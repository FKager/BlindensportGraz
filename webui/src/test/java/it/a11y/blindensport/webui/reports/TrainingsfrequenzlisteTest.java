package it.a11y.blindensport.webui.reports;

import it.a11y.blindensport.webui.club.ClubModels.Attendance;
import it.a11y.blindensport.webui.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webui.club.ClubModels.Membership;
import it.a11y.blindensport.webui.club.ClubModels.Team;
import it.a11y.blindensport.webui.members.MemberRecord;
import it.a11y.blindensport.webui.prae.PraeCalculator.AccountName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIf;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

import static it.a11y.blindensport.webui.members.Dates.CLUB_ZONE;
import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** Port of the app's TrainingsfrequenzlisteCalculationTests plus the file's cells. */
class TrainingsfrequenzlisteTest {
    private static final List<Team> TEAMS = List.of(new Team("damen", "Torball Damen", "Torball", ""),
            new Team("herren", "Torball Herren", "Torball", ""), new Team("fb", "Blindenfußball", "Fußball", ""));
    private static final List<Membership> MEMBERSHIPS = List.of(
            new Membership("m-anna", "damen", "anna", null, "player", null),
            new Membership("m-erika", "damen", "erika", null, "coach", null),
            new Membership("m-anna2", "herren", "anna", null, "player", null),
            new Membership("m-bernd", "herren", "bernd", null, "assistant", null),
            new Membership("m-uli", "herren", null, "uli", "player", null),
            new Membership("m-fb", "fb", "fritz", null, "player", null));
    private static final Map<String, MemberRecord> MEMBERS = Map.of(
            "anna", member("anna", "Anna", "Berger", "f"), "erika", member("erika", "Erika", "Muster", "f"),
            "bernd", member("bernd", "Bernd", "Albrecht", "m"), "fritz", member("fritz", "Fritz", "Fuß", "m"));
    private static final Map<String, AccountName> ACCOUNTS = Map.of("uli", new AccountName("Uli", "Zach"));

    private static MemberRecord member(String id, String first, String last, String gender) {
        return new MemberRecord(id, first, last, "", "", "", "", "", "", "", null, "", gender, "", "", "", true, null);
    }

    private static ClubEvent training(String id, String sport, String start, String title, String location,
                                      String... teams) {
        LocalDateTime begin = LocalDateTime.parse(start);
        return new ClubEvent(id, "training", title, sport, location, "", "", "", "",
                begin.atZone(CLUB_ZONE).toInstant(), begin.plusHours(2).atZone(CLUB_ZONE).toInstant(), "", "", null,
                null, null, List.of(teams), "");
    }

    private static Attendance present(String event, String membership) {
        return new Attendance(event + membership, event, membership, true, null);
    }

    private static final List<ClubEvent> EVENTS = List.of(
            training("t2", "Torball", "2026-03-10T17:30", "Torball Herren", "Halle B", "herren"),
            training("t1", "Torball", "2026-01-07T17:30", "Torball Training", "ODIUM", "damen"),
            training("t3", "Torball", "2026-07-01T17:30", "Sommer", "Halle C", "damen"),
            training("f1", "Fußball", "2026-02-01T10:00", "Fußball", "Platz", "fb"),
            new ClubEvent("x", "tournament", "Cup", "Torball", "", "", "", "", "",
                    LocalDateTime.parse("2026-02-01T10:00").atZone(CLUB_ZONE).toInstant(),
                    LocalDateTime.parse("2026-02-01T18:00").atZone(CLUB_ZONE).toInstant(), "", "", null, null, null,
                    List.of("damen"), ""));

    private static Trainingsfrequenzliste firstHalf() {
        List<Attendance> attendances = List.of(present("t1", "m-anna"), present("t1", "m-erika"),
                present("t2", "m-bernd"), present("t2", "m-uli"), new Attendance("no", "t2", "m-erika", false, null),
                present("t3", "m-anna"), present("x", "m-anna"));
        return Trainingsfrequenzliste.of("Torball", 1, 2026, EVENTS, attendances, TEAMS, MEMBERSHIPS, MEMBERS,
                ACCOUNTS);
    }

    @Test
    void periodSportAndRosterAreLikeTheApp() {
        Trainingsfrequenzliste list = firstHalf();
        assertEquals(List.of(LocalDate.of(2026, 1, 7), LocalDate.of(2026, 3, 10)), list.dates());
        assertEquals(List.of("Torball Damen", "Torball Herren"), list.teams());
        // players first, then helpers; each block by last name; Anna once although on both teams
        assertEquals(List.of("Berger", "Zach", "Albrecht (Helfer)", "Muster (Übungsleiterin)"),
                list.people().stream().map(Trainingsfrequenzliste.Person::lastNameWithRole).toList());
        assertEquals(2, list.present(LocalDate.of(2026, 1, 7))); // Anna + Erika
        assertEquals(2, list.present(LocalDate.of(2026, 3, 10))); // Bernd + Uli
        assertEquals("Torball Training", list.title());
        assertEquals("ODIUM", list.location());
        assertEquals(LocalTime.of(17, 30), list.startTime());
        assertEquals(LocalTime.of(19, 30), list.endTime());
        assertEquals("Torball_H1-2026", list.label());
        assertEquals(0, list.missingDates());
    }

    @Test
    void emptyPeriodFallsBackToTheSport() {
        Trainingsfrequenzliste list = Trainingsfrequenzliste.of("Torball", 2, 2025, EVENTS, List.of(), TEAMS,
                MEMBERSHIPS, MEMBERS, ACCOUNTS);
        assertTrue(list.dates().isEmpty());
        assertTrue(list.people().isEmpty());
        assertEquals("Torball", list.title());
        assertNull(list.location());
        assertNull(list.startTime());
    }

    @Test
    void sportsAreDistinctTrainingSports() {
        assertEquals(List.of("Fußball", "Torball"), Trainingsfrequenzliste.sports(EVENTS));
    }

    @Test
    void onlyTwentyFiveDatesFit() {
        List<ClubEvent> many = new ArrayList<>();
        for (int i = 0; i < 27; i++) {
            many.add(training("d" + i, "Torball", LocalDate.of(2026, 1, 1).plusDays(i) + "T17:30", "T", "", "damen"));
        }
        Trainingsfrequenzliste list = Trainingsfrequenzliste.of("Torball", 1, 2026, many, List.of(), TEAMS,
                MEMBERSHIPS, MEMBERS, ACCOUNTS);
        assertEquals(25, list.dates().size());
        assertEquals(2, list.missingDates());
    }

    @Test
    void excelNumbersMatchTheTemplate() {
        assertEquals(46029.0, Trainingsfrequenzliste.serial(LocalDate.of(2026, 1, 7)));
        assertEquals(0.7291666666666666, Trainingsfrequenzliste.timeFraction(LocalTime.of(17, 30)), 1e-12);
        assertEquals("D", Trainingsfrequenzliste.column(4));
        assertEquals("AB", Trainingsfrequenzliste.column(28));
    }

    @Test
    void fileReplacesTheExampleData() throws IOException {
        String xml = sheet(firstHalf().xlsx());
        assertEquals("Sektion Blindensport (GVSC)", cellText(xml, "D3"));
        assertEquals("Torball Training", cellText(xml, "P3"));
        assertEquals("ODIUM", cellText(xml, "Y3"));
        assertEquals("0.7291666666666666", cellValue(xml, "H4"));
        assertEquals("2026.0", cellValue(xml, "Y4"));
        assertEquals("46029.0", cellValue(xml, "D6"));
        assertEquals("46091.0", cellValue(xml, "E6"));
        assertTrue(isBlank(xml, "F6"), "unused date column is cleared");
        assertEquals("1.", cellText(xml, "A8"));
        assertEquals("Anna", cellText(xml, "B8"));
        assertEquals("Berger", cellText(xml, "C8"));
        assertEquals("j", cellText(xml, "D8"));
        assertEquals("n", cellText(xml, "E8"));
        assertEquals("Muster (Übungsleiterin)", cellText(xml, "C11"));
        assertTrue(isBlank(xml, "A12") && isBlank(xml, "C12") && isBlank(xml, "D12"), "unused rows are cleared");
        assertTrue(isBlank(xml, "F8"));
        assertTrue(xml.contains("COUNTIF(D8:D31,\"j\")"), "total formula stays");
        assertEquals("2.0", cellValue(xml, "D32"));
        assertEquals("0.0", cellValue(xml, "F32"));
        assertFalse(xml.contains("t=\"s\"><v>89</v>"), "no example 'j' from the template remains in the grid");
    }

    private static final Path APP_TEMPLATE = Path.of("../BlindensportGraz/Resources/Trainingsfrequenzliste_Vorlage.xlsx");

    static boolean appTemplateAvailable() {
        return Files.isRegularFile(APP_TEMPLATE);
    }

    @Test
    @EnabledIf("appTemplateAvailable")
    void templateMatchesTheApp() throws IOException {
        try (InputStream copy = getClass().getClassLoader().getResourceAsStream(Trainingsfrequenzliste.TEMPLATE)) {
            assertArrayEquals(Files.readAllBytes(APP_TEMPLATE), copy.readAllBytes(),
                    "webui template differs from the app's");
        }
    }

    // ---------------------------------------------------------- helpers

    private static String sheet(byte[] xlsx) throws IOException {
        try (ZipInputStream in = new ZipInputStream(new ByteArrayInputStream(xlsx))) {
            for (ZipEntry e = in.getNextEntry(); e != null; e = in.getNextEntry()) {
                if (e.getName().equals("xl/worksheets/sheet1.xml")) {
                    return new String(in.readAllBytes(), StandardCharsets.UTF_8);
                }
            }
        }
        throw new AssertionError("no sheet1.xml");
    }

    private static String cell(String xml, String ref) {
        Matcher m = Pattern.compile("<c r=\"" + ref + "\"[^>]*?(?:/>|>.*?</c>)", Pattern.DOTALL).matcher(xml);
        if (!m.find()) {
            throw new AssertionError("no cell " + ref);
        }
        return m.group();
    }

    private static String cellText(String xml, String ref) {
        Matcher m = Pattern.compile("<t>([^<]*)</t>").matcher(cell(xml, ref));
        return m.find() ? m.group(1) : null;
    }

    private static String cellValue(String xml, String ref) {
        Matcher m = Pattern.compile("<v>([^<]*)</v>").matcher(cell(xml, ref));
        return m.find() ? m.group(1) : null;
    }

    private static boolean isBlank(String xml, String ref) {
        return cell(xml, ref).endsWith("/>");
    }
}
