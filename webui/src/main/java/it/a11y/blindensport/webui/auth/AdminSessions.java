package it.a11y.blindensport.webui.auth;

import it.a11y.blindensport.webui.mcp.McpConfig;
import it.a11y.blindensport.webui.supabase.GoTrue;
import it.a11y.blindensport.webui.supabase.Supabase;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.jboss.logging.Logger;

import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.HexFormat;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Sign-in and the in-memory session table shared by the REST API (token in
 * an HttpOnly cookie) and the Vaadin UI (token in the VaadinSession). A
 * restart signs everyone out, which is fine for a handful of admins.
 *
 * Timeouts as before: 30 min idle, 12 h absolute. Every 5 min the role is
 * re-read from the database (as the user), so a role change, a block or a
 * removal reaches an open session quickly.
 */
@ApplicationScoped
public class AdminSessions {
    static final Duration IDLE_TIMEOUT = Duration.ofMinutes(30);
    public static final Duration ABSOLUTE_TIMEOUT = Duration.ofHours(12);
    static final Duration RECHECK_INTERVAL = Duration.ofMinutes(5);

    private static final Logger LOG = Logger.getLogger(AdminSessions.class);
    private static final SecureRandom RANDOM = new SecureRandom();

    private final Supabase supabase;
    private final LoginAttemptLimiter limiter;
    private final Map<String, AdminSession> sessions = new ConcurrentHashMap<>();

    private final LoginAttemptLimiter registrations = new LoginAttemptLimiter();

    @Inject
    McpConfig mcpConfig;

    @Inject
    public AdminSessions(Supabase supabase) {
        this(supabase, new LoginAttemptLimiter());
    }

    public AdminSessions(Supabase supabase, LoginAttemptLimiter limiter) {
        this.supabase = supabase;
        this.limiter = limiter;
    }

    /**
     * Checks the password with Supabase and opens a session.
     *
     * @param client rate-limit key (client IP)
     * @return the opaque session token
     * @throws SignInException 429 locked out, 401 wrong credentials, 403 no web UI access
     */
    public String signIn(String email, String password, String client) {
        return open(email, password, client, false);
    }

    /**
     * The same for the web pages, where any account may sign in that isn't
     * blocked: {@link it.a11y.blindensport.webui.ui.AccessGuard} keeps it to
     * the Übersicht unless it's a coach, admin or root.
     */
    public String signInAccount(String email, String password, String client) {
        return open(email, password, client, true);
    }

    /**
     * Creates an account; Supabase sends the confirmation email. Every attempt
     * counts towards the limit, as each one can send mail.
     *
     * @throws SignInException 429 too many attempts, 400 refused
     */
    public void register(String email, String password, String firstName, String lastName, String client) {
        if (registrations.isLockedOut(client)) {
            throw new SignInException(429, "Zu viele Versuche. Bitte später erneut versuchen.");
        }
        registrations.recordFailure(client);
        String normalized = email.trim().toLowerCase(Locale.ROOT);
        String redirect = mcpConfig.publicUrl() + "/konto-bestaetigen";
        if (!supabase.auth().signUp(normalized, password, firstName, lastName, redirect)) {
            throw new SignInException(400, "Das Konto konnte nicht erstellt werden. Bitte die Angaben prüfen.");
        }
    }

    /**
     * Sends a reset link. Shares the limit of {@link #register}, as each
     * attempt can send mail.
     *
     * @throws SignInException 429 too many attempts
     */
    public void requestPasswordReset(String email, String client) {
        if (registrations.isLockedOut(client)) {
            throw new SignInException(429, "Zu viele Versuche. Bitte später erneut versuchen.");
        }
        registrations.recordFailure(client);
        supabase.auth().requestPasswordReset(email.trim().toLowerCase(Locale.ROOT), mcpConfig.publicUrl() + "/passwort-neu");
    }

    private String open(String email, String password, String client, boolean anyAccount) {
        if (limiter.isLockedOut(client)) {
            throw new SignInException(429, "Zu viele Fehlversuche. Bitte später erneut versuchen.");
        }
        String normalized = email == null ? "" : email.trim().toLowerCase(Locale.ROOT);
        GoTrue.Tokens tokens = password == null || password.isEmpty() || normalized.isEmpty()
                ? null
                : supabase.auth().signIn(normalized, password).orElse(null);
        if (tokens == null) {
            limiter.recordFailure(client);
            throw new SignInException(401, "E-Mail oder Passwort falsch.");
        }
        AdminSession session = new AdminSession(supabase, tokens, Access.NONE);
        Access access = Access.load(session.db(), tokens.userId());
        if (anyAccount ? access.blocked() : !access.canUseWebUi()) {
            LOG.infof("Sign-in refused for %s: role %s", normalized, access.role() == null ? "none" : access.role());
            session.end();
            throw new SignInException(403, access.blocked() ? "Dieses Konto ist gesperrt."
                    : "Dieses Konto hat keinen Zugriff auf die Vereinsverwaltung.");
        }
        if (anyAccount) {
            session.allowPlainAccount();
        }
        limiter.recordSuccess(client);
        session.updateAccess(access, Instant.now());
        String token = newToken();
        dropExpired(Instant.now());
        sessions.put(token, session);
        LOG.infof("Admin signed in: %s (%s)", session.email(), access.role());
        return token;
    }

    /**
     * Checks the person's password again and returns a new Supabase session
     * for them, separate from the one they're signed in with. Same limiter as
     * signing in.
     *
     * @throws SignInException 429 locked out, 401 wrong password
     */
    public GoTrue.Tokens confirmPassword(AdminSession admin, String password, String client) {
        if (limiter.isLockedOut(client)) {
            throw new SignInException(429, "Zu viele Fehlversuche. Bitte später erneut versuchen.");
        }
        GoTrue.Tokens tokens = password == null || password.isEmpty() ? null
                : supabase.auth().signIn(admin.email(), password).orElse(null);
        if (tokens == null) {
            limiter.recordFailure(client);
            throw new SignInException(401, "Das Passwort stimmt nicht.");
        }
        limiter.recordSuccess(client);
        return tokens;
    }

    /** The session for a token, or empty if unknown, expired, or no longer allowed. */
    public Optional<AdminSession> get(String token) {
        if (token == null || token.isEmpty()) {
            return Optional.empty();
        }
        AdminSession session = sessions.get(token);
        if (session == null) {
            return Optional.empty();
        }
        Instant now = Instant.now();
        if (session.ended() || isExpired(session, now)) {
            remove(token);
            return Optional.empty();
        }
        if (Duration.between(session.lastChecked(), now).compareTo(RECHECK_INTERVAL) >= 0) {
            Access access;
            try {
                access = Access.load(session.db(), session.userId());
            } catch (RuntimeException e) {
                // Fail closed, like the Swift server: an unverifiable session ends.
                LOG.infof("Session recheck failed for %s: %s", session.email(), e.getMessage());
                access = Access.NONE;
            }
            if (session.allowsPlainAccount() ? access.blocked() : !access.canUseWebUi()) {
                remove(token);
                return Optional.empty();
            }
            session.updateAccess(access, now);
        }
        session.touch(now);
        return Optional.of(session);
    }

    public void remove(String token) {
        if (token == null) {
            return;
        }
        AdminSession session = sessions.remove(token);
        if (session != null) {
            session.end();
        }
    }

    private void dropExpired(Instant now) {
        sessions.entrySet().removeIf(e -> {
            boolean expired = e.getValue().ended() || isExpired(e.getValue(), now);
            if (expired) {
                e.getValue().end();
            }
            return expired;
        });
    }

    private static boolean isExpired(AdminSession session, Instant now) {
        return Duration.between(session.lastSeen(), now).compareTo(IDLE_TIMEOUT) >= 0
                || Duration.between(session.created(), now).compareTo(ABSOLUTE_TIMEOUT) >= 0;
    }

    /**
     * Rate-limit key: the first X-Forwarded-For hop, else the TCP peer.
     * Trusting the header is safe ONLY because docker-compose.yml never
     * publishes this service's port — the sole path in is through Caddy.
     * Run without that proxy, the header is attacker-controlled.
     */
    public static String clientKey(String forwardedFor, String remoteAddress) {
        if (forwardedFor != null) {
            String first = forwardedFor.split(",")[0].trim();
            if (!first.isEmpty()) {
                return first;
            }
        }
        return remoteAddress == null ? "unknown" : remoteAddress;
    }

    private static String newToken() {
        byte[] bytes = new byte[32];
        RANDOM.nextBytes(bytes);
        return HexFormat.of().formatHex(bytes);
    }
}
