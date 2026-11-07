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

    /** The account behind an access token: id and email. */
    public record User(UUID id, String email) {
    }

    /**
     * Who an access token belongs to, asked of GoTrue so a forged or revoked
     * token doesn't count. Works for app, web admin and OAuth (MCP) tokens.
     * Empty when GoTrue refuses the token.
     */
    public Optional<User> user(String accessToken) {
        SupabaseHttp.Result result = http.send("GET", "auth/v1/user", List.of(), null, Map.of(), anonKey, accessToken);
        if (result.status() >= 400 && result.status() < 500) {
            return Optional.empty();
        }
        JsonNode node = http.parse(http.check(result, "get user").body());
        return Optional.of(new User(UUID.fromString(node.path("id").asText()), node.path("email").asText("")));
    }

    /**
     * An MCP client's pending sign-in (OAuth 2.1 server), as the consent page
     * shows it. A client this user already approved has {@code redirectUrl}
     * set instead and needs no second question.
     */
    public record Authorization(String clientName, String redirectUri, String redirectUrl) {
    }

    public Authorization oauthAuthorization(String accessToken, String authorizationId) {
        SupabaseHttp.Result result = http.send("GET", "auth/v1/oauth/authorizations/" + authorizationId, List.of(), null,
                Map.of(), anonKey, accessToken);
        JsonNode node = http.parse(http.check(result, "get authorization").body());
        return new Authorization(node.path("client").path("name").asText(""), node.path("redirect_uri").asText(""),
                node.path("redirect_url").asText(null));
    }

    /** Approves or denies; returns where to send the browser back to, which is the client's redirect URI. */
    public String oauthConsent(String accessToken, String authorizationId, boolean approve) {
        SupabaseHttp.Result result = http.send("POST", "auth/v1/oauth/authorizations/" + authorizationId + "/consent",
                List.of(), Map.of("action", approve ? "approve" : "deny"), Map.of(), anonKey, accessToken);
        return http.parse(http.check(result, "oauth consent").body()).path("redirect_url").asText();
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
