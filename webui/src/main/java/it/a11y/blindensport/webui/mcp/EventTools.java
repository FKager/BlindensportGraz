package it.a11y.blindensport.webui.mcp;

import io.quarkiverse.mcp.server.Tool;
import io.quarkiverse.mcp.server.ToolArg;
import it.a11y.blindensport.webui.auth.Permission;
import it.a11y.blindensport.webui.club.ClubModels.Attendance;
import it.a11y.blindensport.webui.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webui.club.ClubModels.Membership;
import it.a11y.blindensport.webui.club.ClubModels.Team;
import it.a11y.blindensport.webui.club.ClubModels;
import it.a11y.blindensport.webui.club.ClubStore;
import jakarta.inject.Inject;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

import static it.a11y.blindensport.webui.mcp.McpToolSupport.*;
import static it.a11y.blindensport.webui.members.Dates.CLUB_ZONE;

/**
 * MCP tools for the sport and event-type lists, events and attendance. The rules of every MCP tool (see {@link McpToolSupport}): it
 * runs as the signed-in person, so RLS and their role decide; protected
 * member fields never appear in a result and can't be written.
 */
public class EventTools {
    @Inject
    McpToolRunner runner;
    private static final int DEFAULT_EVENT_LIMIT = 50;
    private static final int MAX_EVENT_LIMIT = 200;


    // ------------------------------------------- sports and event types

    @Tool(description = "The club's sport list and event-type list (Training, Turnier, Kurs …), in their order. "
            + "Use these names for sport and event_type. Each event type has a behaviour, the kind its events get: "
            + "training, tournament or event. Inactive entries are no longer offered but may still appear on old entries.",
            annotations = @Tool.Annotations(title = "List sports and event types", readOnlyHint = true,
                    destructiveHint = false, idempotentHint = true))
    String list_sports_and_event_types() {
        return runner.run("list_sports_and_event_types", user -> {
            ClubStore club = user.club();
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("sports", club.sports().stream().map(s -> {
                Map<String, Object> row = new LinkedHashMap<>();
                row.put("name", s.name());
                row.put("active", s.active());
                return row;
            }).toList());
            result.put("event_types", club.eventTypes().stream().map(t -> {
                Map<String, Object> row = new LinkedHashMap<>();
                row.put("name", t.name());
                row.put("behavior", t.behavior());
                row.put("active", t.active());
                return row;
            }).toList());
            return result;
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
        return runner.run("list_events", user -> {
            LocalDate fromDay = from == null ? null : day(from, "from");
            LocalDate toDay = to == null ? null : day(to, "to");
            String q = query == null ? "" : query.trim().toLowerCase(Locale.ROOT);
            int max = limit == null ? DEFAULT_EVENT_LIMIT : Math.max(1, Math.min(limit, MAX_EVENT_LIMIT));
            return user.club().events().stream()
                    .filter(e -> kind == null || kind.equals(e.kind()))
                    .filter(e -> fromDay == null || !LocalDate.ofInstant(e.endDate(), CLUB_ZONE).isBefore(fromDay))
                    .filter(e -> toDay == null || !LocalDate.ofInstant(e.startDate(), CLUB_ZONE).isAfter(toDay))
                    .filter(e -> q.isEmpty() || (e.title() + " " + e.location()).toLowerCase(Locale.ROOT).contains(q))
                    .limit(max).map(McpToolSupport::eventRow).toList();
        });
    }

    @Tool(description = "One event with its teams and roster: everyone on those teams with attendance and PRAE amount. "
            + "Use each roster entry's membership_id with set_attendance.",
            annotations = @Tool.Annotations(title = "Get event", readOnlyHint = true, destructiveHint = false, idempotentHint = true))
    String get_event(@ToolArg(description = "Event id") String event_id) {
        return runner.run("get_event", user -> {
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
            @ToolArg(description = "Event type from list_sports_and_event_types whose behaviour is this kind, e.g. Kurs; "
                    + "default Training / Turnier; required for kind event", required = false) String event_type,
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
        return runner.run("create_event", user -> {
            requirePermission(user, Permission.EVENTS_MANAGE);
            if (!ClubModels.KINDS.containsKey(kind)) {
                throw new IllegalArgumentException("kind must be training, tournament or event.");
            }
            ClubStore club = user.club();
            String type = eventType(club, kind, event_type);
            if ("event".equals(kind) && type.isEmpty()) {
                throw new IllegalArgumentException("event_type is required for kind event; see list_sports_and_event_types.");
            }
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
                    teamIds(club, team_ids), club.createdBy(), type);
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
            @ToolArg(description = "Event type with this event's behaviour, from list_sports_and_event_types", required = false) String event_type,
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
        return runner.run("update_event", user -> {
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
                    team_ids != null ? teamIds(club, team_ids) : e.teamIds(), e.createdBy(),
                    event_type != null ? eventType(club, e.kind(), event_type) : e.eventType());
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
        return runner.run("set_attendance", user -> {
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

}
