package it.a11y.blindensport.webui.reports;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import it.a11y.blindensport.webui.club.ClubModels.Attendance;
import it.a11y.blindensport.webui.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webui.club.ClubModels.Membership;
import it.a11y.blindensport.webui.members.MemberRecord;
import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.TestFactory;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;

import static it.a11y.blindensport.webui.members.Dates.CLUB_ZONE;
import static org.junit.jupiter.api.Assertions.assertEquals;

/**
 * The TeilnehmerInnenliste scenarios in Shared/ReportFixtures/teilnehmerliste.json,
 * which the app's TeilnehmerlisteFixtureTests.swift reads too.
 */
class TeilnehmerlisteFixtureTest {
    private static final Path FIXTURE = Path.of("..", "Shared", "ReportFixtures", "teilnehmerliste.json");

    private static Instant at(JsonNode m) {
        return LocalDateTime.of(m.path("year").asInt(), m.path("month").asInt(), m.path("day").asInt(),
                m.path("hour").asInt(), 0).atZone(CLUB_ZONE).toInstant();
    }

    private static List<List<String>> rows(Teilnehmerliste list) {
        return list.rows().stream().map(r -> List.of(r.name(), r.wohnort())).toList();
    }

    private static List<List<String>> rows(JsonNode expected) {
        List<List<String>> result = new ArrayList<>();
        expected.forEach(r -> result.add(List.of(r.get(0).asText(), r.get(1).asText())));
        return result;
    }

    @TestFactory
    Stream<DynamicTest> scenarios() throws IOException {
        JsonNode fixture = new ObjectMapper().readTree(Files.readString(FIXTURE));
        Map<String, MemberRecord> members = new HashMap<>();
        fixture.path("people").forEach(p -> members.put(p.path("id").asText(), new MemberRecord(p.path("id").asText(),
                p.path("first").asText(), p.path("last").asText(), "", "", p.path("city").asText(""), "", "", "", "",
                null, "", p.path("gender").asText(""), "", "", "", true, null)));
        List<Membership> memberships = new ArrayList<>();
        fixture.path("memberships").forEach(m -> memberships.add(new Membership(m.path("id").asText(),
                m.path("team").asText(), m.path("person").asText(), null, m.path("role").asText(), null)));

        List<DynamicTest> tests = new ArrayList<>();
        for (JsonNode s : fixture.path("scenarios")) {
            tests.add(DynamicTest.dynamicTest(s.path("name").asText(), () -> {
                ClubEvent tournament = new ClubEvent("t", "tournament", "Turnier", "Torball", "Halle", "", "", "Graz",
                        "", at(s.path("start")), at(s.path("end")), "", "planned", null, null, null,
                        List.of("damen", "herren"), "");
                List<Attendance> attendances = new ArrayList<>();
                s.path("attendances").forEach(a -> attendances.add(new Attendance(a.path("id").asText(), "t",
                        a.path("membership").asText(), a.path("attended").asBoolean(), null)));

                Teilnehmerliste.Pair pair = Teilnehmerliste.forTournament(tournament, attendances, memberships, members,
                        Map.of());

                JsonNode want = s.path("expected");
                assertEquals(rows(want.path("sportler")), rows(pair.sportler()));
                assertEquals(rows(want.path("helfer")), rows(pair.helfer()));
                assertEquals(want.path("days").asInt(), pair.sportler().dayCount());
            }));
        }
        return tests.stream();
    }
}
