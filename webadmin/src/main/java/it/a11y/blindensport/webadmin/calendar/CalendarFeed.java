package it.a11y.blindensport.webadmin.calendar;

import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Set;

/**
 * One user's read-only webcal feed (port of RootCLI's {@code CalendarFeed}).
 * Only schedule data the same user already sees in the app — never PII.
 * Output must stay byte-compatible: subscribed calendars match entries by UID.
 */
public final class CalendarFeed {
    /** {@code teamIds} empty = visible to everyone, as in the app. */
    public record EventFields(String uid, String title, String location, Instant startDate, Instant endDate,
                              List<String> teamIds) {
    }

    private static final DateTimeFormatter ICS_TIME =
            DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'").withZone(ZoneOffset.UTC);

    private CalendarFeed() {
    }

    /** Admins see everything; anyone else unscoped events and those of their own teams. */
    public static List<EventFields> visibleEvents(List<EventFields> all, String role, Set<String> userTeamIds) {
        if ("admin".equals(role)) {
            return all;
        }
        return all.stream()
                .filter(e -> e.teamIds().isEmpty() || !Collections.disjoint(userTeamIds, e.teamIds()))
                .toList();
    }

    /** RFC 5545 VCALENDAR, one VEVENT per event, sorted by start, CRLF line ends. */
    public static String render(List<EventFields> events, Instant now) {
        String stamp = ICS_TIME.format(now);
        List<String> lines = new ArrayList<>(List.of(
                "BEGIN:VCALENDAR",
                "VERSION:2.0",
                "PRODID:-//BlindensportGraz//DE",
                "CALSCALE:GREGORIAN",
                "X-WR-CALNAME:Blindensport Graz"));
        events.stream().sorted(Comparator.comparing(EventFields::startDate)).forEach(e -> lines.addAll(List.of(
                "BEGIN:VEVENT",
                "UID:" + e.uid(),
                "DTSTAMP:" + stamp,
                "DTSTART:" + ICS_TIME.format(e.startDate()),
                "DTEND:" + ICS_TIME.format(e.endDate()),
                "SUMMARY:" + escape(e.title()),
                "LOCATION:" + escape(e.location()),
                "END:VEVENT")));
        lines.add("END:VCALENDAR");
        return String.join("\r\n", lines) + "\r\n";
    }

    /** RFC 5545 §3.3.11 text escaping — same four characters as the app. */
    static String escape(String text) {
        return text.replace("\\", "\\\\").replace(",", "\\,").replace(";", "\\;").replace("\n", "\\n");
    }
}
