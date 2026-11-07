package it.a11y.blindensport.webui.mcp;

import com.fasterxml.jackson.databind.JsonNode;
import it.a11y.blindensport.webui.auth.SessionExpiredException;
import it.a11y.blindensport.webui.members.Dates;
import it.a11y.blindensport.webui.supabase.GoTrue;
import it.a11y.blindensport.webui.supabase.Postgrest;
import it.a11y.blindensport.webui.supabase.Supabase;
import it.a11y.blindensport.webui.supabase.SupabaseHttp;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Base64;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

import static it.a11y.blindensport.webui.supabase.Postgrest.eq;
import static it.a11y.blindensport.webui.supabase.Postgrest.order;

/**
 * Personal access tokens for MCP clients. A token stands for one Supabase
 * session of its owner, opened when they confirmed their password, so the
 * client acts as that person and RLS applies. The database holds a hash of the
 * token and the session's refresh token encrypted with a key derived from the
 * token: without the token neither is any use, and this server keeps no key.
 */
@ApplicationScoped
public class McpTokens {
    public static final String PREFIX = "bsg_mcp_";
    public static final Duration LIFETIME = Duration.ofDays(90);
    private static final Duration REFRESH_MARGIN = Duration.ofMinutes(1);
    private static final int IV_BYTES = 12;
    private static final int TAG_BITS = 128;
    private static final SecureRandom RANDOM = new SecureRandom();

    public record Info(String id, String label, Instant created, Instant lastUsed, Instant expires) {
    }

    /** A token just issued. {@code token} is shown once; it isn't stored anywhere. */
    public record Issued(String token, Instant expires) {
    }

    private final Map<String, Live> live = new ConcurrentHashMap<>();

    @Inject
    Supabase supabase;

    public Issued create(Postgrest db, GoTrue.Tokens session, String label) {
        if (label == null || label.isBlank() || label.trim().length() > 80) {
            throw new IllegalArgumentException("Bitte einen Namen für das Token angeben (höchstens 80 Zeichen).");
        }
        byte[] random = new byte[32];
        RANDOM.nextBytes(random);
        String token = PREFIX + HexFormat.of().formatHex(random);
        Instant expires = Instant.now().plus(LIFETIME);
        Map<String, Object> row = new HashMap<>();
        row.put("user_id", session.userId().toString());
        row.put("label", label.trim());
        row.put("token_hash", hash(token));
        row.put("sealed_session", seal(token, session.refreshToken()));
        row.put("expires_at", Dates.formatTimestamp(expires));
        db.insert("mcp_tokens", row);
        return new Issued(token, expires);
    }

    public List<Info> list(Postgrest db) {
        List<Info> tokens = new ArrayList<>();
        db.select("mcp_tokens", "id,label,created_at,last_used_at,expires_at", order("created_at.desc")).forEach(r ->
                tokens.add(new Info(r.path("id").asText(), r.path("label").asText(""),
                        Dates.parseTimestamp(r.path("created_at").asText(null)).orElse(null),
                        Dates.parseTimestamp(r.path("last_used_at").asText(null)).orElse(null),
                        Dates.parseTimestamp(r.path("expires_at").asText(null)).orElse(null))));
        return tokens;
    }

    /** RLS keeps this to the owner's own tokens. {@link #open} notices within {@link McpIdentity}'s cache time. */
    public void revoke(Postgrest db, String id) {
        // Only id comes back: a delete returns the row, and the sealed columns aren't readable.
        db.delete("mcp_tokens", eq("id", id), new SupabaseHttp.Param("select", "id"));
    }

    /** The session behind a token; empty if unknown, revoked or expired. */
    public Optional<Live> open(String token) {
        if (token == null || !token.startsWith(PREFIX)) {
            return Optional.empty();
        }
        String key = hash(token);
        JsonNode rows = supabase.asAnon().rpc("mcp_token_session", Map.of("p_token_hash", key));
        if (!rows.isArray() || rows.isEmpty()) {
            live.remove(key);
            return Optional.empty();
        }
        return Optional.of(live.computeIfAbsent(key, k -> new Live(token, k)));
    }

    /** One token's Supabase session, refreshed when needed. */
    public final class Live {
        private final String token;
        private final String key;
        private GoTrue.Tokens session;

        private Live(String token, String key) {
            this.token = token;
            this.key = key;
        }

        /** Signs in on first use, and throws {@link SessionExpiredException} if Supabase refuses. */
        public synchronized GoTrue.Tokens session() {
            if (session == null || Instant.now().plus(REFRESH_MARGIN).isAfter(session.expiresAt())) {
                session = refresh();
            }
            return session;
        }

        public String accessToken() {
            return session().accessToken();
        }

        /** Refresh tokens work once, so the new one is saved before the old session is used any further. */
        private GoTrue.Tokens refresh() {
            JsonNode rows = supabase.asAnon().rpc("mcp_token_session", Map.of("p_token_hash", key));
            if (!rows.isArray() || rows.isEmpty()) {
                throw new SessionExpiredException();
            }
            String refreshToken = unseal(token, rows.get(0).path("sealed_session").asText());
            GoTrue.Tokens fresh = supabase.auth().refresh(refreshToken).orElseThrow(SessionExpiredException::new);
            supabase.asAnon().rpc("mcp_token_update",
                    Map.of("p_token_hash", key, "p_sealed_session", seal(token, fresh.refreshToken())));
            return fresh;
        }
    }

    static String hash(String token) {
        return HexFormat.of().formatHex(sha256("bsg-mcp-token-id:" + token));
    }

    /** AES-256-GCM with a key that only the token can produce; {@code iv + ciphertext}, base64. */
    static String seal(String token, String secret) {
        try {
            byte[] iv = new byte[IV_BYTES];
            RANDOM.nextBytes(iv);
            Cipher cipher = cipher(Cipher.ENCRYPT_MODE, token, iv);
            byte[] sealed = cipher.doFinal(secret.getBytes(StandardCharsets.UTF_8));
            return Base64.getEncoder().encodeToString(ByteBuffer.allocate(iv.length + sealed.length).put(iv).put(sealed).array());
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }

    static String unseal(String token, String sealed) {
        try {
            byte[] all = Base64.getDecoder().decode(sealed);
            byte[] iv = java.util.Arrays.copyOf(all, IV_BYTES);
            Cipher cipher = cipher(Cipher.DECRYPT_MODE, token, iv);
            return new String(cipher.doFinal(all, IV_BYTES, all.length - IV_BYTES), StandardCharsets.UTF_8);
        } catch (GeneralSecurityException | IllegalArgumentException e) {
            throw new SessionExpiredException();
        }
    }

    private static Cipher cipher(int mode, String token, byte[] iv) throws GeneralSecurityException {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(mode, new SecretKeySpec(sha256("bsg-mcp-token-key:" + token), "AES"), new GCMParameterSpec(TAG_BITS, iv));
        return cipher;
    }

    private static byte[] sha256(String value) {
        try {
            return MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
