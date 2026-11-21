package it.a11y.blindensport.webui.prae;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import it.a11y.blindensport.webui.club.ClubModels.Attendance;
import it.a11y.blindensport.webui.club.ClubModels.ClubEvent;
import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.TestFactory;

import java.io.IOException;
import java.math.BigDecimal;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Stream;

import static it.a11y.blindensport.webui.members.Dates.CLUB_ZONE;
import static org.junit.jupiter.api.Assertions.assertEquals;

/**
 * The PRAE scenarios in Shared/ReportFixtures/prae.json, which the app's
 * PraeFixtureTests.swift reads too: both calculators must give the same
 * forms, so the app and the web UI never print different amounts.
 */
class PraeFixtureTest {
    private static final Path FIXTURE = Path.of("..", "Shared", "ReportFixtures", "prae.json");
    private static final String MEMBERSHIP = "anna-coach";
    private static final PraeForm.Person ANNA =
            new PraeForm.Person("anna", "Anna Trainer", "Trainer", "Anna", List.of(MEMBERSHIP), null);

    private static JsonNode fixture() throws IOException {
        return new ObjectMapper().readTree(Files.readString(FIXTURE));
    }

    private static Instant at(int year, int month, int day, int hour) {
        return LocalDateTime.of(year, month, day, hour, 0).atZone(CLUB_ZONE).toInstant();
    }

    private static ClubEvent event(String id, String kind, String title, Instant start, Instant end, String status) {
        return new ClubEvent(id, kind, title, "Torball", "", "", "", "", "", start, end, "", status, null, null, null,
                List.of(), "");
    }

    private static Attendance attendance(JsonNode a) {
        BigDecimal amount = a.path("amount").isNull() ? null : a.path("amount").decimalValue();
        return new Attendance(a.path("event").asText() + "-anna", a.path("event").asText(), MEMBERSHIP,
                a.path("attended").asBoolean(), amount);
    }

    private static List<List<Double>> entries(List<PraeForm.DayEntry> entries) {
        return entries.stream().map(e -> List.of((double) e.day(), e.amount())).toList();
    }

    private static List<List<Double>> entries(JsonNode expected) {
        List<List<Double>> result = new ArrayList<>();
        expected.forEach(pair -> result.add(List.of(pair.get(0).asDouble(), pair.get(1).asDouble())));
        return result;
    }

    @TestFactory
    Stream<DynamicTest> monthFormsMatchTheSharedScenarios() throws IOException {
        List<DynamicTest> tests = new ArrayList<>();
        for (JsonNode scenario : fixture().path("month")) {
            tests.add(DynamicTest.dynamicTest(scenario.path("name").asText(), () -> {
                int month = scenario.path("month").asInt();
                int year = scenario.path("year").asInt();
                List<ClubEvent> trainings = new ArrayList<>();
                for (JsonNode t : scenario.path("trainings")) {
                    Instant start = at(year, t.path("month").asInt(month), t.path("day").asInt(), t.path("hour").asInt());
                    trainings.add(event(t.path("id").asText(), "training", t.path("title").asText(), start,
                            start.plusSeconds(5400), t.path("status").asText("open")));
                }
                List<Attendance> attendances = new ArrayList<>();
                scenario.path("attendances").forEach(a -> attendances.add(attendance(a)));

                List<PraeForm> forms = PraeCalculator.monthForms(ANNA, month, year, trainings, attendances);

                JsonNode expected = scenario.path("expected");
                assertEquals(expected.size(), forms.size(), "number of forms");
                for (int i = 0; i < forms.size(); i++) {
                    PraeForm form = forms.get(i);
                    JsonNode want = expected.get(i);
                    assertEquals(want.path("purpose").asText(), form.purpose());
                    assertEquals(entries(want.path("entries")), entries(form.entries()));
                    assertEquals(want.path("total").asDouble(), form.total());
                    assertEquals(want.path("personTotal").asDouble(), form.personTotal());
                    assertEquals(want.path("exceedsMonthlyCap").asBoolean(), form.personTotal() > PraeCalculator.MONTHLY_CAP);
                    List<Integer> days = new ArrayList<>();
                    want.path("daysExceedingDailyCap").forEach(d -> days.add(d.asInt()));
                    assertEquals(days, form.entries().stream()
                            .filter(e -> form.personDayTotals().getOrDefault(e.day(), e.amount()) > PraeCalculator.DAILY_CAP)
                            .map(PraeForm.DayEntry::day).toList());
                }
            }));
        }
        return tests.stream();
    }

    @TestFactory
    Stream<DynamicTest> tournamentFormsMatchTheSharedScenarios() throws IOException {
        List<DynamicTest> tests = new ArrayList<>();
        for (JsonNode scenario : fixture().path("tournament")) {
            tests.add(DynamicTest.dynamicTest(scenario.path("name").asText(), () -> {
                JsonNode s = scenario.path("start");
                JsonNode e = scenario.path("end");
                ClubEvent tournament = event("t", "tournament", "Turnier",
                        at(s.path("year").asInt(), s.path("month").asInt(), s.path("day").asInt(), s.path("hour").asInt()),
                        at(e.path("year").asInt(), e.path("month").asInt(), e.path("day").asInt(), e.path("hour").asInt()),
                        "planned");
                var attendance = new Attendance("t-anna", "t", MEMBERSHIP, true,
                        scenario.path("amount").decimalValue());

                List<PraeForm> forms = PraeCalculator.tournamentForms(ANNA, tournament, List.of(attendance));

                List<List<Double>> all = forms.stream().flatMap(f -> entries(f.entries()).stream()).toList();
                assertEquals(entries(scenario.path("expected")), all);
            }));
        }
        return tests.stream();
    }
}
