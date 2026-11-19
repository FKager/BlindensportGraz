package it.a11y.blindensport.webui.club;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;

import static it.a11y.blindensport.webui.members.Dates.CLUB_ZONE;

/** Club data rows (supabase/migrations/20261013000001_club_data.sql) and the app's value conventions. */
public final class ClubModels {
    private ClubModels() {
    }

    /**
     * Built-in sport list, used only until the club's list (table sports,
     * migration 20261119000001) can be read. The field stays text.
     */
    public static final List<String> SPORTS = List.of("Torball", "Goalball", "Blindenfußball", "Showdown", "Judo",
            "Leichtathletik", "Schwimmen", "Ski", "Radfahren");

    /** The three behaviours (events.kind / event_types.behavior). */
    public static final Map<String, String> KINDS = Map.of("training", "Training", "tournament", "Turnier", "event", "Event");

    /** How an event type behaves, as the admin screens say it. */
    public static final Map<String, String> BEHAVIORS = Map.of(
            "training", "wie ein Training", "tournament", "wie ein Turnier", "event", "wie eine Veranstaltung");

    /** Default type per kind (what the database fills in for older app builds). */
    public static String defaultEventType(String kind) {
        return switch (kind == null ? "" : kind) {
            case "training" -> "Training";
            case "tournament" -> "Turnier";
            default -> "";
        };
    }

    /** One entry of the club's sport list. */
    public record Sport(String id, String name, boolean active, int sortOrder) {
    }

    /** One entry of the club's event-type list; behavior is a KINDS key. */
    public record EventType(String id, String name, String behavior, boolean active, int sortOrder) {
    }

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

    /** {@code eventType}: name of an EventType; empty = the default for the kind. */
    public record ClubEvent(String id, String kind, String title, String sport, String location, String street,
                            String zip, String city, String country, Instant startDate, Instant endDate, String notes,
                            String status, Integer durationMinutes, String focusArea, Integer maxTeams,
                            List<String> teamIds, String createdBy, String eventType) {
        public ClubEvent {
            eventType = eventType == null ? "" : eventType;
        }

        /** Without an event type (the default for the kind applies). */
        public ClubEvent(String id, String kind, String title, String sport, String location, String street,
                         String zip, String city, String country, Instant startDate, Instant endDate, String notes,
                         String status, Integer durationMinutes, String focusArea, Integer maxTeams,
                         List<String> teamIds, String createdBy) {
            this(id, kind, title, sport, location, street, zip, city, country, startDate, endDate, notes, status,
                    durationMinutes, focusArea, maxTeams, teamIds, createdBy, "");
        }

        /** The type to show: stored, else the kind's default, else (older plain events) the sport field. */
        public String typeName() {
            if (!eventType.isBlank()) {
                return eventType;
            }
            String byKind = defaultEventType(kind);
            return byKind.isEmpty() ? sport : byKind;
        }

        /** Calendar days covered, at least 1 (Tournament.dayCount). */
        public int dayCount() {
            LocalDate start = LocalDate.ofInstant(startDate, CLUB_ZONE);
            LocalDate end = LocalDate.ofInstant(endDate, CLUB_ZONE);
            return (int) Math.max(1, ChronoUnit.DAYS.between(start, end) + 1);
        }

        /** A training marked "Abgesagt": left out of KostZ, PRAE and the Trainingsfrequenzliste. */
        public boolean isCancelled() {
            return "cancelled".equals(status);
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
