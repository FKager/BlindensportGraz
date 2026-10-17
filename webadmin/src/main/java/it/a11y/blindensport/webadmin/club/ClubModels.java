package it.a11y.blindensport.webadmin.club;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;

import static it.a11y.blindensport.webadmin.members.Dates.CLUB_ZONE;

/** Club data rows (supabase/migrations/20261013000001_club_data.sql) and the app's value conventions. */
public final class ClubModels {
    private ClubModels() {
    }

    /** Sports the app knows; the field stays free text (SportIcon / Sport.swift). */
    public static final List<String> SPORTS = List.of("Torball", "Goalball", "Blindenfußball", "Showdown", "Judo",
            "Leichtathletik", "Schwimmen", "Ski", "Radfahren");

    public static final Map<String, String> KINDS = Map.of("training", "Training", "tournament", "Turnier", "event", "Event");

    public static final Map<String, String> TOURNAMENT_STATUS = Map.of(
            "planned", "Geplant", "ongoing", "Laufend", "finished", "Beendet");
    public static final Map<String, String> TRAINING_STATUS = Map.of(
            "open", "Offen", "held", "Durchgeführt", "cancelled", "Abgesagt");

    public static final Map<String, String> MEMBERSHIP_ROLES = Map.of(
            "player", "Spieler:in", "coach", "Trainer:in", "assistant", "Assistent:in");

    public static final Map<String, String> BUDGET_CATEGORIES = Map.of(
            "fixedSubsidy", "Fixer Zuschuss", "donation", "Spende", "eventCost", "Veranstaltungskosten",
            "otherExpense", "Sonstige Ausgabe");

    public record Team(String id, String name, String sport, String description) {
    }

    /** Exactly one of memberId / userId is normally set. */
    public record Membership(String id, String teamId, String memberId, String userId, String role, Instant joinedAt) {
        /** Coaches and assistants get PRAE (MembershipRole.isHelfer). */
        public boolean isHelper() {
            return "coach".equals(role) || "assistant".equals(role);
        }
    }

    public record ClubEvent(String id, String kind, String title, String sport, String location, String street,
                            String zip, String city, String country, Instant startDate, Instant endDate, String notes,
                            String status, Integer durationMinutes, String focusArea, Integer maxTeams,
                            List<String> teamIds, String createdBy) {
        /** Calendar days covered, at least 1 (Tournament.dayCount). */
        public int dayCount() {
            LocalDate start = LocalDate.ofInstant(startDate, CLUB_ZONE);
            LocalDate end = LocalDate.ofInstant(endDate, CLUB_ZONE);
            return (int) Math.max(1, ChronoUnit.DAYS.between(start, end) + 1);
        }

        /** Highest PRAE per helper: €90 per training, €120 per tournament day (PraeCalculator.dailyCap). */
        public int maxPrae() {
            return "tournament".equals(kind) ? 120 * dayCount() : 90;
        }
    }

    public record Attendance(String id, String eventId, String membershipId, boolean attended, BigDecimal praeAmount) {
    }

    public record TrainingFavorite(String id, String title, String sport, int weekday, int startHour, int startMinute,
                                   int endHour, int endMinute, String location, String street, String zip,
                                   String city, String country, List<String> teamIds) {
    }

    /** {@code amount} is always positive; income vs. expense comes from the category. */
    public record BudgetEntry(String id, String category, BigDecimal amount, Instant date, String note, String eventId,
                              String createdBy) {
        public boolean isIncome() {
            return "fixedSubsidy".equals(category) || "donation".equals(category);
        }
    }

    public record WelcomeContent(String id, String markdown, boolean enabled) {
    }
}
