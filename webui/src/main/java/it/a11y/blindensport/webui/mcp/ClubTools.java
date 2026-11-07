package it.a11y.blindensport.webui.mcp;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.quarkiverse.mcp.server.Tool;
import io.quarkiverse.mcp.server.ToolArg;
import io.quarkiverse.mcp.server.ToolCallException;
import io.quarkus.vertx.http.runtime.CurrentVertxRequest;
import it.a11y.blindensport.webui.auth.Permission;
import it.a11y.blindensport.webui.club.ClubModels;
import it.a11y.blindensport.webui.club.ClubModels.Attendance;
import it.a11y.blindensport.webui.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webui.club.ClubModels.Membership;
import it.a11y.blindensport.webui.club.ClubModels.Team;
import it.a11y.blindensport.webui.club.ClubStore;
import it.a11y.blindensport.webui.members.Dates;
import it.a11y.blindensport.webui.members.MemberPrivate;
import it.a11y.blindensport.webui.members.MemberRecord;
import it.a11y.blindensport.webui.members.MemberStatus;
import it.a11y.blindensport.webui.members.MemberStore;
import it.a11y.blindensport.webui.prae.PraeCalculator;
import it.a11y.blindensport.webui.prae.PraeForm;
import it.a11y.blindensport.webui.prae.PraeService;
import it.a11y.blindensport.webui.supabase.DbErrorMessages;
import it.a11y.blindensport.webui.supabase.SupabaseException;
import jakarta.inject.Inject;
import org.jboss.logging.Logger;

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
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static it.a11y.blindensport.webui.members.Dates.CLUB_ZONE;

/**
 * What an MCP client can do. Three rules hold for every tool:
 * <ul>
 *   <li>It runs as the signed-in person, so RLS and their role decide.</li>
 *   <li>Protected fields (SVNR, IBAN, birth date, medical exam, disability,
 *       consents) never appear in a result and can't be written, since
 *       anything returned reaches the AI behind the client. Member results
 *       are built from an explicit list of fields for that reason.</li>
 *   <li>Nothing here deletes. A member is only flagged with status "delete";
 *       root removes them in the app or web UI.</li>
 * </ul>
 */
public class ClubTools {
    private static final Logger LOG = Logger.getLogger(ClubTools.class);
    private static final int DEFAULT_EVENT_LIMIT = 50;
    private static final int MAX_EVENT_LIMIT = 200;

    private static final String ID_HINT = " Get ids from list_members, list_teams or list_events.";

    @Inject
    CurrentVertxRequest request;

    @Inject
    ObjectMapper json;

    @Inject
    McpFiles files;

    @Inject
    McpConfig config;

    public record AttendanceChange(
            @ToolArg(description = "membership_id from get_event's roster") String membershipId,
            @ToolArg(description = "Whether the person attended") boolean attended,
            @ToolArg(description = "PRAE in euros, coaches and assistants only; omit to keep the current amount", required = false)
            Double praeAmount) {
    }

    // ---------------------------------------------------------------- who

    @Tool(description = "Who is signed in: name, role and what the account may do.",
            annotations = @Tool.Annotations(title = "Who am I", readOnlyHint = true, destructiveHint = false, idempotentHint = true))
    String whoami() {
        return run("whoami", user -> {
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("email", user.email());
            result.put("role", user.access().role());
            result.put("permissions", user.access().permissions().stream().sorted().toList());
            return result;
        });
    }

    // ------------------------------------------------------------ members

    @Tool(description = "List club members, sorted by last name. Protected data is never returned.",
            annotations = @Tool.Annotations(title = "List members", readOnlyHint = true, destructiveHint = false, idempotentHint = true))
    String list_members(
            @ToolArg(description = "Part of a name, email or member number", required = false) String query,
            @ToolArg(description = "Only this status: new, active or delete", required = false) String status) {
        return run("list_members", user -> {
            String q = query == null ? "" : query.trim().toLowerCase(Locale.ROOT);
            return user.roster().all(false).stream()
                    .filter(m -> status == null || status.equals(m.status()))
                    .filter(m -> q.isEmpty() || (m.fullName() + " " + m.email() + " " + m.memberNumber())
                            .toLowerCase(Locale.ROOT).contains(q))
                    .map(ClubTools::memberSummary).toList();
        });
    }

    @Tool(description = "One member's contact details and teams. Protected data (SVNR, IBAN, birth date, health) is never returned.",
            annotations = @Tool.Annotations(title = "Get member", readOnlyHint = true, destructiveHint = false, idempotentHint = true))
    String get_member(@ToolArg(description = "Member id") String member_id) {
        return run("get_member", user -> {
            MemberRecord member = member(user, member_id);
            String key = member.id().toLowerCase(Locale.ROOT);
            ClubStore club = user.club();
            Map<String, String> teams = teamNames(club);
            List<Map<String, Object>> memberships = new ArrayList<>();
            for (Membership m : club.memberships()) {
                if (key.equals(m.memberId())) {
                    Map<String, Object> row = new LinkedHashMap<>();
                    row.put("membership_id", m.id());
                    row.put("team_id", m.teamId());
                    row.put("team", teams.getOrDefault(m.teamId(), "?"));
                    row.put("role", m.role());
                    memberships.add(row);
                }
            }
            Map<String, Object> result = memberDetails(member);
            result.put("teams", memberships);
            return result;
        });
    }

    @Tool(description = "Create a club member with status 'new'. Check list_members first so nobody is added twice. "
            + "Protected data (SVNR, IBAN, birth date) can't be set here; it is entered in the app or web UI.",
            annotations = @Tool.Annotations(title = "Create member", readOnlyHint = false, destructiveHint = false, idempotentHint = false))
    String create_member(
            @ToolArg(description = "First name") String first_name,
            @ToolArg(description = "Last name") String last_name,
            @ToolArg(description = "Street and number", required = false) String street,
            @ToolArg(description = "Postal code", required = false) String zip,
            @ToolArg(description = "City", required = false) String city,
            @ToolArg(description = "Country", required = false) String country,
            @ToolArg(description = "Email", required = false) String email,
            @ToolArg(description = "Phone", required = false) String phone,
            @ToolArg(description = "Member number", required = false) String member_number,
            @ToolArg(description = "Gender: f, m or empty", required = false) String gender,
            @ToolArg(description = "Academic title", required = false) String title,
            @ToolArg(description = "Sport Austria id, e.g. St-0046", required = false) String sport_id,
            @ToolArg(description = "Default team role: player, coach or assistant", required = false) String default_function,
            @ToolArg(description = "Whether a Grazer VSC club member; default true", required = false) Boolean member_of_gvsc,
            @ToolArg(description = "Free-text notes. Don't put health or other protected data here", required = false) String notes) {
        return run("create_member", user -> {
            requirePermission(user, Permission.MEMBERS_MANAGE);
            String first = required(first_name, "first_name");
            String last = required(last_name, "last_name");
            MemberRecord record = new MemberRecord(UUID.randomUUID().toString().toUpperCase(Locale.ROOT), first, last,
                    or(street, ""), or(zip, ""), or(city, ""), or(country, ""), or(email, ""), or(phone, ""),
                    or(member_number, ""), Instant.now(), or(notes, ""), or(gender, ""), or(title, ""), or(sport_id, ""),
                    or(default_function, ""), member_of_gvsc == null || member_of_gvsc, MemberPrivate.EMPTY, MemberStatus.NEW);
            user.roster().save(record, false, user.id());
            return memberDetails(record);
        });
    }

    @Tool(description = "Change a member; only the fields you pass change. Status: new, active, or delete. "
            + "Status 'delete' only marks the member for deletion: a root user removes them in the app or web UI. "
            + "Protected data can't be changed here.",
            annotations = @Tool.Annotations(title = "Update member", readOnlyHint = false, destructiveHint = false, idempotentHint = true))
    String update_member(
            @ToolArg(description = "Member id") String member_id,
            @ToolArg(description = "First name", required = false) String first_name,
            @ToolArg(description = "Last name", required = false) String last_name,
            @ToolArg(description = "Street and number", required = false) String street,
            @ToolArg(description = "Postal code", required = false) String zip,
            @ToolArg(description = "City", required = false) String city,
            @ToolArg(description = "Country", required = false) String country,
            @ToolArg(description = "Email", required = false) String email,
            @ToolArg(description = "Phone", required = false) String phone,
            @ToolArg(description = "Member number", required = false) String member_number,
            @ToolArg(description = "Gender: f, m or empty", required = false) String gender,
            @ToolArg(description = "Academic title", required = false) String title,
            @ToolArg(description = "Sport Austria id", required = false) String sport_id,
            @ToolArg(description = "Default team role: player, coach or assistant", required = false) String default_function,
            @ToolArg(description = "Whether a Grazer VSC club member", required = false) Boolean member_of_gvsc,
            @ToolArg(description = "Free-text notes. Don't put health or other protected data here", required = false) String notes,
            @ToolArg(description = "new, active or delete", required = false) String status) {
        return run("update_member", user -> {
            requirePermission(user, Permission.MEMBERS_MANAGE);
            if (status != null && !MemberStatus.isValid(status)) {
                throw new IllegalArgumentException("status must be new, active or delete.");
            }
            MemberRecord m = member(user, member_id);
            MemberRecord updated = new MemberRecord(m.id(),
                    first_name == null ? m.firstName() : required(first_name, "first_name"),
                    last_name == null ? m.lastName() : required(last_name, "last_name"),
                    or(street, m.street()), or(zip, m.zip()), or(city, m.city()), or(country, m.country()),
                    or(email, m.email()), or(phone, m.phone()), or(member_number, m.memberNumber()), m.joinedAt(),
                    or(notes, m.notes()), or(gender, m.gender()), or(title, m.title()), or(sport_id, m.sportId()),
                    or(default_function, m.defaultFunction()),
                    member_of_gvsc != null ? member_of_gvsc : m.memberOfGVSC(), MemberPrivate.EMPTY, or(status, m.status()));
            user.roster().save(updated, false, user.id());
            return memberDetails(updated);
        });
    }

    // -------------------------------------------------------------- teams

    @Tool(description = "List teams with their people and roles.",
            annotations = @Tool.Annotations(title = "List teams", readOnlyHint = true, destructiveHint = false, idempotentHint = true))
    String list_teams() {
        return run("list_teams", user -> {
            ClubStore club = user.club();
            Names names = names(user, club);
            List<Membership> memberships = club.memberships();
            return club.teams().stream().map(t -> {
                Map<String, Object> row = new LinkedHashMap<>();
                row.put("team_id", t.id());
                row.put("name", t.name());
                row.put("sport", t.sport());
                row.put("members", memberships.stream().filter(m -> m.teamId().equals(t.id()))
                        .map(m -> membershipRow(m, names)).toList());
                return row;
            }).toList();
        });
    }

    @Tool(description = "Create a team.",
            annotations = @Tool.Annotations(title = "Create team", readOnlyHint = false, destructiveHint = false, idempotentHint = false))
    String create_team(
            @ToolArg(description = "Unique team name") String name,
            @ToolArg(description = "Sport, e.g. Torball", required = false) String sport,
            @ToolArg(description = "Description", required = false) String description) {
        return run("create_team", user -> {
            requirePermission(user, Permission.TEAMS_MANAGE);
            Team team = new Team(ClubStore.newId(), required(name, "name"), or(sport, ""), or(description, ""));
            user.club().saveTeam(team);
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("team_id", team.id());
            row.put("name", team.name());
            return row;
        });
    }

    @Tool(description = "Put a member on a team, which puts them on the attendance list of the team's events. "
            + "Does nothing if they are already on it.",
            annotations = @Tool.Annotations(title = "Add team member", readOnlyHint = false, destructiveHint = false, idempotentHint = true))
    String add_team_member(
            @ToolArg(description = "Team id") String team_id,
            @ToolArg(description = "Member id") String member_id,
            @ToolArg(description = "player, coach or assistant; coaches and assistants can get PRAE. Default: player", required = false) String role) {
        return run("add_team_member", user -> {
            requirePermission(user, Permission.TEAMS_MANAGE);
            String roleValue = or(role, "player");
            if (!ClubModels.MEMBERSHIP_ROLES.containsKey(roleValue)) {
                throw new IllegalArgumentException("role must be player, coach or assistant.");
            }
            ClubStore club = user.club();
            String teamId = id(team_id, "team_id");
            String memberKey = member(user, member_id).id().toLowerCase(Locale.ROOT);
            if (club.teams().stream().noneMatch(t -> t.id().equals(teamId))) {
                throw new IllegalArgumentException("Dieses Team gibt es nicht." + ID_HINT);
            }
            Optional<Membership> existing = club.memberships().stream()
                    .filter(m -> m.teamId().equals(teamId) && memberKey.equals(m.memberId())).findFirst();
            Membership membership = existing.orElseGet(() -> {
                Membership created = new Membership(ClubStore.newId(), teamId, memberKey, null, roleValue, Instant.now());
                club.saveMembership(created);
                return created;
            });
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("membership_id", membership.id());
            row.put("role", membership.role());
            row.put("already_on_team", existing.isPresent());
            return row;
        });
    }

    // ------------------------------------------------------------- events

    @Tool(description = "List trainings, tournaments and events, newest first.",
            annotations = @Tool.Annotations(title = "List events", readOnlyHint = true, destructiveHint = false, idempotentHint = true))
    String list_events(
            @ToolArg(description = "training, tournament or event; default all", required = false) String kind,
            @ToolArg(description = "From this day, yyyy-MM-dd", required = false) String from,
            @ToolArg(description = "Up to and including this day, yyyy-MM-dd", required = false) String to,
            @ToolArg(description = "Part of the title or location", required = false) String query,
            @ToolArg(description = "Most results, default 50, at most 200", required = false) Integer limit) {
        return run("list_events", user -> {
            LocalDate fromDay = from == null ? null : day(from, "from");
            LocalDate toDay = to == null ? null : day(to, "to");
            String q = query == null ? "" : query.trim().toLowerCase(Locale.ROOT);
            int max = limit == null ? DEFAULT_EVENT_LIMIT : Math.max(1, Math.min(limit, MAX_EVENT_LIMIT));
            return user.club().events().stream()
                    .filter(e -> kind == null || kind.equals(e.kind()))
                    .filter(e -> fromDay == null || !LocalDate.ofInstant(e.endDate(), CLUB_ZONE).isBefore(fromDay))
                    .filter(e -> toDay == null || !LocalDate.ofInstant(e.startDate(), CLUB_ZONE).isAfter(toDay))
                    .filter(e -> q.isEmpty() || (e.title() + " " + e.location()).toLowerCase(Locale.ROOT).contains(q))
                    .limit(max).map(ClubTools::eventRow).toList();
        });
    }

    @Tool(description = "One event with its teams and roster: everyone on those teams with attendance and PRAE amount. "
            + "Use each roster entry's membership_id with set_attendance.",
            annotations = @Tool.Annotations(title = "Get event", readOnlyHint = true, destructiveHint = false, idempotentHint = true))
    String get_event(@ToolArg(description = "Event id") String event_id) {
        return run("get_event", user -> {
            ClubStore club = user.club();
            ClubEvent event = event(club, event_id);
            Names names = names(user, club);
            Map<String, Attendance> attendance = new HashMap<>();
            club.attendances(event.id()).forEach(a -> attendance.put(a.membershipId(), a));
            Map<String, String> teams = teamNames(club);
            List<Map<String, Object>> rows = new ArrayList<>();
            for (Membership m : roster(event, club.memberships(), names)) {
                Map<String, Object> row = membershipRow(m, names);
                Attendance a = attendance.get(m.id());
                row.put("attended", a != null && a.attended());
                row.put("prae_amount", a == null ? null : a.praeAmount());
                rows.add(row);
            }
            Map<String, Object> result = eventRow(event);
            result.put("notes", event.notes());
            result.put("street", event.street());
            result.put("zip", event.zip());
            result.put("country", event.country());
            result.put("teams", event.teamIds().stream().map(id -> teams.getOrDefault(id, "?")).toList());
            result.put("max_prae", event.maxPrae());
            result.put("roster", rows);
            return result;
        });
    }

    @Tool(description = "Create a training, tournament or event. Times are Austrian local time. "
            + "Training: start is date and time, plus duration_minutes (default 90). "
            + "Tournament: start and end are days, yyyy-MM-dd; when an invitation names an arrival day, start is the arrival day and end the last playing day. "
            + "Event: start and end are date and time. "
            + "Date and time as yyyy-MM-ddTHH:mm.",
            annotations = @Tool.Annotations(title = "Create event", readOnlyHint = false, destructiveHint = false, idempotentHint = false))
    String create_event(
            @ToolArg(description = "training, tournament or event") String kind,
            @ToolArg(description = "Title. Trainings with the same title share one PRAE form per month") String title,
            @ToolArg(description = "Start") String start,
            @ToolArg(description = "End; for a tournament the last day (default: same day); for an event required", required = false) String end,
            @ToolArg(description = "Sport, e.g. Torball", required = false) String sport,
            @ToolArg(description = "Name of the place", required = false) String location,
            @ToolArg(description = "Street", required = false) String street,
            @ToolArg(description = "Postal code", required = false) String zip,
            @ToolArg(description = "City", required = false) String city,
            @ToolArg(description = "Country, default Österreich", required = false) String country,
            @ToolArg(description = "Notes", required = false) String notes,
            @ToolArg(description = "Training length, default 90", required = false) Integer duration_minutes,
            @ToolArg(description = "Training focus", required = false) String focus_area,
            @ToolArg(description = "Tournament size, default 8", required = false) Integer max_teams,
            @ToolArg(description = "Team ids; their people form the attendance list", required = false) List<String> team_ids) {
        return run("create_event", user -> {
            requirePermission(user, Permission.EVENTS_MANAGE);
            if (!ClubModels.KINDS.containsKey(kind)) {
                throw new IllegalArgumentException("kind must be training, tournament or event.");
            }
            ClubStore club = user.club();
            Instant startAt;
            Instant endAt;
            Integer duration = null;
            switch (kind) {
                case "training" -> {
                    duration = duration_minutes == null ? 90 : positive(duration_minutes, "duration_minutes");
                    startAt = dateTime(start, "start");
                    endAt = startAt.plusSeconds(duration * 60L);
                }
                case "tournament" -> {
                    LocalDate first = day(start, "start");
                    LocalDate last = end == null ? first : day(end, "end");
                    startAt = dayStart(first);
                    endAt = dayEnd(last);
                }
                default -> {
                    startAt = dateTime(start, "start");
                    endAt = dateTime(required(end, "end"), "end");
                }
            }
            if (endAt.isBefore(startAt)) {
                throw new IllegalArgumentException("Das Ende liegt vor dem Beginn.");
            }
            String status = switch (kind) {
                case "training" -> "open";
                case "tournament" -> "planned";
                default -> "";
            };
            ClubEvent event = new ClubEvent(ClubStore.newId(), kind, required(title, "title"), or(sport, ""), or(location, ""),
                    or(street, ""), or(zip, ""), or(city, ""), or(country, "Österreich"), startAt, endAt, or(notes, ""), status,
                    duration, "training".equals(kind) ? or(focus_area, "") : null,
                    "tournament".equals(kind) ? (max_teams == null ? 8 : positive(max_teams, "max_teams")) : null,
                    teamIds(club, team_ids), club.createdBy());
            club.saveEvent(event);
            return eventRow(event);
        });
    }

    @Tool(description = "Change an event; only the fields you pass change. A training's status is open, held or cancelled "
            + "(cancel a training this way). A tournament's status is planned, ongoing or finished. "
            + "team_ids replaces the whole list. Date formats as in create_event.",
            annotations = @Tool.Annotations(title = "Update event", readOnlyHint = false, destructiveHint = false, idempotentHint = true))
    String update_event(
            @ToolArg(description = "Event id") String event_id,
            @ToolArg(description = "Title", required = false) String title,
            @ToolArg(description = "Start", required = false) String start,
            @ToolArg(description = "End; not for trainings, use duration_minutes", required = false) String end,
            @ToolArg(description = "Status", required = false) String status,
            @ToolArg(description = "Sport", required = false) String sport,
            @ToolArg(description = "Name of the place", required = false) String location,
            @ToolArg(description = "Street", required = false) String street,
            @ToolArg(description = "Postal code", required = false) String zip,
            @ToolArg(description = "City", required = false) String city,
            @ToolArg(description = "Country", required = false) String country,
            @ToolArg(description = "Notes", required = false) String notes,
            @ToolArg(description = "Training length", required = false) Integer duration_minutes,
            @ToolArg(description = "Training focus", required = false) String focus_area,
            @ToolArg(description = "Tournament size", required = false) Integer max_teams,
            @ToolArg(description = "Team ids; replaces the list", required = false) List<String> team_ids) {
        return run("update_event", user -> {
            requirePermission(user, Permission.EVENTS_MANAGE);
            ClubStore club = user.club();
            ClubEvent e = event(club, event_id);
            Map<String, String> statuses = "tournament".equals(e.kind()) ? ClubModels.TOURNAMENT_STATUS
                    : "training".equals(e.kind()) ? ClubModels.TRAINING_STATUS : Map.of();
            if (status != null && !statuses.containsKey(status)) {
                throw new IllegalArgumentException("Für diese Art gültiger Status: " + statuses.keySet());
            }
            Instant startAt = e.startDate();
            Instant endAt = e.endDate();
            Integer duration = e.durationMinutes();
            switch (e.kind()) {
                case "training" -> {
                    if (end != null) {
                        throw new IllegalArgumentException("Bei Trainings die Dauer mit duration_minutes ändern.");
                    }
                    startAt = start == null ? startAt : dateTime(start, "start");
                    duration = duration_minutes != null ? positive(duration_minutes, "duration_minutes") : duration;
                    endAt = duration == null ? endAt : startAt.plusSeconds(duration * 60L);
                }
                case "tournament" -> {
                    startAt = start == null ? startAt : keepTime(day(start, "start"), e.startDate(), LocalTime.of(9, 0));
                    endAt = end == null ? endAt : keepTime(day(end, "end"), e.endDate(), LocalTime.of(18, 0));
                }
                default -> {
                    startAt = start == null ? startAt : dateTime(start, "start");
                    endAt = end == null ? endAt : dateTime(end, "end");
                }
            }
            if (endAt.isBefore(startAt)) {
                throw new IllegalArgumentException("Das Ende liegt vor dem Beginn.");
            }
            ClubEvent updated = new ClubEvent(e.id(), e.kind(), title == null ? e.title() : required(title, "title"),
                    or(sport, e.sport()), or(location, e.location()), or(street, e.street()), or(zip, e.zip()),
                    or(city, e.city()), or(country, e.country()), startAt, endAt, or(notes, e.notes()),
                    or(status, e.status()), duration, focus_area != null ? focus_area : e.focusArea(),
                    max_teams != null ? Integer.valueOf(positive(max_teams, "max_teams")) : e.maxTeams(),
                    team_ids != null ? teamIds(club, team_ids) : e.teamIds(), e.createdBy());
            club.saveEvent(updated);
            return eventRow(updated);
        });
    }

    @Tool(description = "Record attendance and PRAE amounts for one event, for one or several people. "
            + "PRAE is only for coaches and assistants who attended: 0 up to max_prae from get_event, in steps of 5 euros. "
            + "A tournament's amount is entered once and spread over its days. "
            + "Marking someone absent clears their PRAE.",
            annotations = @Tool.Annotations(title = "Set attendance", readOnlyHint = false, destructiveHint = false, idempotentHint = true))
    String set_attendance(
            @ToolArg(description = "Event id") String event_id,
            @ToolArg(description = "The changes") List<AttendanceChange> changes) {
        return run("set_attendance", user -> {
            requirePermission(user, Permission.EVENTS_MANAGE);
            ClubStore club = user.club();
            ClubEvent event = event(club, event_id);
            Names names = names(user, club);
            Map<String, Membership> roster = new HashMap<>();
            roster(event, club.memberships(), names).forEach(m -> roster.put(m.id(), m));
            Map<String, Attendance> stored = new HashMap<>();
            club.attendances(event.id()).forEach(a -> stored.put(a.membershipId(), a));
            // Everything is checked before the first write, so a bad entry changes nothing.
            List<Attendance> rows = new ArrayList<>();
            for (AttendanceChange change : changes) {
                String membershipId = id(change.membershipId(), "membership_id");
                Membership m = roster.get(membershipId);
                if (m == null) {
                    throw new IllegalArgumentException(membershipId + " steht nicht auf der Anwesenheitsliste dieses Eintrags.");
                }
                Attendance old = stored.get(membershipId);
                rows.add(new Attendance(old == null ? ClubStore.newId() : old.id(), event.id(), membershipId,
                        change.attended(), prae(change, m, old, event, names)));
            }
            rows.forEach(club::saveAttendance);
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("saved", rows.size());
            return result;
        });
    }

    // --------------------------------------------------------------- PRAE

    @Tool(description = "Show which PRAE forms there would be, with amounts per day and legal-cap warnings, without creating files. "
            + "Pass event_id for a tournament or a training (a training's form covers all sessions of that title in the month), "
            + "or month and year for all trainings of a month.",
            annotations = @Tool.Annotations(title = "Preview PRAE", readOnlyHint = true, destructiveHint = false, idempotentHint = true))
    String preview_prae(
            @ToolArg(description = "Tournament or training id", required = false) String event_id,
            @ToolArg(description = "Month, 1 to 12", required = false) Integer month,
            @ToolArg(description = "Year", required = false) Integer year,
            @ToolArg(description = "Only this person's member id", required = false) String member_id) {
        return run("preview_prae", user -> {
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("forms", forms(user, event_id, month, year, member_id, false).stream().map(ClubTools::formRow).toList());
            return result;
        });
    }

    @Tool(description = "Create the official PRAE forms and Darstellung as a zip of Excel files, for the same choices as preview_prae. "
            + "The result has summaries and a one-time download_url, valid for 10 minutes. "
            + "The files contain social security numbers and IBANs: save them with `curl -o <file> <download_url>` "
            + "and leave them closed. Don't read their contents, and give the path to the user.",
            annotations = @Tool.Annotations(title = "Create PRAE forms", readOnlyHint = false, destructiveHint = false, idempotentHint = false))
    String create_prae_forms(
            @ToolArg(description = "Tournament or training id", required = false) String event_id,
            @ToolArg(description = "Month, 1 to 12", required = false) Integer month,
            @ToolArg(description = "Year", required = false) Integer year,
            @ToolArg(description = "Only this person's member id", required = false) String member_id) {
        return run("create_prae_forms", user -> {
            requirePermission(user, Permission.MEMBERS_PRIVATE_READ);
            List<PraeForm> forms = forms(user, event_id, month, year, member_id, true);
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("forms", forms.stream().map(ClubTools::formRow).toList());
            if (forms.isEmpty()) {
                result.put("message", "Keine Einsätze mit PRAE-Betrag gefunden.");
                return result;
            }
            String token = files.put("PRAE.zip", "application/zip", PraeService.zip(forms));
            result.put("download_url", config.publicUrl() + "/mcp-files/" + token);
            result.put("expires_in_minutes", McpFiles.LIFETIME.toMinutes());
            return result;
        });
    }

    // ------------------------------------------------------------ helpers

    private interface Action {
        Object run(McpUser user);
    }

    /** The one way into a tool: the user, German errors, and a log line that holds no data. */
    private String run(String tool, Action action) {
        McpUser user = request.getCurrent() == null ? null : request.getCurrent().get(McpAuthFilter.USER);
        if (user == null) {
            throw new ToolCallException("Nicht angemeldet.");
        }
        LOG.infof("MCP %s by %s", tool, user.id());
        try {
            return json.writeValueAsString(action.run(user));
        } catch (SupabaseException e) {
            LOG.infof("MCP %s refused by the database: %s", tool, e.getMessage());
            throw new ToolCallException(DbErrorMessages.german(e));
        } catch (IllegalArgumentException e) {
            throw new ToolCallException(e.getMessage());
        } catch (JsonProcessingException e) {
            throw new IllegalStateException(e);
        }
    }

    private static void requirePermission(McpUser user, String permission) {
        if (!user.can(permission)) {
            throw new IllegalArgumentException("Dieses Konto hat keine Berechtigung dafür (" + permission + ").");
        }
    }

    private static List<PraeForm> forms(McpUser user, String eventId, Integer month, Integer year, String memberId,
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

    private static Map<String, Object> formRow(PraeForm form) {
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
    private record Names(Map<String, String> members, Map<String, PraeCalculator.AccountName> accounts) {
        String of(Membership m) {
            if (m.userId() != null && accounts.containsKey(m.userId())) {
                return (accounts.get(m.userId()).firstName() + " " + accounts.get(m.userId()).lastName()).trim();
            }
            return m.memberId() == null ? "?" : members.getOrDefault(m.memberId(), "?");
        }
    }

    private static Names names(McpUser user, ClubStore club) {
        Map<String, String> members = new HashMap<>();
        user.roster().all(false).forEach(m -> members.put(m.id().toLowerCase(Locale.ROOT), m.fullName()));
        return new Names(members, club.accounts());
    }

    private static Map<String, Object> membershipRow(Membership m, Names names) {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("membership_id", m.id());
        row.put("member_id", m.memberId());
        row.put("name", names.of(m));
        row.put("role", m.role());
        return row;
    }

    /** Memberships of the event's teams, each person once, by name (SportEvent.rosterAcrossTeams). */
    private static List<Membership> roster(ClubEvent event, List<Membership> all, Names names) {
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

    private static Map<String, String> teamNames(ClubStore club) {
        Map<String, String> names = new HashMap<>();
        club.teams().forEach(t -> names.put(t.id(), t.name()));
        return names;
    }

    private static List<String> teamIds(ClubStore club, List<String> ids) {
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

    private static BigDecimal prae(AttendanceChange change, Membership m, Attendance old, ClubEvent event, Names names) {
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

    private static Map<String, Object> memberSummary(MemberRecord m) {
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
    private static Map<String, Object> memberDetails(MemberRecord m) {
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

    private static Map<String, Object> eventRow(ClubEvent e) {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("event_id", e.id());
        row.put("kind", e.kind());
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

    private static MemberRecord member(McpUser user, String memberId) {
        MemberStore roster = user.roster();
        return roster.get(id(memberId, "member_id"), false)
                .orElseThrow(() -> new IllegalArgumentException("Dieses Mitglied gibt es nicht." + ID_HINT));
    }

    private static ClubEvent event(ClubStore club, String eventId) {
        return club.event(id(eventId, "event_id"))
                .orElseThrow(() -> new IllegalArgumentException("Diesen Eintrag gibt es nicht." + ID_HINT));
    }

    /** Lowercase id; ids reach PostgREST filters, so anything but a UUID stops here. */
    private static String id(String raw, String name) {
        return MemberStore.key(raw == null ? null : raw.trim())
                .orElseThrow(() -> new IllegalArgumentException(name + " ist keine gültige Id." + ID_HINT));
    }

    private static String required(String value, String name) {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException(name + " darf nicht leer sein.");
        }
        return value.trim();
    }

    private static String or(String value, String fallback) {
        return value != null ? value : fallback;
    }

    private static int positive(int value, String name) {
        if (value < 1) {
            throw new IllegalArgumentException(name + " muss mindestens 1 sein.");
        }
        return value;
    }

    private static LocalDate day(String raw, String name) {
        try {
            return LocalDate.parse(required(raw, name));
        } catch (DateTimeParseException e) {
            throw new IllegalArgumentException(name + ": bitte als yyyy-MM-dd angeben.");
        }
    }

    /** Local Austrian time, or with an explicit offset. */
    private static Instant dateTime(String raw, String name) {
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

    private static Instant dayStart(LocalDate day) {
        return day.atTime(9, 0).atZone(CLUB_ZONE).toInstant();
    }

    private static Instant dayEnd(LocalDate day) {
        return day.atTime(18, 0).atZone(CLUB_ZONE).toInstant();
    }

    private static Instant keepTime(LocalDate day, Instant previous, LocalTime defaultTime) {
        return LocalDate.ofInstant(previous, CLUB_ZONE).equals(day) ? previous
                : day.atTime(defaultTime).atZone(CLUB_ZONE).toInstant();
    }
}
