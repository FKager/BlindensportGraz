package it.a11y.blindensport.webadmin.auth;

import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class LoginAttemptLimiterTest {
    private static final class MutableClock extends Clock {
        Instant now = Instant.parse("2026-10-17T10:00:00Z");

        @Override
        public ZoneOffset getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(java.time.ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return now;
        }
    }

    @Test
    void locksOutAfterFiveFailuresWithinTheWindow() {
        var clock = new MutableClock();
        var limiter = new LoginAttemptLimiter(5, Duration.ofMinutes(5), clock);
        for (int i = 0; i < 4; i++) {
            limiter.recordFailure("1.2.3.4");
        }
        assertFalse(limiter.isLockedOut("1.2.3.4"));
        limiter.recordFailure("1.2.3.4");
        assertTrue(limiter.isLockedOut("1.2.3.4"));
        assertFalse(limiter.isLockedOut("5.6.7.8"), "other clients are unaffected");
    }

    @Test
    void failuresExpireAfterTheWindow() {
        var clock = new MutableClock();
        var limiter = new LoginAttemptLimiter(5, Duration.ofMinutes(5), clock);
        for (int i = 0; i < 5; i++) {
            limiter.recordFailure("ip");
        }
        clock.now = clock.now.plus(Duration.ofMinutes(5)).plusSeconds(1);
        assertFalse(limiter.isLockedOut("ip"));
    }

    @Test
    void successClearsTheHistory() {
        var limiter = new LoginAttemptLimiter();
        for (int i = 0; i < 5; i++) {
            limiter.recordFailure("ip");
        }
        limiter.recordSuccess("ip");
        assertFalse(limiter.isLockedOut("ip"));
    }

    @Test
    void clientKeyPrefersTheFirstForwardedHop() {
        assertEquals("9.9.9.9", AdminSessions.clientKey("9.9.9.9, 10.0.0.2", "10.0.0.3"));
        assertEquals("10.0.0.3", AdminSessions.clientKey(" ", "10.0.0.3"));
        assertEquals("unknown", AdminSessions.clientKey(null, null));
    }
}
