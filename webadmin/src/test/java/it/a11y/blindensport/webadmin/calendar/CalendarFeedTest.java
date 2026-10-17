package it.a11y.blindensport.webadmin.calendar;

import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.List;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** Port of RootCLI's CalendarFeedTests. */
class CalendarFeedTest {
    private static CalendarFeed.EventFields event(String uid, String title, List<String> teamIds, long start) {
        Instant s = Instant.ofEpochSecond(start);
        return new CalendarFeed.EventFields(uid, title, "Graz", s, s.plusSeconds(3600), teamIds);
    }

    private static CalendarFeed.EventFields event(String uid, List<String> teamIds) {
        return event(uid, "T", teamIds, 1_700_000_000L);
    }

    @Test
    void adminSeesEveryEventRegardlessOfTeamScoping() {
        var events = List.of(event("a", List.of()), event("b", List.of("team-x")));
        var visible = CalendarFeed.visibleEvents(events, "admin", Set.of());
        assertEquals(List.of("a", "b"), visible.stream().map(CalendarFeed.EventFields::uid).toList());
    }

    @Test
    void memberSeesUnscopedAndOwnTeamEventsOnly() {
        var events = List.of(event("unscoped", List.of()), event("own", List.of("team-x", "team-y")),
                event("other", List.of("team-z")));
        var visible = CalendarFeed.visibleEvents(events, "member", Set.of("team-x"));
        assertEquals(Set.of("unscoped", "own"),
                Set.copyOf(visible.stream().map(CalendarFeed.EventFields::uid).toList()));
    }

    @Test
    void memberWithNoTeamsOnlySeesUnscopedEvents() {
        var visible = CalendarFeed.visibleEvents(
                List.of(event("unscoped", List.of()), event("scoped", List.of("team-x"))), "member", Set.of());
        assertEquals(List.of("unscoped"), visible.stream().map(CalendarFeed.EventFields::uid).toList());
    }

    @Test
    void renderProducesOneVEventPerEventSortedByStartDate() {
        var later = event("later", "Später", List.of(), 2_000_000_000L);
        var earlier = event("earlier", "Früher", List.of(), 1_000_000_000L);
        String ics = CalendarFeed.render(List.of(later, earlier), Instant.now());
        assertTrue(ics.startsWith("BEGIN:VCALENDAR\r\n"));
        assertTrue(ics.endsWith("END:VCALENDAR\r\n"));
        assertEquals(2, ics.split("BEGIN:VEVENT", -1).length - 1);
        assertTrue(ics.indexOf("SUMMARY:Früher") < ics.indexOf("SUMMARY:Später"));
    }

    @Test
    void renderEscapesCommasSemicolonsAndBackslashesInTextFields() {
        String ics = CalendarFeed.render(List.of(event("x", "Turnier; Graz, \\Test", List.of(), 1L)), Instant.now());
        assertTrue(ics.contains("SUMMARY:Turnier\\; Graz\\, \\\\Test"));
    }

    @Test
    void renderOfNoEventsIsStillAValidEmptyCalendar() {
        String ics = CalendarFeed.render(List.of(), Instant.now());
        assertTrue(ics.contains("BEGIN:VCALENDAR"));
        assertTrue(ics.contains("END:VCALENDAR"));
        assertFalse(ics.contains("BEGIN:VEVENT"));
    }

    @Test
    void renderMatchesTheSwiftFeedByteForByte() {
        Instant now = Instant.parse("2026-10-17T08:00:00Z");
        var e = new CalendarFeed.EventFields("ABC", "Training", "Halle", Instant.parse("2026-10-20T16:00:00Z"),
                Instant.parse("2026-10-20T18:00:00Z"), List.of());
        assertEquals("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//BlindensportGraz//DE\r\nCALSCALE:GREGORIAN\r\n"
                + "X-WR-CALNAME:Blindensport Graz\r\nBEGIN:VEVENT\r\nUID:ABC\r\nDTSTAMP:20261017T080000Z\r\n"
                + "DTSTART:20261020T160000Z\r\nDTEND:20261020T180000Z\r\nSUMMARY:Training\r\nLOCATION:Halle\r\n"
                + "END:VEVENT\r\nEND:VCALENDAR\r\n", CalendarFeed.render(List.of(e), now));
    }
}
