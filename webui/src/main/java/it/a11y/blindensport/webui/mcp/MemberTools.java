package it.a11y.blindensport.webui.mcp;

import io.quarkiverse.mcp.server.Tool;
import io.quarkiverse.mcp.server.ToolArg;
import it.a11y.blindensport.webui.auth.Permission;
import it.a11y.blindensport.webui.club.ClubModels.Membership;
import it.a11y.blindensport.webui.club.ClubModels.Team;
import it.a11y.blindensport.webui.club.ClubModels;
import it.a11y.blindensport.webui.club.ClubStore;
import it.a11y.blindensport.webui.members.MemberPrivate;
import it.a11y.blindensport.webui.members.MemberRecord;
import it.a11y.blindensport.webui.members.MemberStatus;
import jakarta.inject.Inject;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import static it.a11y.blindensport.webui.mcp.McpToolSupport.*;

/**
 * MCP tools for the signed-in account, members and teams. The rules of every MCP tool (see {@link McpToolSupport}): it
 * runs as the signed-in person, so RLS and their role decide; protected
 * member fields never appear in a result and can't be written.
 */
public class MemberTools {
    @Inject
    McpToolRunner runner;

    // ---------------------------------------------------------------- who

    @Tool(description = "Who is signed in: name, role and what the account may do.",
            annotations = @Tool.Annotations(title = "Who am I", readOnlyHint = true, destructiveHint = false, idempotentHint = true))
    String whoami() {
        return runner.run("whoami", user -> {
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
        return runner.run("list_members", user -> {
            String q = query == null ? "" : query.trim().toLowerCase(Locale.ROOT);
            return user.roster().all(false).stream()
                    .filter(m -> status == null || status.equals(m.status()))
                    .filter(m -> q.isEmpty() || (m.fullName() + " " + m.email() + " " + m.memberNumber())
                            .toLowerCase(Locale.ROOT).contains(q))
                    .map(McpToolSupport::memberSummary).toList();
        });
    }

    @Tool(description = "One member's contact details and teams. Protected data (SVNR, IBAN, birth date, health) is never returned.",
            annotations = @Tool.Annotations(title = "Get member", readOnlyHint = true, destructiveHint = false, idempotentHint = true))
    String get_member(@ToolArg(description = "Member id") String member_id) {
        return runner.run("get_member", user -> {
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
        return runner.run("create_member", user -> {
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
        return runner.run("update_member", user -> {
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
        return runner.run("list_teams", user -> {
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
        return runner.run("create_team", user -> {
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
        return runner.run("add_team_member", user -> {
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

}
