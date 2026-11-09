package it.a11y.blindensport.webui.reports;

import it.a11y.blindensport.webui.club.ClubModels.Attendance;
import it.a11y.blindensport.webui.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webui.club.ClubModels.Membership;
import it.a11y.blindensport.webui.members.MemberPrivate;
import it.a11y.blindensport.webui.members.MemberRecord;
import it.a11y.blindensport.webui.prae.PraeCalculator;
import it.a11y.blindensport.webui.prae.PraeCalculator.AccountName;
import it.a11y.blindensport.webui.prae.PraeForm;
import it.a11y.blindensport.webui.prae.PraeForm.Person;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIf;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

import static it.a11y.blindensport.webui.members.Dates.CLUB_ZONE;
import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** KostZ, TeilnehmerInnenliste and the Sammelabrechnung — ports of the app's KostZCalculationTests and friends. */
class ReportsTest {
    private static final Path APP_RESOURCES = Path.of("../BlindensportGraz/Resources");

    private static final MemberRecord COACH = member("c", "Erika", "Muster", "Graz");
    private static final MemberRecord HELPER = member("h", "Bernd", "Albrecht", "Leoben");
    private static final MemberRecord PLAYER = member("p", "Zoe", "Zach", "Wien");
    private static final MemberRecord PLAYER2 = member("q", "Anna", "Berger", "");

    private static final List<Membership> MEMBERSHIPS = List.of(
            new Membership("mc", "t", "c", null, "coach", null),
            new Membership("mc2", "t2", "c", null, "assistant", null),
            new Membership("mh", "t", "h", null, "assistant", null),
            new Membership("mp", "t", "p", null, "player", null),
            new Membership("mq", "t2", "q", null, "player", null),
            new Membership("mu", "t", null, "u", "player", null));
    private static final Map<String, MemberRecord> MEMBERS = Map.of("c", COACH, "h", HELPER, "p", PLAYER, "q", PLAYER2);
    private static final Map<String, AccountName> ACCOUNTS = Map.of("u", new AccountName("Uli", "Konto"));

    private static MemberRecord member(String id, String first, String last, String city) {
        return new MemberRecord(id, first, last, "Gasse 1", "8010", city, "", "", "", "", null, "", "", "", "", "",
                true, new MemberPrivate("1234", "AT00", Instant.parse("1980-05-04T00:00:00Z"), null));
    }

    private static List<Person> people() {
        return PraeCalculator.eligiblePeople(MEMBERSHIPS, MEMBERS::get, ACCOUNTS);
    }

    private static Instant at(String local) {
        return LocalDateTime.parse(local).atZone(CLUB_ZONE).toInstant();
    }

    private static ClubEvent event(String id, String kind, String title, String start, String end, String city,
                                   String country) {
        return new ClubEvent(id, kind, title, "", "", "", "", city, country, at(start), at(end), "", "", null, null,
                null, List.of(), "");
    }

    private static Attendance attended(String event, String membership, Integer amount) {
        return new Attendance(event + membership, event, membership, true,
                amount == null ? null : BigDecimal.valueOf(amount));
    }

    private static String sheet(byte[] xlsx) throws IOException {
        try (ZipInputStream zip = new ZipInputStream(new ByteArrayInputStream(xlsx))) {
            for (ZipEntry e = zip.getNextEntry(); e != null; e = zip.getNextEntry()) {
                if (e.getName().equals("xl/worksheets/sheet1.xml")) {
                    return new String(zip.readAllBytes(), StandardCharsets.UTF_8);
                }
            }
        }
        throw new AssertionError("no sheet1.xml");
    }

    private static List<String> entryNames(byte[] zipBytes) throws IOException {
        List<String> names = new ArrayList<>();
        try (ZipInputStream zip = new ZipInputStream(new ByteArrayInputStream(zipBytes))) {
            for (ZipEntry e = zip.getNextEntry(); e != null; e = zip.getNextEntry()) {
                names.add(e.getName());
            }
        }
        return names;
    }

    private static void assertCell(String xml, String ref, String expected) {
        assertTrue(xml.contains(expected), ref + " should hold " + expected);
    }

    // ---------------------------------------------------------------- KostZ

    @Test
    void monthKostZSumsTrainingsPerPersonAndSkipsTournaments() {
        List<ClubEvent> events = List.of(
                event("t1", "training", "Torball", "2026-03-03T18:00", "2026-03-03T20:00", "", ""),
                event("t2", "training", "Torball", "2026-03-10T18:00", "2026-03-10T20:00", "", ""),
                event("t3", "training", "Showdown", "2026-03-20T18:00", "2026-03-20T20:00", "", ""),
                event("t4", "training", "Torball", "2026-04-01T18:00", "2026-04-01T20:00", "", ""),
                event("x", "tournament", "Cup", "2026-03-15T09:00", "2026-03-15T18:00", "", ""));
        List<Attendance> attendances = List.of(attended("t1", "mc", 40), attended("t2", "mc2", 50),
                attended("t3", "mh", 30), attended("t3", "mp", 90), attended("t4", "mc", 70), attended("x", "mc", 99),
                new Attendance("no", "t2", "mh", false, BigDecimal.TEN));

        KostZ kostZ = KostZ.month(3, 2026, people(), events, attendances);

        assertEquals("Torball, Showdown", kostZ.betrifft());
        assertEquals("Graz", kostZ.ort());
        assertEquals(LocalDate.of(2026, 3, 3), kostZ.start());
        assertEquals(LocalDate.of(2026, 3, 20), kostZ.end());
        assertEquals(3, kostZ.dayCount());
        assertEquals(List.of("Albrecht", "Muster"), kostZ.people().stream().map(p -> p.person().lastName()).toList());
        assertEquals(30, kostZ.people().get(0).amount());
        assertEquals(90, kostZ.people().get(1).amount(), "coach and assistant memberships are one person");
        assertEquals(120, kostZ.total());
    }

    @Test
    void monthWithoutTrainingsFallsBackToTheCalendarMonth() {
        KostZ kostZ = KostZ.month(2, 2028, people(), List.of(), List.of());
        assertEquals(LocalDate.of(2028, 2, 1), kostZ.start());
        assertEquals(LocalDate.of(2028, 2, 29), kostZ.end());
        assertEquals(0, kostZ.dayCount());
        assertEquals("", kostZ.betrifft());
    }

    @Test
    void tournamentKostZUsesItsOwnPlaceAndDays() {
        ClubEvent cup = event("x", "tournament", "Cup", "2026-05-29T09:00", "2026-05-31T18:00", "Prag", "Tschechien");
        KostZ kostZ = KostZ.tournament(cup, people(), List.of(attended("x", "mc", 120), attended("x", "mh", null)));
        assertEquals("Cup", kostZ.betrifft());
        assertEquals("Prag, Tschechien", kostZ.ort());
        assertEquals(3, kostZ.dayCount());
        assertEquals(1, kostZ.personCount());

        ClubEvent home = event("y", "tournament", "Heim", "2026-05-29T09:00", "2026-05-29T18:00", "", "");
        assertNull(KostZ.tournament(home, people(), List.of()).ort(), "no city leaves H3 blank");
    }

    @Test
    void kostZFillsTheAppsCells() throws IOException {
        KostZ kostZ = new KostZ("Cup & Co", "Graz", LocalDate.of(2026, 3, 3), LocalDate.of(2026, 3, 20), 3,
                List.of(new KostZ.PersonAmount(people().get(0), 45.5)));
        String xml = sheet(kostZ.xlsx());
        assertCell(xml, "C3", "<c r=\"C3\" s=\"70\" t=\"inlineStr\"><is><t>Cup &amp; Co</t></is></c>");
        assertCell(xml, "H3", "<c r=\"H3\" s=\"70\" t=\"inlineStr\"><is><t>Graz</t></is></c>");
        assertCell(xml, "D5", "<t>03.03.2026</t>");
        assertCell(xml, "G5", "<t>20.03.2026</t>");
        assertCell(xml, "I5", "<c r=\"I5\" s=\"36\"><v>3.0</v></c>");
        assertCell(xml, "E7", "<c r=\"E7\" s=\"37\"><v>1.0</v></c>");
        assertCell(xml, "I15", "<c r=\"I15\" s=\"39\"><v>45.5</v></c>");
        assertCell(xml, "I26", "<f>IF(SUM(I10:I25)&gt;0,SUM(I10:I25),\"\")</f>");
    }

    @Test
    void zeroTotalLeavesTheHonorariaCellBlank() throws IOException {
        KostZ kostZ = new KostZ("Torball", null, LocalDate.of(2026, 3, 1), LocalDate.of(2026, 3, 31), 0, List.of());
        String xml = sheet(kostZ.xlsx());
        assertCell(xml, "I15", "<c r=\"I15\" s=\"39\"/>");
        assertCell(xml, "H3", "<c r=\"H3\" s=\"70\"/>");
    }

    // ------------------------------------------------------ Teilnehmerliste

    @Test
    void tournamentParticipantsAreSplitByRoleSortedAndDeduplicated() {
        ClubEvent cup = event("x", "tournament", "Cup", "2026-05-29T09:00", "2026-05-30T18:00", "Linz", "Österreich");
        List<Attendance> attendances = List.of(attended("x", "mp", null), attended("x", "mu", null),
                attended("x", "mq", null), attended("x", "mc", 60), attended("x", "mc2", null),
                attended("x", "mh", null), new Attendance("n", "x", "mh", false, null));

        Teilnehmerliste.Pair pair = Teilnehmerliste.forTournament(cup, attendances, MEMBERSHIPS, MEMBERS, ACCOUNTS);

        assertEquals(List.of("Berger Anna", "Uli Konto", "Zach Zoe"),
                pair.sportler().rows().stream().map(Teilnehmerliste.Row::name).toList());
        assertEquals(List.of("Wien", ""), List.of(pair.sportler().rows().get(2).wohnort(),
                pair.sportler().rows().get(1).wohnort()));
        assertEquals(List.of("Albrecht Bernd", "Muster Erika"),
                pair.helfer().rows().stream().map(Teilnehmerliste.Row::name).toList());
        assertEquals("Linz", pair.sportler().ort());
        assertEquals(2, pair.sportler().dayCount());
    }

    @Test
    void teilnehmerlisteFillsTheTemplateAndCountsBeyondItsRows() throws IOException {
        List<Teilnehmerliste.Row> rows = new ArrayList<>();
        for (int i = 1; i <= 17; i++) {
            rows.add(new Teilnehmerliste.Row("Person " + i, i == 1 ? "Graz" : "", "P", "" + i));
        }
        Teilnehmerliste list = new Teilnehmerliste("Cup", "Prag, Tschechien", LocalDate.of(2026, 5, 29),
                LocalDate.of(2026, 5, 31), rows);
        String xml = sheet(list.xlsx());
        assertTrue(list.overflows());
        assertCell(xml, "C3", "<c r=\"C3\" s=\"64\" t=\"inlineStr\"><is><t>Cup</t></is></c>");
        assertCell(xml, "H3", "<t>Prag, Tschechien</t>");
        assertCell(xml, "D5", "<t>29.05.2026</t>");
        assertCell(xml, "F5", "<t>31.05.2026</t>");
        assertCell(xml, "H5", "<c r=\"H5\" s=\"30\"><v>3</v></c>");
        assertCell(xml, "D7", "<c r=\"D7\" s=\"31\"><v>17</v></c>");
        assertCell(xml, "B10", "<c r=\"B10\" s=\"65\" t=\"inlineStr\"><is><t>Person 1</t></is></c>");
        assertCell(xml, "D10", "<t>Graz</t>");
        assertCell(xml, "F10", "<c r=\"F10\" s=\"32\"><v>3</v></c>");
        assertCell(xml, "B24", "<t>Person 15</t>");
        assertFalse(xml.contains("Person 16"), "only 15 rows fit the form");
    }

    // ------------------------------------------------------ Sammelabrechnung

    @Test
    void tournamentBundleHoldsTheChosenPartsInTheAppsOrder() throws IOException {
        ClubEvent cup = event("x", "tournament", "Cup", "2026-05-29T09:00", "2026-05-30T18:00", "Linz", "");
        List<Attendance> attendances = List.of(attended("x", "mc", 60), attended("x", "mh", 40),
                attended("x", "mp", null));
        List<Person> people = people();
        List<PraeForm> prae = new ArrayList<>();
        people.forEach(p -> prae.addAll(PraeCalculator.tournamentForms(p, cup, attendances)));
        Reports.Tournament report = new Reports.Tournament(cup, KostZ.tournament(cup, people, attendances), prae,
                Teilnehmerliste.forTournament(cup, attendances, MEMBERSHIPS, MEMBERS, ACCOUNTS));

        assertEquals(List.of("KostZ.xlsx", "PRAE_Albrecht_Bernd.xlsx", "PRAE-Darstellung_Albrecht_Bernd.xlsx",
                        "PRAE_Muster_Erika.xlsx", "PRAE-Darstellung_Muster_Erika.xlsx",
                        "TeilnehmerInnenliste-Sportler.xlsx", "TeilnehmerInnenliste-Helfer.xlsx"),
                List.copyOf(report.sammelabrechnung(Reports.Selection.ALL).keySet()));

        String muster = people.stream().filter(p -> p.lastName().equals("Muster")).findFirst().orElseThrow().id();
        var chosen = report.sammelabrechnung(new Reports.Selection(false, Set.of(muster), false, true));
        assertEquals(List.of("PRAE_Muster_Erika.xlsx", "PRAE-Darstellung_Muster_Erika.xlsx",
                "TeilnehmerInnenliste-Helfer.xlsx"), List.copyOf(chosen.keySet()));
        assertEquals(List.copyOf(chosen.keySet()),
                entryNames(it.a11y.blindensport.webui.xlsx.XlsxPatch.zip(chosen)));
    }

    @Test
    void monthBundleNamesFormsByTraining() {
        List<ClubEvent> events = List.of(
                event("t1", "training", "Torball", "2026-03-03T18:00", "2026-03-03T20:00", "", ""),
                event("t2", "training", "Showdown", "2026-03-04T18:00", "2026-03-04T20:00", "", ""));
        List<Attendance> attendances = List.of(attended("t1", "mc", 40), attended("t2", "mc", 30));
        List<PraeForm> prae = new ArrayList<>();
        people().forEach(p -> prae.addAll(PraeCalculator.monthForms(p, 3, 2026, events, attendances)));
        Reports.Month report = new Reports.Month(3, 2026, KostZ.month(3, 2026, people(), events, attendances), prae);

        assertEquals("03-2026", report.label());
        assertEquals("März 2026", report.title());
        assertEquals(List.of("KostZ.xlsx", "PRAE_Muster_Erika_Torball.xlsx", "PRAE-Darstellung_Muster_Erika_Torball.xlsx",
                        "PRAE_Muster_Erika_Showdown.xlsx", "PRAE-Darstellung_Muster_Erika_Showdown.xlsx"),
                List.copyOf(report.sammelabrechnung(Reports.Selection.ALL).keySet()));
        assertTrue(new Reports.Selection(false, Set.of(), true, true).isEmpty(false),
                "a month has no TeilnehmerInnenliste, so this selects nothing");
        assertFalse(new Reports.Selection(false, Set.of(), true, false).isEmpty(true));
    }

    @Test
    void placesAppendOnlyForeignCountries() {
        assertEquals("Linz", Places.withForeignCountry("Linz", "Österreich"));
        assertEquals("Linz", Places.withForeignCountry("Linz", " "));
        assertEquals("Prag, Tschechien", Places.withForeignCountry("Prag", "Tschechien"));
        assertEquals("Tschechien", Places.withForeignCountry("", "Tschechien"));
    }

    static boolean appResourcesAvailable() {
        return Files.isDirectory(APP_RESOURCES);
    }

    /** The Docker build only sees webui/, hence a copy; it must not drift from the app's. */
    @Test
    @EnabledIf("appResourcesAvailable")
    void templatesAreTheAppsTemplates() throws IOException {
        Map<String, String> copies = new HashMap<>(Map.of(
                "KostZ_Kostenzusammenstellung.xlsx", KostZ.TEMPLATE,
                "TN_TeilnehmerInnenliste.xlsx", Teilnehmerliste.TEMPLATE));
        for (var entry : copies.entrySet()) {
            try (var copy = getClass().getClassLoader().getResourceAsStream(entry.getValue())) {
                assertArrayEquals(Files.readAllBytes(APP_RESOURCES.resolve(entry.getKey())), copy.readAllBytes(),
                        entry.getKey());
            }
        }
    }
}
