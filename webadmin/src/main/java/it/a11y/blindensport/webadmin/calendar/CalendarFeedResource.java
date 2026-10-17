package it.a11y.blindensport.webadmin.calendar;

import com.fasterxml.jackson.databind.JsonNode;
import it.a11y.blindensport.webadmin.members.Dates;
import it.a11y.blindensport.webadmin.supabase.Postgrest;
import it.a11y.blindensport.webadmin.supabase.Supabase;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.core.Response;

import java.time.Instant;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

import static it.a11y.blindensport.webadmin.supabase.Postgrest.eq;

/**
 * {@code GET /calendar/{token}[.ics]} — one user's webcal feed, the URL the
 * app's account screen hands out. Not behind the admin sign-in: calendar
 * clients can't log in, so the unguessable, rotatable
 * {@code profiles.calendar_token} is the credential. Reads with the service
 * key (there is no user session) and filters like the app does.
 */
@Path("/calendar/{token}")
public class CalendarFeedResource {
    @Inject
    Supabase supabase;

    @GET
    public Response feed(@PathParam("token") String raw) {
        String token = raw.endsWith(".ics") ? raw.substring(0, raw.length() - 4) : raw;
        // Tokens are hex (or legacy UUIDs); anything else can't match and
        // must not reach the PostgREST filter.
        if (token.isEmpty() || !token.matches("[0-9a-fA-F-]+")) {
            throw new NotFoundException();
        }
        Postgrest db = supabase.asService();
        var profiles = db.select("profiles", "id", eq("calendar_token", token));
        if (profiles.isEmpty()) {
            // Same 404 as an unknown path — doesn't hint whether a token existed.
            throw new NotFoundException();
        }
        String userId = profiles.get(0).path("id").asText();
        // Blocking already replaces the token; this covers a block set
        // outside the app (dashboard, service role).
        JsonNode unblocked = db.rpc("unblocked_user_ids", Map.of("ids", List.of(userId)));
        boolean isUnblocked = false;
        for (JsonNode id : unblocked) {
            isUnblocked |= id.asText().equalsIgnoreCase(userId);
        }
        if (!isUnblocked) {
            throw new NotFoundException();
        }
        var roles = db.select("user_roles", "role", eq("user_id", userId));
        String storedRole = roles.isEmpty() ? "member" : roles.get(0).path("role").asText("member");
        // CalendarFeed knows member/coach/admin; root sees everything too.
        String role = "root".equals(storedRole) ? "admin" : storedRole;
        Set<String> userTeamIds = new HashSet<>();
        if (!"admin".equals(role)) {
            db.select("team_memberships", "team_id", eq("user_id", userId)).forEach(row -> {
                if (row.hasNonNull("team_id")) {
                    userTeamIds.add(row.get("team_id").asText().toLowerCase(Locale.ROOT));
                }
            });
        }

        List<CalendarFeed.EventFields> events = new ArrayList<>();
        for (JsonNode row : db.select("events", "id,title,location,start_date,end_date,team_ids",
                Postgrest.in("kind", List.of("training", "tournament")))) {
            var start = Dates.parseTimestamp(row.path("start_date").asText(null));
            var end = Dates.parseTimestamp(row.path("end_date").asText(null));
            if (!row.hasNonNull("id") || !row.hasNonNull("title") || start.isEmpty() || end.isEmpty()) {
                continue;
            }
            List<String> teamIds = new ArrayList<>();
            row.path("team_ids").forEach(t -> teamIds.add(t.asText().toLowerCase(Locale.ROOT)));
            // UIDs stay the uppercase ids the CloudKit-era feed used, so
            // subscribed calendars keep their entries.
            events.add(new CalendarFeed.EventFields(row.get("id").asText().toUpperCase(Locale.ROOT),
                    row.get("title").asText(), row.path("location").asText(""), start.get(), end.get(), teamIds));
        }

        String ics = CalendarFeed.render(CalendarFeed.visibleEvents(events, role, userTeamIds), Instant.now());
        return Response.ok(ics)
                .header("Content-Type", "text/calendar; charset=utf-8")
                .header("Content-Disposition", "inline; filename=\"blindensportgraz.ics\"")
                .build();
    }
}
