package it.a11y.blindensport.webui.reports;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import it.a11y.blindensport.webui.club.ClubModels.Attendance;
import it.a11y.blindensport.webui.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webui.club.ClubModels.Membership;
import it.a11y.blindensport.webui.club.ClubModels.Team;
import it.a11y.blindensport.webui.members.MemberRecord;
import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.TestFactory;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;

import static it.a11y.blindensport.webui.members.Dates.CLUB_ZONE;
import static org.junit.jupiter.api.Assertions.assertEquals;

/**
 * The Trainingsfrequenzliste scenarios in
 * Shared/ReportFixtures/trainingsfrequenzliste.json, which the app's
 * TrainingsfrequenzlisteFixtureTests.swift reads too.
 */
class TrainingsfrequenzlisteFixtureTest {
    private static final Path FIXTURE = Path.of("..", "Shared", "ReportFixtures", "trainingsfrequenzliste.json");

    private static MemberRecord member(JsonNode p) {
        return new MemberRecord(p.path("id").asText(), p.path("first").asText(), p.path("last").asText(), "", "", "",
                "", "", "", "", null, "", p.path("gender").asText(""), "", "", "", true, null);
    }

    @TestFactory
    Stream<DynamicTest> scenarios() throws IOException {
        JsonNode fixture = new ObjectMapper().readTree(Files.readString(FIXTURE));
        Map<String, MemberRecord> members = new HashMap<>();
        fixture.path("people").forEach(p -> members.put(p.path("id").asText(), member(p)));
        List<Team> teams = new ArrayList<>();
        fixture.path("teams").forEach(t -> teams.add(new Team(t.path("id").asText(), t.path("name").asText(),
                t.path("sport").asText(), "")));
        List<Membership> memberships = new ArrayList<>();
        fixture.path("memberships").forEach(m -> memberships.add(new Membership(m.path("id").asText(),
                m.path("team").asText(), m.path("person").asText(), null, m.path("role").asText(), null)));

        List<DynamicTest> tests = new ArrayList<>();
        for (JsonNode s : fixture.path("scenarios")) {
            tests.add(DynamicTest.dynamicTest(s.path("name").asText(), () -> {
                int year = s.path("year").asInt();
                List<ClubEvent> events = new ArrayList<>();
                for (JsonNode t : s.path("trainings")) {
                    LocalDateTime begin = LocalDateTime.of(year, t.path("month").asInt(), t.path("day").asInt(),
                            t.path("hour").asInt(), 0);
                    List<String> teamIds = new ArrayList<>();
                    t.path("teams").forEach(id -> teamIds.add(id.asText()));
                    events.add(new ClubEvent(t.path("id").asText(), "training", t.path("title").asText(),
                            t.path("sport").asText(s.path("sport").asText()), t.path("location").asText(), "", "", "",
                            "", begin.atZone(CLUB_ZONE).toInstant(), begin.plusHours(2).atZone(CLUB_ZONE).toInstant(),
                            "", t.path("status").asText("open"), null, null, null, teamIds, ""));
                }
                List<Attendance> attendances = new ArrayList<>();
                int i = 0;
                for (JsonNode a : s.path("attendances")) {
                    attendances.add(new Attendance("a" + i++, a.path("event").asText(), a.path("membership").asText(),
                            a.path("attended").asBoolean(), null));
                }

                Trainingsfrequenzliste list = Trainingsfrequenzliste.of(s.path("sport").asText(), s.path("half").asInt(),
                        year, events, attendances, teams, memberships, members, Map.of());

                JsonNode want = s.path("expected");
                List<LocalDate> dates = new ArrayList<>();
                want.path("dates").forEach(d -> dates.add(LocalDate.parse(d.asText())));
                assertEquals(dates, list.dates());
                assertEquals(want.path("title").asText(), list.title());
                assertEquals(want.path("location").asText(), list.location());
                List<String> teamNames = new ArrayList<>();
                want.path("teams").forEach(t -> teamNames.add(t.asText()));
                assertEquals(teamNames, list.teams());
                List<List<Object>> expectedPeople = new ArrayList<>();
                for (JsonNode p : want.path("people")) {
                    List<LocalDate> attended = new ArrayList<>();
                    p.path("attended").forEach(d -> attended.add(LocalDate.parse(d.asText())));
                    expectedPeople.add(List.of(p.path("last").asText(),
                            p.path("roleSuffix").isNull() ? "-" : p.path("roleSuffix").asText(), attended));
                }
                List<List<Object>> actualPeople = list.people().stream().map(p -> List.<Object>of(p.lastName(),
                        p.roleSuffix() == null ? "-" : p.roleSuffix(),
                        p.attended().stream().sorted().toList())).toList();
                assertEquals(expectedPeople, actualPeople);
            }));
        }
        return tests.stream();
    }
}
