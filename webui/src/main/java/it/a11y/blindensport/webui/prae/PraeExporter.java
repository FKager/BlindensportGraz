package it.a11y.blindensport.webui.prae;

import it.a11y.blindensport.webui.xlsx.XlsxPatch;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.UnaryOperator;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static it.a11y.blindensport.webui.members.Dates.CLUB_ZONE;

/**
 * Fills the official PRAE forms — port of PraeExporter in the app's
 * PraeExport.swift, using the same two templates (src/main/resources/prae,
 * copies of BlindensportGraz/Resources). The exported form must stay exactly
 * like the template: ticks go only into the form controls, never into labels.
 */
public final class PraeExporter {
    private static final String CHECKED_ATTRIBUTE = "checked=\"Checked\"";
    private static final int MAX_ENTRY_ROWS = 21;
    private static final int FIRST_ENTRY_ROW = 8;
    private static final DateTimeFormatter DAY = DateTimeFormatter.ofPattern("dd.MM.uuuu");

    private PraeExporter() {
    }

    /**
     * A checkbox of the form; the values are read from the template, see FormCheckbox in the app. {@code label}
     * is for readers of this code only: nothing is written for it, the NVDA add-on names a box from the cells.
     */
    private record Checkbox(String vmlShapeId, int drawingShapeId, int ctrlProp, String label) {
        static Checkbox named(int name, int drawingShapeId, int ctrlProp, String label) {
            return new Checkbox("Kontrollkästchen_x0020_" + name, drawingShapeId, ctrlProp, label);
        }

        String ctrlPropPath() {
            return "xl/ctrlProps/ctrlProp" + ctrlProp + ".xml";
        }
    }

    private static final Checkbox UEBUNGSLEITER = Checkbox.named(17, 1041, 7, "Übungsleiter:in");
    private static final Checkbox TRAINER = Checkbox.named(13, 1037, 3, "Trainer:in");
    private static final Checkbox NEBENBERUF_JA = Checkbox.named(22, 1046, 10, "Ja (Nebenberuf)");
    private static final Checkbox EINFACHBEZUG_JA = Checkbox.named(24, 1048, 12, "Ja (Einfachbezug)");
    private static final Checkbox UEBERWEISUNG = Checkbox.named(27, 1051, 15, "Überweisung mittels");
    private static final Checkbox RICHTIGKEITSVERMERK = new Checkbox("_x0000_s1052", 1052, 16, "Richtigkeitsvermerk");

    /** The main signed form. Trainings tick Übungsleiter:in, tournaments Trainer:in; both tick the usual declarations. */
    public static byte[] mainForm(PraeForm form) {
        List<Checkbox> checked = form.tournament() ? List.of(TRAINER, NEBENBERUF_JA, EINFACHBEZUG_JA, UEBERWEISUNG, RICHTIGKEITSVERMERK)
                : List.of(UEBUNGSLEITER, NEBENBERUF_JA, EINFACHBEZUG_JA, UEBERWEISUNG, RICHTIGKEITSVERMERK);
        PraeForm.Person person = form.person();
        var member = person.member();
        var privateData = member == null ? null : member.privateData();
        return XlsxPatch.fillTemplate("prae/PRAE_Formular.xlsx", entryPatches(checked), xml -> {
            String p = XlsxPatch.setText(xml, "D4", person.formName());
            p = XlsxPatch.setText(p, "D5", privateData == null ? "" : privateData.svnr());
            p = XlsxPatch.setText(p, "D7", person.address());
            if (privateData != null && privateData.birthDate() != null) {
                p = XlsxPatch.setText(p, "L5", day(privateData.birthDate()));
            }
            if (privateData != null && !privateData.iban().isEmpty()) {
                p = XlsxPatch.setText(p, "D33", privateData.iban());
            }
            p = XlsxPatch.setText(p, "B11", form.monthName());
            p = XlsxPatch.setText(p, "K11", String.valueOf(form.year()));
            p = XlsxPatch.setText(p, "T11", form.purpose());
            for (PraeForm.DayEntry entry : form.entries()) {
                String ref = dayGridAmountRef(entry.day());
                if (ref != null) {
                    p = XlsxPatch.setNumber(p, ref, entry.amount());
                }
            }
            double total = form.total();
            p = XlsxPatch.setFormulaCachedValue(p, "L16", total);
            if (total > 0) {
                p = XlsxPatch.setText(p, "B18", GermanNumberWords.euroAmount(total));
            }
            return p;
        });
    }

    /**
     * The Darstellung der Verwendungszwecke appendix. A5 "Monat und Jahr:" is in the template, as in
     * Sport Austria's original; C5 gets the month and year, for tournaments too.
     */
    public static byte[] darstellung(PraeForm form, String vereinName) {
        String value = form.monthLabel();
        PraeForm.Person person = form.person();
        var birthDate = person.member() == null ? null : person.member().privateData().birthDate();
        return XlsxPatch.fillTemplate("prae/PRAE_Darstellung_Vorlage.xlsx", Map.of(), xml -> {
            String p = XlsxPatch.setText(xml, "C2", vereinName);
            p = XlsxPatch.setText(p, "C3", person.formName());
            if (birthDate != null) {
                p = XlsxPatch.setText(p, "C4", day(birthDate));
            }
            p = XlsxPatch.setText(p, "C5", value);
            List<PraeForm.DayEntry> entries = form.entries();
            for (int i = 0; i < Math.min(entries.size(), MAX_ENTRY_ROWS); i++) {
                int row = FIRST_ENTRY_ROW + i;
                p = XlsxPatch.setNumber(p, "A" + row, entries.get(i).day());
                p = XlsxPatch.setNumber(p, "B" + row, entries.get(i).amount());
                p = XlsxPatch.setText(p, "C" + row, entries.get(i).purpose());
            }
            return p;
        });
    }

    /** File names as in the app's Sammelabrechnung: "PRAE_Nachname_Vorname_Titel.xlsx". */
    public static String fileName(PraeForm form, String prefix) {
        PraeForm.Person person = form.person();
        List<String> names = new ArrayList<>();
        if (!person.lastName().isEmpty()) {
            names.add(person.lastName());
        }
        if (!person.firstName().isEmpty()) {
            names.add(person.firstName());
        }
        String name = names.isEmpty() ? person.displayName() : String.join("_", names);
        String detail = !form.tournament() ? form.purpose()
                : form.spansSeveralMonths() ? String.format("%02d-%d", form.month(), form.year()) : "";
        return prefix + "_" + sanitize(name) + (detail.isEmpty() ? "" : "_" + sanitize(detail)) + ".xlsx";
    }

    private static String sanitize(String raw) {
        return raw.replace("/", "-").replace("\\", "-");
    }

    private static String day(java.time.Instant instant) {
        return DAY.format(LocalDate.ofInstant(instant, CLUB_ZONE));
    }

    /**
     * Amount cell of a day in the "Einsatztage" grid: rows 12–15, ten days per
     * row, each day's label followed by a merged two-column amount cell.
     */
    static String dayGridAmountRef(int day) {
        if (day < 1 || day > 31) {
            return null;
        }
        int row;
        int indexInRow;
        if (day <= 10) {
            row = 12;
            indexInRow = day - 1;
        } else if (day <= 20) {
            row = 13;
            indexInRow = day - 11;
        } else if (day <= 30) {
            row = 14;
            indexInRow = day - 21;
        } else {
            row = 15;
            indexInRow = 0;
        }
        return columnLetter(2 + indexInRow * 3 + 1) + row;
    }

    private static String columnLetter(int column) {
        StringBuilder letters = new StringBuilder();
        for (int n = column; n > 0; n = (n - 1) / 26) {
            letters.insert(0, (char) ('A' + (n - 1) % 26));
        }
        return letters.toString();
    }

    /** Patches for everything but sheet1.xml: tick {@code boxes}. */
    private static Map<String, UnaryOperator<String>> entryPatches(List<Checkbox> boxes) {
        Map<String, UnaryOperator<String>> patches = new HashMap<>();
        patches.put("xl/drawings/vmlDrawing1.vml", vml -> {
            String ticked = vml;
            for (Checkbox box : boxes) {
                ticked = checkFormCheckbox(ticked, box.vmlShapeId());
            }
            return ticked;
        });
        for (Checkbox box : boxes) {
            patches.put(box.ctrlPropPath(), ctrlProp -> ctrlProp.replace("objectType=\"CheckBox\"",
                    "objectType=\"CheckBox\" " + CHECKED_ATTRIBUTE));
        }
        return patches;
    }

    /**
     * Ticks one control. Scoped to its own shape block first: every shape's
     * {@code <x:NoThreeD/>} is identical, so an unscoped search would tick the
     * first box in the file.
     */
    private static String checkFormCheckbox(String vml, String shapeId) {
        Matcher shape = Pattern.compile("<v:shape id=\"" + Pattern.quote(shapeId) + "\".*?</v:shape>", Pattern.DOTALL)
                .matcher(vml);
        if (!shape.find() || !shape.group().contains("<x:NoThreeD/>")) {
            return vml;
        }
        String block = shape.group().replaceFirst("<x:NoThreeD/>", "<x:Checked>1</x:Checked><x:NoThreeD/>");
        return vml.substring(0, shape.start()) + block + vml.substring(shape.end());
    }
}
