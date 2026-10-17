package it.a11y.blindensport.webadmin.supabase;

import com.fasterxml.jackson.databind.JsonNode;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import static it.a11y.blindensport.webadmin.supabase.SupabaseHttp.Param;

/** Supabase Auth (GoTrue) with the anon key: sign in, refresh, sign out. */
public final class GoTrue {
    /** A session GoTrue issued. Kept server-side only, never sent to the browser. */
    public record Tokens(UUID userId, String email, String accessToken, String refreshToken, Instant expiresAt) {
    }

    private final SupabaseHttp http;
    private final String anonKey;

    public GoTrue(SupabaseHttp http, String anonKey) {
        this.http = http;
        this.anonKey = anonKey;
    }

    /** Password grant. Empty for wrong credentials or an unconfirmed email (400/401). */
    public Optional<Tokens> signIn(String email, String password) {
        SupabaseHttp.Result result = http.send("POST", "auth/v1/token", List.of(new Param("grant_type", "password")),
                Map.of("email", email, "password", password), Map.of(), anonKey, null);
        if (result.status() == 400 || result.status() == 401) {
            return Optional.empty();
        }
        return Optional.of(tokens(http.check(result, "sign in").body()));
    }

    /**
     * New tokens for a refresh token. Empty when GoTrue refuses it — the
     * account was blocked (banned) or deleted, or the session was revoked.
     */
    public Optional<Tokens> refresh(String refreshToken) {
        SupabaseHttp.Result result = http.send("POST", "auth/v1/token",
                List.of(new Param("grant_type", "refresh_token")),
                Map.of("refresh_token", refreshToken), Map.of(), anonKey, null);
        if (result.status() >= 400 && result.status() < 500) {
            return Optional.empty();
        }
        return Optional.of(tokens(http.check(result, "refresh session").body()));
    }

    /** Revokes this session's refresh token. Best effort. */
    public void signOut(String accessToken) {
        try {
            http.send("POST", "auth/v1/logout", List.of(new Param("scope", "local")), null, Map.of(),
                    anonKey, accessToken);
        } catch (RuntimeException ignored) {
            // The local session is gone either way.
        }
    }

    private Tokens tokens(String body) {
        JsonNode node = http.parse(body);
        JsonNode user = node.path("user");
        long expiresIn = node.path("expires_in").asLong(3600);
        Instant expiresAt = node.hasNonNull("expires_at")
                ? Instant.ofEpochSecond(node.get("expires_at").asLong())
                : Instant.now().plusSeconds(expiresIn);
        return new Tokens(UUID.fromString(user.path("id").asText()), user.path("email").asText(""),
                node.path("access_token").asText(), node.path("refresh_token").asText(), expiresAt);
    }
}
