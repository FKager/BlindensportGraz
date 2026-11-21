package it.a11y.blindensport.webui.mcp;

import it.a11y.blindensport.webui.club.TournamentDocuments;
import it.a11y.blindensport.webui.club.ClubModels.Attendance;
import it.a11y.blindensport.webui.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webui.club.ClubModels.Membership;
import it.a11y.blindensport.webui.club.ClubModels.Team;
import it.a11y.blindensport.webui.club.ClubModels;
import it.a11y.blindensport.webui.club.ClubStore;
import it.a11y.blindensport.webui.members.Dates;
import it.a11y.blindensport.webui.members.MemberRecord;
import it.a11y.blindensport.webui.members.MemberStore;
import it.a11y.blindensport.webui.prae.PraeCalculator;
import it.a11y.blindensport.webui.prae.PraeForm;
import it.a11y.blindensport.webui.prae.PraeService;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.OffsetDateTime;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import static it.a11y.blindensport.webui.members.Dates.CLUB_ZONE;

/**
 * Shared argument parsing and result shapes of the MCP tools
 * ({@link MemberTools}, {@link EventTools}, {@link ReportTools},
 * {@link TournamentDocumentTools}). Three rules hold for every tool:
 * <ul>
 *   <li>It runs as the signed-in person, so RLS and their role decide.</li>
 *   <li>Protected fields (SVNR, IBAN, birth date, medical exam, disability,
 *       consents) never appear in a result and can't be written, since
 *       anything returned reaches the AI behind the client. Member results
 *       are built from an explicit list of fields for that reason.</li>
 *   <li>Nothing deletes, except a single tournament document
 *       (delete_tournament_document, marked destructive). A member is only
 *       flagged with status "delete"; root removes them in the app or web UI.</li>
 * </ul>
 */
final class McpToolSupport {
    static final String ID_HINT = " Get ids from list_members, list_teams or list_events.";

    private McpToolSupport() {
    }
    // ------------------------------------------------------------ helpers

    interface Action {
        Object run(McpUser user);
    }


    static void requirePermission(McpUser user, String permission) {
        if (!user.can(permission)) {
            throw new IllegalArgumentException("Dieses Konto hat keine Berechtigung dafür (" + permission + ").");
        }
    }

    static List<PraeForm> forms(McpUser user, String eventId, Integer month, Integer year, String memberId,
                                        boolean withPrivate) {
        ClubStore club = user.club();
        PraeService prae = new PraeService(club, user.roster());
        String member = memberId == null ? null : id(memberId, "member_id");
        if (eventId != null) {
            return prae.forEvent(event(club, eventId), member, withPrivate);
        }
        if (month == null || year == null || month < 1 || month > 12) {
            throw new IllegalArgumentException("Bitte event_id oder month (1–12) und year angeben.");
        }
        return prae.forMonth(month, year, member, withPrivate);
    }

    static Map<String, Object> formRow(PraeForm form) {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("person", form.person().displayName());
        row.put("kind", form.tournament() ? "tournament" : "training");
        row.put("purpose", form.purpose());
        row.put("month", form.month());
        row.put("year", form.year());
        row.put("total", form.total());
        row.put("days", form.entries().stream().map(e -> {
            Map<String, Object> day = new LinkedHashMap<>();
            day.put("day", e.day());
            day.put("amount", e.amount());
            return day;
        }).toList());
        row.put("warnings", form.capWarnings());
        return row;
    }

    /** Who a membership belongs to, without protected data. */
    record Names(Map<String, String> members, Map<String, PraeCalculator.AccountName> accounts) {
        String of(Membership m) {
            if (m.userId() != null && accounts.containsKey(m.userId())) {
                return (accounts.get(m.userId()).firstName() + " " + accounts.get(m.userId()).lastName()).trim();
            }
            return m.memberId() == null ? "?" : members.getOrDefault(m.memberId(), "?");
        }
    }

    static Names names(McpUser user, ClubStore club) {
        Map<String, String> members = new HashMap<>();
        user.roster().all(false).forEach(m -> members.put(m.id().toLowerCase(Locale.ROOT), m.fullName()));
        return new Names(members, club.accounts());
    }

    static Map<String, Object> membershipRow(Membership m, Names names) {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("membership_id", m.id());
        row.put("member_id", m.memberId());
        row.put("name", names.of(m));
        row.put("role", m.role());
        return row;
    }

    /** Memberships of the event's teams, each person once, by name (SportEvent.rosterAcrossTeams). */
    static List<Membership> roster(ClubEvent event, List<Membership> all, Names names) {
        Set<String> seen = new HashSet<>();
        List<Membership> result = new ArrayList<>();
        for (String teamId : event.teamIds()) {
            for (Membership m : all) {
                String key = m.userId() != null ? m.userId() : m.memberId() != null ? m.memberId() : m.id();
                if (m.teamId().equals(teamId) && seen.add(key)) {
                    result.add(m);
                }
            }
        }
        result.sort(Comparator.comparing(names::of));
        return result;
    }

    static Map<String, String> teamNames(ClubStore club) {
        Map<String, String> names = new HashMap<>();
        club.teams().forEach(t -> names.put(t.id(), t.name()));
        return names;
    }

    static List<String> teamIds(ClubStore club, List<String> ids) {
        if (ids == null) {
            return List.of();
        }
        Set<String> known = new HashSet<>();
        club.teams().forEach(t -> known.add(t.id()));
        List<String> result = new ArrayList<>();
        for (String raw : ids) {
            String teamId = id(raw, "team_ids");
            if (!known.contains(teamId)) {
                throw new IllegalArgumentException("Das Team " + teamId + " gibt es nicht." + ID_HINT);
            }
            result.add(teamId);
        }
        return result;
    }

    static BigDecimal prae(AttendanceChange change, Membership m, Attendance old, ClubEvent event, Names names) {
        if (!change.attended()) {
            return null;
        }
        if (change.praeAmount() == null) {
            return old == null ? null : old.praeAmount();
        }
        double amount = change.praeAmount();
        if (amount == 0) {
            return null;
        }
        if (!m.isHelper()) {
            throw new IllegalArgumentException(names.of(m) + " ist weder Trainer:in noch Assistent:in und bekommt keine PRAE.");
        }
        if (amount < 0 || amount > event.maxPrae() || amount % 5 != 0) {
            throw new IllegalArgumentException("PRAE für " + names.of(m) + ": erlaubt sind 0 bis " + event.maxPrae()
                    + " € in 5-€-Schritten.");
        }
        return BigDecimal.valueOf(amount);
    }

    static Map<String, Object> memberSummary(MemberRecord m) {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("member_id", m.id());
        row.put("first_name", m.firstName());
        row.put("last_name", m.lastName());
        row.put("status", m.status());
        row.put("member_number", m.memberNumber());
        row.put("default_function", m.defaultFunction());
        row.put("member_of_gvsc", m.memberOfGVSC());
        return row;
    }

    /** An allow-list on purpose: a new protected field stays out until someone adds it here. */
    static Map<String, Object> memberDetails(MemberRecord m) {
        Map<String, Object> row = memberSummary(m);
        row.put("title", m.title());
        row.put("gender", m.gender());
        row.put("street", m.street());
        row.put("zip", m.zip());
        row.put("city", m.city());
        row.put("country", m.country());
        row.put("email", m.email());
        row.put("phone", m.phone());
        row.put("sport_id", m.sportId());
        row.put("joined_at", Dates.day(m.joinedAt()));
        row.put("notes", m.notes());
        return row;
    }

    static Map<String, Object> eventRow(ClubEvent e) {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("event_id", e.id());
        row.put("kind", e.kind());
        row.put("event_type", e.typeName());
        row.put("title", e.title());
        row.put("sport", e.sport());
        row.put("start", LocalDateTime.ofInstant(e.startDate(), CLUB_ZONE).toString());
        row.put("end", LocalDateTime.ofInstant(e.endDate(), CLUB_ZONE).toString());
        row.put("status", e.status());
        row.put("location", e.location());
        row.put("city", e.city());
        if (e.durationMinutes() != null) {
            row.put("duration_minutes", e.durationMinutes());
        }
        return row;
    }

    static MemberRecord member(McpUser user, String memberId) {
        MemberStore roster = user.roster();
        return roster.get(id(memberId, "member_id"), false)
                .orElseThrow(() -> new IllegalArgumentException("Dieses Mitglied gibt es nicht." + ID_HINT));
    }

    /**
     * The event type for {@code kind}: blank = the kind's default; otherwise
     * it must be on the club's list with that behaviour (exact name, case
     * ignored). If the list can't be read, the name is taken as given.
     */
    static String eventType(ClubStore club, String kind, String requested) {
        if (requested == null || requested.isBlank()) {
            return ClubModels.defaultEventType(kind);
        }
        String wanted = ClubStore.cleanName(requested);
        List<ClubModels.EventType> types;
        try {
            types = club.eventTypes();
        } catch (RuntimeException e) {
            return wanted;
        }
        return types.stream().filter(t -> t.name().equalsIgnoreCase(wanted)).findFirst()
                .map(t -> {
                    if (!t.behavior().equals(kind)) {
                        throw new IllegalArgumentException("Die Art " + t.name() + " verhält sich wie " + t.behavior()
                                + ", nicht wie " + kind + ".");
                    }
                    return t.name();
                })
                .orElseThrow(() -> new IllegalArgumentException("Diese Veranstaltungsart gibt es nicht: " + wanted
                        + ". Siehe list_sports_and_event_types."));
    }

    static ClubEvent event(ClubStore club, String eventId) {
        return club.event(id(eventId, "event_id"))
                .orElseThrow(() -> new IllegalArgumentException("Diesen Eintrag gibt es nicht." + ID_HINT));
    }

    /** Lowercase id; ids reach PostgREST filters, so anything but a UUID stops here. */
    static String id(String raw, String name) {
        return MemberStore.key(raw == null ? null : raw.trim())
                .orElseThrow(() -> new IllegalArgumentException(name + " ist keine gültige Id." + ID_HINT));
    }

    static String required(String value, String name) {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException(name + " darf nicht leer sein.");
        }
        return value.trim();
    }

    static String or(String value, String fallback) {
        return value != null ? value : fallback;
    }

    static int positive(int value, String name) {
        if (value < 1) {
            throw new IllegalArgumentException(name + " muss mindestens 1 sein.");
        }
        return value;
    }

    static LocalDate day(String raw, String name) {
        try {
            return LocalDate.parse(required(raw, name));
        } catch (DateTimeParseException e) {
            throw new IllegalArgumentException(name + ": bitte als yyyy-MM-dd angeben.");
        }
    }

    /** Local Austrian time, or with an explicit offset. */
    static Instant dateTime(String raw, String name) {
        String value = required(raw, name);
        try {
            return LocalDateTime.parse(value).atZone(CLUB_ZONE).toInstant();
        } catch (DateTimeParseException local) {
            try {
                return OffsetDateTime.parse(value).toInstant();
            } catch (DateTimeParseException offset) {
                throw new IllegalArgumentException(name + ": bitte als yyyy-MM-ddTHH:mm angeben.");
            }
        }
    }

    static Instant dayStart(LocalDate day) {
        return day.atTime(9, 0).atZone(CLUB_ZONE).toInstant();
    }

    static Instant dayEnd(LocalDate day) {
        return day.atTime(18, 0).atZone(CLUB_ZONE).toInstant();
    }

    static Instant keepTime(LocalDate day, Instant previous, LocalTime defaultTime) {
        return LocalDate.ofInstant(previous, CLUB_ZONE).equals(day) ? previous
                : day.atTime(defaultTime).atZone(CLUB_ZONE).toInstant();
    }

    static TournamentDocuments documents(McpUser user) {
        return new TournamentDocuments(user.db(), user.id());
    }

    static ClubEvent tournament(ClubStore club, String tournamentId) {
        ClubEvent event = event(club, tournamentId);
        if (!"tournament".equals(event.kind())) {
            throw new IllegalArgumentException("„" + event.title() + "“ ist kein Turnier; Dokumente gibt es nur bei Turnieren.");
        }
        return event;
    }

    static TournamentDocuments.Document document(TournamentDocuments store, String documentId) {
        return store.get(id(documentId, "document_id")).orElseThrow(() -> new IllegalArgumentException(
                "Dieses Dokument gibt es nicht. Ids liefert list_tournament_documents."));
    }

    static Map<String, Object> documentRow(TournamentDocuments.Document d) {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("id", d.id());
        row.put("tournament_id", d.tournamentId());
        row.put("file_name", d.fileName());
        row.put("content_type", d.contentType());
        row.put("uploaded_at", d.uploadedAt() == null ? null : Dates.formatApi(d.uploadedAt()));
        return row;
    }
}
