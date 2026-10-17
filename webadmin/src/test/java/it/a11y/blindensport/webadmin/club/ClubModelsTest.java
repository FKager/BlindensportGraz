package it.a11y.blindensport.webadmin.club;

import it.a11y.blindensport.webadmin.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webadmin.club.ClubModels.Membership;
import it.a11y.blindensport.webadmin.ui.AttendanceRosterAccess;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ClubModelsTest {
    private static ClubEvent event(String kind, String start, String end, List<String> teams) {
        return new ClubEvent("e", kind, "T", "", "", "", "", "", "", Instant.parse(start), Instant.parse(end), "", "",
                null, null, null, teams, "");
    }

    @Test
    void praeCapPerTrainingAndPerTournamentDay() {
        assertEquals(90, event("training", "2026-10-20T16:00:00Z", "2026-10-20T17:30:00Z", List.of()).maxPrae());
        var tournament = event("tournament", "2026-10-23T07:00:00Z", "2026-10-25T16:00:00Z", List.of());
        assertEquals(3, tournament.dayCount());
        assertEquals(360, tournament.maxPrae());
    }

    @Test
    void helpersAreCoachesAndAssistants() {
        assertTrue(new Membership("m", "t", null, null, "coach", null).isHelper());
        assertTrue(new Membership("m", "t", null, null, "assistant", null).isHelper());
        assertFalse(new Membership("m", "t", null, null, "player", null).isHelper());
    }

    @Test
    void rosterAcrossTeamsListsEachPersonOnce() {
        var a = new Membership("1", "t1", "anna", null, "player", null);
        var aAgain = new Membership("2", "t2", "anna", null, "coach", null);
        var bert = new Membership("3", "t2", "bert", null, "player", null);
        var other = new Membership("4", "t3", "carl", null, "player", null);
        var roster = AttendanceRosterAccess.roster(event("training", "2026-10-20T16:00:00Z", "2026-10-20T17:00:00Z",
                List.of("t1", "t2")), List.of(a, aAgain, bert, other), m -> m.memberId());
        assertEquals(List.of("1", "3"), roster.stream().map(Membership::id).toList());
        assertTrue(AttendanceRosterAccess.roster(event("training", "2026-10-20T16:00:00Z", "2026-10-20T17:00:00Z",
                List.of()), List.of(a), m -> "x").isEmpty(), "no teams → nobody");
    }
}
