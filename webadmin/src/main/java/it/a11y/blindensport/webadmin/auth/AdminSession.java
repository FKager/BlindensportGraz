package it.a11y.blindensport.webadmin.auth;

import it.a11y.blindensport.webadmin.supabase.GoTrue;
import it.a11y.blindensport.webadmin.supabase.Postgrest;
import it.a11y.blindensport.webadmin.supabase.Supabase;

import java.time.Duration;
import java.time.Instant;
import java.util.Set;
import java.util.UUID;

/**
 * One signed-in admin. Holds their Supabase tokens server-side (never sent
 * to the browser) and refreshes them shortly before they expire; if
 * Supabase refuses the refresh (account blocked or deleted, session revoked)
 * the session is over. All data access goes through {@link #db()}, i.e. as
 * this user, so RLS decides what they may read and write.
 */
public final class AdminSession {
    private static final Duration REFRESH_MARGIN = Duration.ofSeconds(60);

    private final Supabase supabase;
    private final UUID userId;
    private final String email;
    private final Instant created;
    private final Postgrest db;
    private GoTrue.Tokens tokens;
    private Access access;
    private Instant lastSeen;
    private Instant lastChecked;
    private boolean ended;

    public AdminSession(Supabase supabase, GoTrue.Tokens tokens, Access access) {
        this.supabase = supabase;
        this.userId = tokens.userId();
        this.email = tokens.email();
        this.tokens = tokens;
        this.access = access;
        this.created = Instant.now();
        this.lastSeen = created;
        this.lastChecked = created;
        this.db = supabase.asUser(this::accessToken);
    }

    public UUID userId() {
        return userId;
    }

    public String email() {
        return email;
    }

    public synchronized String role() {
        return access.role();
    }

    public synchronized Set<String> permissions() {
        return access.permissions();
    }

    public boolean can(String permission) {
        return permissions().contains(permission);
    }

    public String roleName() {
        String role = role();
        return Permission.ROLE_NAMES.getOrDefault(role, role);
    }

    /** PostgREST as this admin. */
    public Postgrest db() {
        return db;
    }

    /** A valid access token, refreshed if it expires within a minute. */
    public synchronized String accessToken() {
        if (ended) {
            throw new SessionExpiredException();
        }
        if (Instant.now().plus(REFRESH_MARGIN).isAfter(tokens.expiresAt())) {
            GoTrue.Tokens fresh = supabase.auth().refresh(tokens.refreshToken()).orElse(null);
            if (fresh == null) {
                ended = true;
                throw new SessionExpiredException();
            }
            tokens = fresh;
        }
        return tokens.accessToken();
    }

    synchronized Instant created() {
        return created;
    }

    synchronized Instant lastSeen() {
        return lastSeen;
    }

    synchronized Instant lastChecked() {
        return lastChecked;
    }

    synchronized void touch(Instant now) {
        lastSeen = now;
    }

    synchronized void updateAccess(Access fresh, Instant now) {
        access = fresh;
        lastChecked = now;
    }

    synchronized boolean ended() {
        return ended;
    }

    /** Marks the session over and revokes its refresh token at Supabase. */
    void end() {
        String token;
        synchronized (this) {
            if (ended) {
                return;
            }
            ended = true;
            token = tokens.accessToken();
        }
        supabase.auth().signOut(token);
    }
}
