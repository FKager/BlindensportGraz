package it.a11y.blindensport.webadmin.club;

import com.fasterxml.jackson.databind.JsonNode;
import it.a11y.blindensport.webadmin.club.ClubModels.Attendance;
import it.a11y.blindensport.webadmin.club.ClubModels.BudgetEntry;
import it.a11y.blindensport.webadmin.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webadmin.club.ClubModels.Membership;
import it.a11y.blindensport.webadmin.club.ClubModels.Team;
import it.a11y.blindensport.webadmin.club.ClubModels.TrainingFavorite;
import it.a11y.blindensport.webadmin.club.ClubModels.WelcomeContent;
import it.a11y.blindensport.webadmin.members.Dates;
import it.a11y.blindensport.webadmin.supabase.Postgrest;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.StreamSupport;

import static it.a11y.blindensport.webadmin.supabase.Postgrest.eq;
import static it.a11y.blindensport.webadmin.supabase.Postgrest.order;

/**
 * Teams, memberships, events (trainings / tournaments / events),
 * attendance, training favourites, budget and the welcome text — read and
 * written as the signed-in admin. RLS: approved accounts read; teams.manage,
 * events.manage, budget.manage, club.manage write. Ids are lowercase UUIDs;
 * every write sets {@code updated_by} so the app's sync sees who changed it.
 * Deletes are logged by a trigger (public.deletions), so the app removes
 * them from its offline cache too.
 */
public final class ClubStore {
    private final Postgrest db;
    private final UUID admin;

    public ClubStore(Postgrest db, UUID admin) {
        this.db = db;
        this.admin = admin;
    }

    public static String newId() {
        return UUID.randomUUID().toString();
    }

    // ---------------------------------------------------------------- teams

    public List<Team> teams() {
        return rows("teams", "id,name,sport,description_text", "name.asc", r -> new Team(
                id(r), text(r, "name"), text(r, "sport"), text(r, "description_text")));
    }

    public void saveTeam(Team team) {
        Map<String, Object> row = row(team.id());
        row.put("name", team.name().trim());
        row.put("sport", team.sport());
        row.put("description_text", team.description());
        db.upsert("teams", List.of(row), "id");
    }

    /** Memberships cascade; events keep a stale id in team_ids — the database trigger removes it. */
    public void deleteTeam(String id) {
        db.delete("teams", eq("id", id));
    }

    public List<Membership> memberships() {
        return rows("team_memberships", "id,team_id,member_id,user_id,role,joined_at", "joined_at.asc", r -> new Membership(
                id(r), lower(r, "team_id"), lowerOrNull(r, "member_id"), lowerOrNull(r, "user_id"),
                text(r, "role"), instant(r, "joined_at")));
    }

    public void saveMembership(Membership m) {
        Map<String, Object> row = row(m.id());
        row.put("team_id", m.teamId());
        row.put("member_id", m.memberId());
        row.put("user_id", m.userId());
        row.put("role", m.role());
        row.put("joined_at", Dates.formatTimestamp(m.joinedAt() == null ? Instant.now() : m.joinedAt()));
        db.upsert("team_memberships", List.of(row), "id");
    }

    public void deleteMembership(String id) {
        db.delete("team_memberships", eq("id", id));
    }

    /** Names of all accounts (account_directory RPC, readable by approved accounts). */
    public Map<String, String> accountNames() {
        Map<String, String> names = new HashMap<>();
        db.rpc("account_directory", Map.of()).forEach(r -> names.put(lower(r, "id"),
                (text(r, "first_name") + " " + text(r, "last_name")).trim()));
        return names;
    }

    // --------------------------------------------------------------- events

    public List<ClubEvent> events() {
        return rows("events", "*", "start_date.desc", ClubStore::event);
    }

    public Optional<ClubEvent> event(String id) {
        var rows = db.select("events", "*", eq("id", id));
        return rows.isEmpty() ? Optional.empty() : Optional.of(event(rows.get(0)));
    }

    public void saveEvent(ClubEvent e) {
        Map<String, Object> row = row(e.id());
        row.put("kind", e.kind());
        row.put("title", e.title().trim());
        row.put("sport", e.sport());
        row.put("location", e.location());
        row.put("street", e.street());
        row.put("zip", e.zip());
        row.put("city", e.city());
        row.put("country", e.country());
        row.put("start_date", Dates.formatTimestamp(e.startDate()));
        row.put("end_date", Dates.formatTimestamp(e.endDate()));
        row.put("notes", e.notes());
        row.put("status", e.status());
        row.put("duration_minutes", e.durationMinutes());
        row.put("focus_area", e.focusArea());
        row.put("max_teams", e.maxTeams());
        row.put("team_ids", e.teamIds());
        row.put("created_by", e.createdBy());
        db.upsert("events", List.of(row), "id");
    }

    /** Attendance, participations and images cascade. */
    public void deleteEvent(String id) {
        db.delete("events", eq("id", id));
    }

    private static ClubEvent event(JsonNode r) {
        List<String> teams = new ArrayList<>();
        r.path("team_ids").forEach(t -> teams.add(t.asText().toLowerCase(Locale.ROOT)));
        return new ClubEvent(id(r), text(r, "kind"), text(r, "title"), text(r, "sport"), text(r, "location"),
                text(r, "street"), text(r, "zip"), text(r, "city"), text(r, "country"), instant(r, "start_date"),
                instant(r, "end_date"), text(r, "notes"), text(r, "status"), integer(r, "duration_minutes"),
                r.hasNonNull("focus_area") ? r.get("focus_area").asText() : null, integer(r, "max_teams"),
                teams, text(r, "created_by"));
    }

    // ----------------------------------------------------------- attendance

    public List<Attendance> attendances(String eventId) {
        List<Attendance> result = new ArrayList<>();
        db.select("attendances", "id,event_id,membership_id,attended,prae_amount", eq("event_id", eventId))
                .forEach(r -> result.add(new Attendance(id(r), lower(r, "event_id"), lower(r, "membership_id"),
                        r.path("attended").asBoolean(false),
                        r.hasNonNull("prae_amount") ? r.get("prae_amount").decimalValue() : null)));
        return result;
    }

    /**
     * Creates the row on first use, like the app's AttendanceService. PRAE
     * only stays on an attended row; 0 is stored as null.
     */
    public void saveAttendance(Attendance a) {
        Map<String, Object> row = row(a.id());
        row.put("event_id", a.eventId());
        row.put("membership_id", a.membershipId());
        row.put("attended", a.attended());
        BigDecimal prae = a.attended() && a.praeAmount() != null && a.praeAmount().signum() > 0 ? a.praeAmount() : null;
        row.put("prae_amount", prae);
        row.put("recorded_at", Dates.formatTimestamp(Instant.now()));
        db.upsert("attendances", List.of(row), "id");
    }

    // ------------------------------------------------------------ favorites

    public List<TrainingFavorite> favorites() {
        return rows("training_favorites", "*", "title.asc", r -> {
            List<String> teams = new ArrayList<>();
            r.path("team_ids").forEach(t -> teams.add(t.asText().toLowerCase(Locale.ROOT)));
            return new TrainingFavorite(id(r), text(r, "title"), text(r, "sport"), r.path("weekday").asInt(2),
                    r.path("start_hour").asInt(), r.path("start_minute").asInt(), r.path("end_hour").asInt(),
                    r.path("end_minute").asInt(), text(r, "location"), text(r, "street"), text(r, "zip"),
                    text(r, "city"), text(r, "country"), teams);
        });
    }

    public void saveFavorite(TrainingFavorite f) {
        Map<String, Object> row = row(f.id());
        row.put("title", f.title().trim());
        row.put("sport", f.sport());
        row.put("weekday", f.weekday());
        row.put("start_hour", f.startHour());
        row.put("start_minute", f.startMinute());
        row.put("end_hour", f.endHour());
        row.put("end_minute", f.endMinute());
        row.put("location", f.location());
        row.put("street", f.street());
        row.put("zip", f.zip());
        row.put("city", f.city());
        row.put("country", f.country());
        row.put("team_ids", f.teamIds());
        db.upsert("training_favorites", List.of(row), "id");
    }

    public void deleteFavorite(String id) {
        db.delete("training_favorites", eq("id", id));
    }

    // --------------------------------------------------------------- budget

    public List<BudgetEntry> budget() {
        return rows("budget_entries", "id,category,amount,date,note,event_id,created_by", "date.desc", r -> new BudgetEntry(
                id(r), text(r, "category"), r.path("amount").decimalValue(), instant(r, "date"), text(r, "note"),
                lowerOrNull(r, "event_id"), text(r, "created_by")));
    }

    public void saveBudget(BudgetEntry b) {
        Map<String, Object> row = row(b.id());
        row.put("category", b.category());
        row.put("amount", b.amount().abs());
        row.put("date", Dates.formatTimestamp(b.date()));
        row.put("note", b.note());
        row.put("event_id", b.eventId());
        row.put("created_by", b.createdBy());
        db.upsert("budget_entries", List.of(row), "id");
    }

    public void deleteBudget(String id) {
        db.delete("budget_entries", eq("id", id));
    }

    // -------------------------------------------------------------- welcome

    /** The single welcome text row, if any. */
    public Optional<WelcomeContent> welcome() {
        var rows = db.select("welcome_content", "id,markdown,is_enabled", order("updated_at.desc"), Postgrest.limit(1));
        return rows.isEmpty() ? Optional.empty() : Optional.of(new WelcomeContent(id(rows.get(0)),
                text(rows.get(0), "markdown"), rows.get(0).path("is_enabled").asBoolean(false)));
    }

    public void saveWelcome(WelcomeContent w) {
        Map<String, Object> row = row(w.id());
        row.put("markdown", w.markdown());
        row.put("is_enabled", w.enabled());
        db.upsert("welcome_content", List.of(row), "id");
    }

    // -------------------------------------------------------------- helpers

    /** Admin id in the app's created_by convention (UUID.uuidString, uppercase). */
    public String createdBy() {
        return admin.toString().toUpperCase(Locale.ROOT);
    }

    private Map<String, Object> row(String id) {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("id", id.toLowerCase(Locale.ROOT));
        row.put("updated_by", admin.toString());
        return row;
    }

    private <T> List<T> rows(String table, String columns, String orderBy, Function<JsonNode, T> map) {
        return StreamSupport.stream(db.select(table, columns, order(orderBy)).spliterator(), false).map(map).toList();
    }

    private static String id(JsonNode r) {
        return lower(r, "id");
    }

    private static String lower(JsonNode r, String key) {
        return r.path(key).asText("").toLowerCase(Locale.ROOT);
    }

    private static String lowerOrNull(JsonNode r, String key) {
        return r.hasNonNull(key) ? r.get(key).asText().toLowerCase(Locale.ROOT) : null;
    }

    private static String text(JsonNode r, String key) {
        return r.hasNonNull(key) ? r.get(key).asText() : "";
    }

    private static Integer integer(JsonNode r, String key) {
        return r.hasNonNull(key) ? r.get(key).asInt() : null;
    }

    private static Instant instant(JsonNode r, String key) {
        return Dates.parseTimestamp(r.path(key).asText(null)).orElse(null);
    }
}
