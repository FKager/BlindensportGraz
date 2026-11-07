package it.a11y.blindensport.webadmin.mcp;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import it.a11y.blindensport.webadmin.auth.Access;
import it.a11y.blindensport.webadmin.supabase.GoTrue;
import it.a11y.blindensport.webadmin.supabase.Postgrest;
import it.a11y.blindensport.webadmin.supabase.Supabase;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.HexFormat;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Turns a bearer token into an {@link McpUser}. A client sends many requests in
 * a row, so a result is kept for a minute, never past the token's own expiry;
 * a blocked account or changed role therefore counts within a minute, as RLS
 * applies immediately anyway.
 */
@ApplicationScoped
public class McpIdentity {
    /** Why a token got no user. */
    public enum Refusal { INVALID_TOKEN, NO_ACCESS }

    public record Outcome(McpUser user, Refusal refusal) {
    }

    private record Cached(McpUser user, Instant until) {
    }

    private static final Duration CACHE_TIME = Duration.ofMinutes(1);
    private static final int MAX_CACHED = 1000;

    private final Map<String, Cached> cache = new ConcurrentHashMap<>();

    @Inject
    Supabase supabase;

    @Inject
    ObjectMapper json;

    public Outcome resolve(String token) {
        Instant now = Instant.now();
        String key = sha256(token);
        Cached cached = cache.get(key);
        if (cached != null && cached.until().isAfter(now)) {
            return new Outcome(cached.user(), null);
        }
        cache.remove(key);
        Optional<GoTrue.User> account = supabase.auth().user(token);
        if (account.isEmpty()) {
            return new Outcome(null, Refusal.INVALID_TOKEN);
        }
        Postgrest db = supabase.asUser(() -> token);
        Access access = Access.load(db, account.get().id());
        if (!access.canUseWebAdmin()) {
            return new Outcome(null, Refusal.NO_ACCESS);
        }
        McpUser user = new McpUser(account.get().id(), account.get().email(), access, db);
        Instant until = now.plus(CACHE_TIME);
        Instant expiry = expiry(token);
        if (expiry != null && expiry.isBefore(until)) {
            until = expiry;
        }
        if (cache.size() >= MAX_CACHED) {
            cache.entrySet().removeIf(e -> !e.getValue().until().isAfter(now));
            if (cache.size() >= MAX_CACHED) {
                cache.clear();
            }
        }
        cache.put(key, new Cached(user, until));
        return new Outcome(user, null);
    }

    /** The JWT's exp. Only shortens caching of a token GoTrue has just accepted, so the unverified read is fine. */
    private Instant expiry(String token) {
        try {
            String[] parts = token.split("\\.");
            JsonNode payload = json.readTree(Base64.getUrlDecoder().decode(parts[1]));
            return payload.hasNonNull("exp") ? Instant.ofEpochSecond(payload.get("exp").asLong()) : null;
        } catch (java.io.IOException | IllegalArgumentException | ArrayIndexOutOfBoundsException e) {
            return null;
        }
    }

    /** Tokens are kept out of the map's keys, in case anything ever dumps it. */
    private static String sha256(String token) {
        try {
            return HexFormat.of().formatHex(
                    MessageDigest.getInstance("SHA-256").digest(token.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
