package it.a11y.blindensport.webadmin.members;

import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.time.temporal.ChronoUnit;
import java.util.Optional;

/** Date conventions shared with the Swift tooling and the app. */
public final class Dates {
    public static final ZoneId CLUB_ZONE = ZoneId.of("Europe/Vienna");
    private static final DateTimeFormatter GERMAN_DAY = DateTimeFormatter.ofPattern("dd.MM.uuuu");

    private Dates() {
    }

    /** timestamptz as PostgREST writes it, with or without fractional seconds. */
    public static Optional<Instant> parseTimestamp(String raw) {
        if (raw == null || raw.isBlank()) {
            return Optional.empty();
        }
        try {
            return Optional.of(OffsetDateTime.parse(raw).toInstant());
        } catch (DateTimeParseException e) {
            return Optional.empty();
        }
    }

    /** ISO 8601 with fractional seconds, as written to timestamptz columns. */
    public static String formatTimestamp(Instant instant) {
        return DateTimeFormatter.ISO_INSTANT.format(instant.truncatedTo(ChronoUnit.MILLIS));
    }

    /** API output: ISO 8601 without fractional seconds (what Vapor's encoder produced). */
    public static String formatApi(Instant instant) {
        return DateTimeFormatter.ISO_INSTANT.format(instant.truncatedTo(ChronoUnit.SECONDS));
    }

    /** Calendar day of an instant as the club sees it (Europe/Vienna), "yyyy-MM-dd". */
    public static String day(Instant instant) {
        return LocalDate.ofInstant(instant, CLUB_ZONE).toString();
    }

    /** "yyyy-MM-dd" → midnight UTC, the instant a date-only import produces, so round trips keep the day. */
    public static Optional<Instant> fromDay(String day) {
        try {
            return Optional.of(LocalDate.parse(day).atStartOfDay(ZoneOffset.UTC).toInstant());
        } catch (DateTimeParseException | NullPointerException e) {
            return Optional.empty();
        }
    }

    /** Accepts full ISO 8601 or "yyyy-MM-dd" (midnight UTC). */
    public static Optional<Instant> parseJoinedAt(String raw) {
        if (raw == null || raw.isBlank()) {
            return Optional.empty();
        }
        String trimmed = raw.trim();
        Optional<Instant> instant = parseTimestamp(trimmed);
        return instant.isPresent() ? instant : fromDay(trimmed);
    }

    /** ISO 8601, "yyyy-MM-dd" or the German "dd.MM.yyyy" (all midnight UTC for date-only). */
    public static Optional<Instant> parseFlexible(String raw) {
        Optional<Instant> instant = parseJoinedAt(raw);
        if (instant.isPresent() || raw == null || raw.isBlank()) {
            return instant;
        }
        try {
            return Optional.of(LocalDate.parse(raw.trim(), GERMAN_DAY).atStartOfDay(ZoneOffset.UTC).toInstant());
        } catch (DateTimeParseException e) {
            return Optional.empty();
        }
    }
}
