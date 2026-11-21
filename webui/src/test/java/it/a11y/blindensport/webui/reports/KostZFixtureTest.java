package it.a11y.blindensport.webui.reports;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import it.a11y.blindensport.webui.club.ClubModels.Attendance;
import it.a11y.blindensport.webui.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webui.prae.PraeForm;
import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.TestFactory;

import java.io.IOException;
import java.math.BigDecimal;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;

import static it.a11y.blindensport.webui.members.Dates.CLUB_ZONE;
import static org.junit.jupiter.api.Assertions.assertEquals;

/**
 * The KostZ scenarios in Shared/ReportFixtures/kostz.json, which the app's
 * KostZFixtureTests.swift reads too: both must give the same form.
 */
class KostZFixtureTest {
    private static final Path FIXTURE = Path.of("..", "Shared", "ReportFixtures", "kostz.json");

    private static Instant at(int year, int month, int day, int hour) {
        return LocalDateTime.of(year, month, day, hour, 0).atZone(CLUB_ZONE).toInstant();
    }

    private static ClubEvent event(String id, String kind, String title, Instant start, Instant end, String status) {
        return new ClubEvent(id, kind, title, "Torball", "", "", "", "Graz", "", start, end, "", status, null, null, null,
                List.of(), "");
    }

    private static BigDecimal amount(JsonNode a) {
        return a.path("amount").isNull() ? null : a.path("amount").decimalValue();
    }

    /** Coaches and assistants, by last name — what PraeCalculator.eligiblePeople gives the KostZ. */
    private static List<PraeForm.Person> eligible(JsonNode fixture) {
        Map<String, JsonNode> people = new HashMap<>();
        fixture.path("people").forEach(p -> people.put(p.path("id").asText(), p));
        List<PraeForm.Person> result = new ArrayList<>();
        for (JsonNode m : fixture.path("memberships")) {
            String role = m.path("role").asText();
            if (role.equals("coach") || role.equals("assistant")) {
                JsonNode p = people.get(m.path("person").asText());
                result.add(new PraeForm.Person(p.path("id").asText(),
                        p.path("first").asText() + " " + p.path("last").asText(), p.path("last").asText(),
                        p.path("first").asText(), List.of(m.path("id").asText()), null));
            }
        }
        result.sort(Comparator.comparing(PraeForm.Person::lastName).thenComparing(PraeForm.Person::firstName));
        return result;
    }

    private static List<List<Object>> people(KostZ kostz) {
        return kostz.people().stream().map(p -> List.<Object>of(p.person().lastName(), p.amount())).toList();
    }

    private static List<List<Object>> people(JsonNode expected) {
        List<List<Object>> result = new ArrayList<>();
        expected.forEach(p -> result.add(List.of(p.get(0).asText(), p.get(1).asDouble())));
        return result;
    }

    @TestFactory
    Stream<DynamicTest> scenarios() throws IOException {
        JsonNode fixture = new ObjectMapper().readTree(Files.readString(FIXTURE));
        List<PraeForm.Person> eligible = eligible(fixture);
        List<DynamicTest> tests = new ArrayList<>();
        for (JsonNode s : fixture.path("month")) {
            tests.add(DynamicTest.dynamicTest(s.path("name").asText(), () -> {
                int month = s.path("month").asInt();
                int year = s.path("year").asInt();
                List<ClubEvent> events = new ArrayList<>();
                for (JsonNode t : s.path("trainings")) {
                    Instant start = at(year, t.path("month").asInt(month), t.path("day").asInt(), t.path("hour").asInt());
                    events.add(event(t.path("id").asText(), "training", t.path("title").asText(), start,
                            start.plusSeconds(5400), t.path("status").asText("open")));
                }
                for (JsonNode t : s.path("tournaments")) {
                    Instant start = at(year, month, t.path("day").asInt(), 9);
                    events.add(event(t.path("id").asText(), "tournament", t.path("title").asText(), start,
                            start.plusSeconds(8 * 3600), "planned"));
                }
                List<Attendance> attendances = new ArrayList<>();
                int i = 0;
                for (JsonNode a : s.path("attendances")) {
                    attendances.add(new Attendance("a" + i++, a.path("event").asText(), a.path("membership").asText(),
                            a.path("attended").asBoolean(), amount(a)));
                }

                KostZ kostz = KostZ.month(month, year, eligible, events, attendances);

                JsonNode want = s.path("expected");
                assertEquals(want.path("betrifft").asText(), kostz.betrifft());
                assertEquals(want.path("dayCount").asInt(), kostz.dayCount());
                assertEquals(want.path("startDay").asInt(), kostz.start().getDayOfMonth());
                assertEquals(want.path("endDay").asInt(), kostz.end().getDayOfMonth());
                assertEquals(people(want.path("people")), people(kostz));
                assertEquals(want.path("total").asDouble(), kostz.total());
            }));
        }
        for (JsonNode s : fixture.path("tournament")) {
            tests.add(DynamicTest.dynamicTest(s.path("name").asText(), () -> {
                JsonNode a = s.path("start");
                JsonNode e = s.path("end");
                ClubEvent tournament = event("t", "tournament", "Turnier",
                        at(a.path("year").asInt(), a.path("month").asInt(), a.path("day").asInt(), a.path("hour").asInt()),
                        at(e.path("year").asInt(), e.path("month").asInt(), e.path("day").asInt(), e.path("hour").asInt()),
                        "planned");
                List<Attendance> attendances = new ArrayList<>();
                int i = 0;
                for (JsonNode row : s.path("attendances")) {
                    attendances.add(new Attendance("a" + i++, "t", row.path("membership").asText(),
                            row.path("attended").asBoolean(), amount(row)));
                }

                KostZ kostz = KostZ.tournament(tournament, eligible, attendances);

                JsonNode want = s.path("expected");
                assertEquals(want.path("dayCount").asInt(), kostz.dayCount());
                assertEquals(people(want.path("people")), people(kostz));
                assertEquals(want.path("total").asDouble(), kostz.total());
            }));
        }
        return tests.stream();
    }
}
