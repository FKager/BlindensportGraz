package it.a11y.blindensport.webadmin.auth;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * In-memory sliding-window limiter for failed sign-ins (REST and Vaadin
 * sign-in share it). Keyed by client IP, not email, so guessing across many
 * addresses is throttled too (Supabase Auth adds its own limits on top).
 * State resets on restart — its job is slowing down guessing, not banning.
 */
public final class LoginAttemptLimiter {
    private final Map<String, List<Instant>> failuresByClient = new HashMap<>();
    private final int maxFailures;
    private final Duration window;
    private final Clock clock;

    /** 5 failures per 5-minute sliding window per client IP. */
    public LoginAttemptLimiter() {
        this(5, Duration.ofMinutes(5), Clock.systemUTC());
    }

    public LoginAttemptLimiter(int maxFailures, Duration window, Clock clock) {
        this.maxFailures = maxFailures;
        this.window = window;
        this.clock = clock;
    }

    /** True if this client is rejected (429) without even checking credentials. */
    public synchronized boolean isLockedOut(String client) {
        prune(client);
        return failuresByClient.getOrDefault(client, List.of()).size() >= maxFailures;
    }

    public synchronized void recordFailure(String client) {
        prune(client);
        failuresByClient.computeIfAbsent(client, c -> new ArrayList<>()).add(clock.instant());
    }

    /** Only an admin sign-in clears the history — any member's correct password must not. */
    public synchronized void recordSuccess(String client) {
        failuresByClient.remove(client);
    }

    private void prune(String client) {
        List<Instant> failures = failuresByClient.get(client);
        if (failures == null) {
            return;
        }
        Instant cutoff = clock.instant().minus(window);
        failures.removeIf(t -> t.isBefore(cutoff));
        if (failures.isEmpty()) {
            failuresByClient.remove(client);
        }
    }
}
