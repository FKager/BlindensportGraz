package it.a11y.blindensport.webadmin.prae;

import it.a11y.blindensport.webadmin.club.ClubModels.Attendance;
import it.a11y.blindensport.webadmin.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webadmin.club.ClubModels.Membership;
import it.a11y.blindensport.webadmin.members.MemberRecord;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

import static it.a11y.blindensport.webadmin.members.Dates.CLUB_ZONE;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** The rules of PraeCalculationTests.swift; the two calculators must keep agreeing. */
class PraeCalculatorTest {
    private static final PraeForm.Person PERSON = new PraeForm.Person("p", "Erika Muster", "Muster", "Erika", List.of("m1", "m2"), null);

    private static ClubEvent event(String id, String kind, String title, String start, String end) {
        return new ClubEvent(id, kind, title, "", "", "", "", "", "", at(start), at(end), "", "", null, null, null, List.of(), "");
    }

    private static Instant at(String local) {
        return LocalDateTime.parse(local).atZone(CLUB_ZONE).toInstant();
    }

    private static Attendance attended(String event, String membership, int amount) {
        return new Attendance(event + membership, event, membership, true, BigDecimal.valueOf(amount));
    }

    @Test
    void spreadsOverDaysWithTheMiddleDayTakingTheRemainder() {
        assertEquals(List.of(33.0, 34.0, 33.0), PraeCalculator.spreadEvenly(100, 3));
        assertEquals(List.of(50.0, 50.0), PraeCalculator.spreadEvenly(100, 2));
        assertEquals(List.of(60.0), PraeCalculator.spreadEvenly(60, 1));
        assertEquals(List.of(), PraeCalculator.spreadEvenly(60, 0));
    }

    @Test
    void oneFormPerTrainingTitleWithSessionsOfADaySummed() {
        var a = event("a", "training", "Torball", "2026-03-03T18:00:00", "2026-03-03T19:30:00");
        var b = event("b", "training", "Torball", "2026-03-03T20:00:00", "2026-03-03T21:00:00");
        var c = event("c", "training", "Lauf", "2026-03-10T18:00:00", "2026-03-10T19:30:00");
        List<PraeForm> forms = PraeCalculator.monthForms(PERSON, 3, 2026, List.of(a, b, c),
                List.of(attended("a", "m1", 40), attended("b", "m2", 30), attended("c", "m1", 50)));
        assertEquals(List.of("Torball", "Lauf"), forms.stream().map(PraeForm::purpose).toList());
        assertEquals(List.of(new PraeForm.DayEntry(3, 70, "Torball")), forms.get(0).entries());
        assertEquals(120, forms.get(0).personTotal() );
        assertEquals(120, forms.get(1).personTotal(), "caps look at the person across forms");
    }

    @Test
    void ignoresOtherMonthsPeopleAndAbsences() {
        var a = event("a", "training", "T", "2026-03-03T18:00:00", "2026-03-03T19:00:00");
        var april = event("b", "training", "T", "2026-04-01T18:00:00", "2026-04-01T19:00:00");
        var absent = new Attendance("x", "a", "m1", false, BigDecimal.TEN);
        assertTrue(PraeCalculator.monthForms(PERSON, 3, 2026, List.of(a, april),
                List.of(absent, attended("a", "other", 40), attended("b", "m1", 40))).isEmpty());
    }

    @Test
    void monthUsesTheClubsTimeZone() {
        var lateInMarch = event("a", "training", "T", "2026-03-31T23:30:00", "2026-04-01T00:30:00");
        assertEquals(31, PraeCalculator.monthForms(PERSON, 3, 2026, List.of(lateInMarch), List.of(attended("a", "m1", 40)))
                .get(0).entries().get(0).day());
    }

    @Test
    void tournamentRunningIntoNextMonthAddsUpToTheEnteredAmount() {
        var t = event("t", "tournament", "Cup", "2026-03-30T09:00:00", "2026-04-01T18:00:00");
        List<PraeForm> forms = PraeCalculator.tournamentForms(PERSON, t, List.of(attended("t", "m1", 100)));
        assertEquals(2, forms.size());
        assertEquals(67, forms.get(0).total(), "33 + 34, the middle day takes the remainder");
        assertEquals(33, forms.get(1).total());
        assertTrue(forms.get(0).spansSeveralMonths());
        assertEquals(List.of(30, 31), forms.get(0).entries().stream().map(PraeForm.DayEntry::day).toList());
        assertEquals(List.of(1), forms.get(1).entries().stream().map(PraeForm.DayEntry::day).toList());
    }

    @Test
    void capsAreFlaggedNotEnforced() {
        var a = event("a", "training", "T", "2026-03-03T18:00:00", "2026-03-03T19:00:00");
        var b = event("b", "training", "U", "2026-03-03T20:00:00", "2026-03-03T21:00:00");
        List<PraeForm> forms = PraeCalculator.monthForms(PERSON, 3, 2026, List.of(a, b),
                List.of(attended("a", "m1", 70), attended("b", "m1", 70)));
        assertEquals(2, forms.size());
        assertEquals(1, forms.get(0).capWarnings().size(), "€140 that day across both forms");
    }

    @Test
    void helpersDedupedAcrossTeamsAndPlayersLeftOut() {
        MemberRecord member = new MemberRecord("AA", "Erika", "Muster", "", "", "", "", "", "", "", null, "", "", "", "", "", true, null);
        var coach = new Membership("1", "t1", "aa", null, "coach", Instant.now());
        var assistant = new Membership("2", "t2", "aa", null, "assistant", Instant.now());
        var player = new Membership("3", "t2", "bb", null, "player", Instant.now());
        var byAccount = new Membership("4", "t2", null, "u1", "coach", Instant.now());
        List<PraeForm.Person> people = PraeCalculator.eligiblePeople(List.of(coach, assistant, player, byAccount),
                id -> "aa".equals(id) ? member : null,
                Map.of("u1", new PraeCalculator.AccountName("Zoe", "Adler")));
        assertEquals(List.of("Adler, Zoe", "Muster, Erika"), people.stream().map(PraeForm.Person::formName).toList());
        assertEquals(List.of("1", "2"), people.get(1).membershipIds());
    }

    @Test
    void addressSkipsEmptyParts() {
        MemberRecord member = new MemberRecord("AA", "E", "M", "Gasse 1", "8010", "Graz", "", "", "", "", null, "", "", "", "", "", true, null);
        assertEquals("Gasse 1, 8010 Graz", new PraeForm.Person("p", "E M", "M", "E", List.of(), member).address());
        assertEquals("", PERSON.address());
    }
}
