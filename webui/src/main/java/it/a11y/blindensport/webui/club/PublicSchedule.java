package it.a11y.blindensport.webui.club;

import com.fasterxml.jackson.databind.JsonNode;
import it.a11y.blindensport.webui.members.Dates;
import it.a11y.blindensport.webui.supabase.Postgrest;

import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

import static it.a11y.blindensport.webui.supabase.Postgrest.order;

/**
 * What anyone may see without an account: upcoming trainings and tournaments
 * from {@code public_schedule}, with name, day and location only. Same rule as
 * the app's UpcomingScheduleSections: cancelled trainings are left out, and a
 * tournament stays listed until its last day.
 */
public final class PublicSchedule {
    public record Entry(String kind, String title, String location, LocalDate firstDay, LocalDate lastDay) {
    }

    private static final String CANCELLED = "cancelled";

    private PublicSchedule() {
    }

    /** @param db PostgREST without a user: the view is open to anon on purpose */
    public static List<Entry> upcoming(Postgrest db, LocalDate today) {
        Instant start = today.atStartOfDay(Dates.CLUB_ZONE).toInstant();
        List<Entry> entries = new ArrayList<>();
        for (JsonNode row : db.select("public_schedule", "kind,title,location,city,start_date,end_date,status",
                Postgrest.gte("end_date", Dates.formatTimestamp(start)), order("start_date.asc"))) {
            if (!CANCELLED.equals(row.path("status").asText())) {
                entries.add(new Entry(row.path("kind").asText(""), row.path("title").asText(""), place(row),
                        day(row, "start_date"), day(row, "end_date")));
            }
        }
        return entries;
    }

    private static String place(JsonNode row) {
        String location = row.path("location").asText("");
        return location.isBlank() ? row.path("city").asText("") : location;
    }

    private static LocalDate day(JsonNode row, String key) {
        return LocalDate.ofInstant(Dates.parseTimestamp(row.path(key).asText(null)).orElseThrow(), Dates.CLUB_ZONE);
    }
}
