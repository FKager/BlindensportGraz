package it.a11y.blindensport.webui.mcp;

import it.a11y.blindensport.webui.auth.Access;
import it.a11y.blindensport.webui.auth.SessionExpiredException;
import it.a11y.blindensport.webui.supabase.GoTrue;
import it.a11y.blindensport.webui.supabase.Postgrest;
import it.a11y.blindensport.webui.supabase.Supabase;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Turns a token into an {@link McpUser}. A client sends many requests in a row,
 * so a result is kept for a minute: a revoked token, a blocked account or a
 * changed role counts within a minute. RLS applies immediately anyway.
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
    McpTokens tokens;

    public Outcome resolve(String token) {
        Instant now = Instant.now();
        String key = McpTokens.hash(token);
        Cached cached = cache.get(key);
        if (cached != null && cached.until().isAfter(now)) {
            return new Outcome(cached.user(), null);
        }
        cache.remove(key);
        Optional<McpTokens.Live> live = tokens.open(token);
        if (live.isEmpty()) {
            return new Outcome(null, Refusal.INVALID_TOKEN);
        }
        GoTrue.Tokens session;
        try {
            session = live.get().session();
        } catch (SessionExpiredException e) {
            return new Outcome(null, Refusal.INVALID_TOKEN);
        }
        Postgrest db = supabase.asUser(live.get()::accessToken);
        Access access = Access.load(db, session.userId());
        if (!access.canUseWebUi()) {
            return new Outcome(null, Refusal.NO_ACCESS);
        }
        McpUser user = new McpUser(session.userId(), session.email(), access, db);
        if (cache.size() >= MAX_CACHED) {
            cache.entrySet().removeIf(e -> !e.getValue().until().isAfter(now));
            if (cache.size() >= MAX_CACHED) {
                cache.clear();
            }
        }
        cache.put(key, new Cached(user, now.plus(CACHE_TIME)));
        return new Outcome(user, null);
    }
}
