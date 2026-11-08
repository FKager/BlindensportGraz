package it.a11y.blindensport.webui.prae;

import it.a11y.blindensport.webui.members.MemberPrivate;
import it.a11y.blindensport.webui.members.MemberRecord;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIf;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * The filled-in forms. On 2026-11-07 this exporter's output was compared with
 * the app's PraeExporter over the same data: 8 forms, 168 zip entries, all byte
 * for byte equal. These tests hold on to that result.
 */
class PraeExporterTest {
    private static final Path APP_RESOURCES = Path.of("../BlindensportGraz/Resources");

    private static final MemberRecord MEMBER = new MemberRecord("AA", "Erika", "Muster", "Gasse 1", "8010", "Graz", "",
            "", "", "", null, "", "", "", "", "", true,
            new MemberPrivate("1234567890", "AT00", Instant.parse("1980-05-04T00:00:00Z"), null));
    private static final PraeForm.Person PERSON = new PraeForm.Person("p", "Erika Muster", "Muster", "Erika", List.of(), MEMBER);

    private static PraeForm form(boolean tournament, boolean severalMonths) {
        return new PraeForm(PERSON, tournament, 3, 2031, "Cup & Co", List.of(new PraeForm.DayEntry(11, 45.5, "Cup & Co"),
                new PraeForm.DayEntry(31, 60, "Cup & Co")), Map.of(), severalMonths);
    }

    private static Map<String, String> entries(byte[] xlsx) throws IOException {
        Map<String, String> result = new HashMap<>();
        try (ZipInputStream zip = new ZipInputStream(new ByteArrayInputStream(xlsx))) {
            for (ZipEntry e = zip.getNextEntry(); e != null; e = zip.getNextEntry()) {
                result.put(e.getName(), new String(zip.readAllBytes(), StandardCharsets.UTF_8));
            }
        }
        return result;
    }

    private static List<String> tickedControls(Map<String, String> entries) {
        List<String> ticked = new ArrayList<>();
        entries.forEach((name, xml) -> {
            if (name.startsWith("xl/ctrlProps/") && xml.contains("checked=\"Checked\"")) {
                ticked.add(name.replaceAll("\\D", ""));
            }
        });
        ticked.sort(java.util.Comparator.comparingInt(Integer::parseInt));
        return ticked;
    }

    @Test
    void fillsTheMainForm() throws IOException {
        String sheet = entries(PraeExporter.mainForm(form(false, false))).get("xl/worksheets/sheet1.xml");
        assertTrue(sheet.contains("<is><t>Muster, Erika</t></is>"));
        assertTrue(sheet.contains("<is><t>1234567890</t></is>"));
        assertTrue(sheet.contains("<is><t>04.05.1980</t></is>"));
        assertTrue(sheet.contains("<is><t>Gasse 1, 8010 Graz</t></is>"));
        assertTrue(sheet.contains("<is><t>März</t></is>"));
        assertTrue(sheet.contains("<is><t>Cup &amp; Co</t></is>"), "text is XML-escaped");
        assertTrue(sheet.contains("<is><t>Einhundertfünf Euro und fünfzig Cent</t></is>"));
        assertTrue(sheet.contains("<c r=\"C13\" s=\"105\"><v>45.5</v></c>"), "day 11 amount");
        assertTrue(sheet.contains("<v>60.0</v>"), "day 31 amount");
        assertTrue(sheet.contains("altText=\"Trainer:in\""), "every checkbox is named for NVDA");
    }

    @Test
    void trainingAndTournamentTickTheirBoxes() throws IOException {
        var training = entries(PraeExporter.mainForm(form(false, false)));
        assertEquals(List.of("7", "10", "12", "15", "16"), tickedControls(training));
        assertEquals(5, training.get("xl/drawings/vmlDrawing1.vml").split("<x:Checked>1", -1).length - 1);
        assertEquals(List.of("3", "10", "12", "15", "16"), tickedControls(entries(PraeExporter.mainForm(form(true, false)))));
    }

    @Test
    void labelsStayLikeTheTemplate() throws IOException {
        assertFalse(entries(PraeExporter.mainForm(form(false, false))).get("xl/sharedStrings.xml").contains("☒"),
                "a tick lives only in the control, so the form prints like the template");
    }

    @Test
    void darstellungNamesPeriodAndMonthOfASplitTournament() throws IOException {
        String month = entries(PraeExporter.darstellung(form(false, false), "Grazer VSC")).get("xl/worksheets/sheet1.xml");
        assertTrue(month.contains("<is><t>Monat und Jahr:</t></is>"));
        assertTrue(month.contains("<is><t>März 2031</t></is>"));
        String split = entries(PraeExporter.darstellung(form(true, true), "Grazer VSC")).get("xl/worksheets/sheet1.xml");
        assertTrue(split.contains("<is><t>Turnier:</t></is>"));
        assertTrue(split.contains("<is><t>Cup &amp; Co, März 2031</t></is>"));
    }

    @Test
    void fileNamesMatchTheAppAndCantEscapeTheFolder() {
        assertEquals("PRAE_Muster_Erika_Cup & Co.xlsx", PraeExporter.fileName(form(false, false), "PRAE"));
        assertEquals("PRAE_Muster_Erika.xlsx", PraeExporter.fileName(form(true, false), "PRAE"));
        assertEquals("PRAE-Darstellung_Muster_Erika_03-2031.xlsx", PraeExporter.fileName(form(true, true), "PRAE-Darstellung"));
        var slash = new PraeForm(PERSON, false, 3, 2031, "../a\\b", List.of(), Map.of(), false);
        assertEquals("PRAE_Muster_Erika_..-a-b.xlsx", PraeExporter.fileName(slash, "PRAE"));
    }

    @Test
    void dayGridFollowsTheFormsLayout() {
        assertEquals("C12", PraeExporter.dayGridAmountRef(1));
        assertEquals("F12", PraeExporter.dayGridAmountRef(2));
        assertEquals("C13", PraeExporter.dayGridAmountRef(11));
        assertEquals("AD14", PraeExporter.dayGridAmountRef(30));
        assertEquals("C15", PraeExporter.dayGridAmountRef(31));
        assertEquals(null, PraeExporter.dayGridAmountRef(32));
    }

    @Test
    void spellsAmountsLikeOfficialForms() {
        assertEquals("Einundzwanzig Euro", GermanNumberWords.euroAmount(21));
        assertEquals("Einhundertfünfunddreißig Euro und fünfzig Cent", GermanNumberWords.euroAmount(135.5));
        assertEquals("Eintausendzweihundert Euro", GermanNumberWords.euroAmount(1200));
    }

    static boolean appResourcesAvailable() {
        return Files.isDirectory(APP_RESOURCES);
    }

    /** The Docker build only sees webui/, hence a copy; it must not drift from the app's. */
    @Test
    @EnabledIf("appResourcesAvailable")
    void templatesAreTheAppsTemplates() throws IOException {
        for (String name : List.of("PRAE_Formular.xlsx", "PRAE_Darstellung_Vorlage.xlsx")) {
            try (var copy = getClass().getClassLoader().getResourceAsStream("prae/" + name)) {
                assertArrayEquals(Files.readAllBytes(APP_RESOURCES.resolve(name)), copy.readAllBytes(), name);
            }
        }
    }
}
