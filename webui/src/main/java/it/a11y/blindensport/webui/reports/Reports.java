package it.a11y.blindensport.webui.reports;

import it.a11y.blindensport.webui.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webui.prae.PraeForm;
import it.a11y.blindensport.webui.prae.PraeService;
import it.a11y.blindensport.webui.xlsx.XlsxPatch;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Set;

/**
 * The invoicing of one period, as the app's "Berichte" menus file it: a
 * month of trainings, or one tournament. Plain data, so the web UI and the
 * REST API produce the same files. Port of SammelabrechnungExport.swift for
 * the bundles.
 */
public final class Reports {
    private static final Locale AUSTRIA = Locale.forLanguageTag("de-AT");

    private Reports() {
    }

    /**
     * What goes into a Sammelabrechnung. Everything is chosen by default, as in the app.
     *
     * @param praePeople the people whose PRAE (Formular + Darstellung) to include, by
     *                   {@link PraeForm.Person#id()}; null for everyone
     * @param sportler   tournaments only: TeilnehmerInnenliste of the players
     * @param helfer     tournaments only: TeilnehmerInnenliste of the coaches and assistants
     */
    public record Selection(boolean kostZ, Set<String> praePeople, boolean sportler, boolean helfer) {
        public static final Selection ALL = new Selection(true, null, true, true);

        boolean includes(PraeForm form) {
            return praePeople == null || praePeople.contains(form.person().id());
        }

        public boolean isEmpty(boolean tournament) {
            boolean noPrae = praePeople != null && praePeople.isEmpty();
            return !kostZ && noPrae && (!tournament || (!sportler && !helfer));
        }
    }

    /** Every training of one calendar month. */
    public record Month(int month, int year, KostZ kostZ, List<PraeForm> prae) {
        /** "11-2026", as the app names a season's month files. */
        public String label() {
            return String.format("%02d-%d", month, year);
        }

        /** "November 2026". */
        public String title() {
            return DateTimeFormatter.ofPattern("LLLL uuuu", AUSTRIA).format(LocalDate.of(year, month, 1));
        }

        /** KostZ, then each chosen person's PRAE and Darstellung per training. */
        public LinkedHashMap<String, byte[]> sammelabrechnung(Selection selection) {
            LinkedHashMap<String, byte[]> files = new LinkedHashMap<>();
            if (selection.kostZ()) {
                files.put("KostZ.xlsx", kostZ.xlsx());
            }
            praeFiles(prae, selection).forEach((name, data) -> XlsxPatch.addUnique(files, name, data));
            return files;
        }
    }

    /** One tournament. */
    public record Tournament(ClubEvent event, KostZ kostZ, List<PraeForm> prae, Teilnehmerliste.Pair teilnehmer) {
        public String label() {
            return fileSafe(event.title());
        }

        /** KostZ, the chosen PRAE forms, then the two TeilnehmerInnenlisten — the app's order. */
        public LinkedHashMap<String, byte[]> sammelabrechnung(Selection selection) {
            LinkedHashMap<String, byte[]> files = new LinkedHashMap<>();
            if (selection.kostZ()) {
                files.put("KostZ.xlsx", kostZ.xlsx());
            }
            praeFiles(prae, selection).forEach((name, data) -> XlsxPatch.addUnique(files, name, data));
            if (selection.sportler()) {
                XlsxPatch.addUnique(files, "TeilnehmerInnenliste-Sportler.xlsx", teilnehmer.sportler().xlsx());
            }
            if (selection.helfer()) {
                XlsxPatch.addUnique(files, "TeilnehmerInnenliste-Helfer.xlsx", teilnehmer.helfer().xlsx());
            }
            return files;
        }
    }

    private static LinkedHashMap<String, byte[]> praeFiles(List<PraeForm> forms, Selection selection) {
        return PraeService.files(forms.stream().filter(selection::includes).toList());
    }

    /** One person's PRAE forms of the period. */
    public static List<PraeForm> formsOf(List<PraeForm> forms, String personId) {
        return forms.stream().filter(f -> f.person().id().equals(personId)).toList();
    }

    /** "/" and "\" can't be in a file name. */
    public static String fileSafe(String raw) {
        String safe = raw.replace("/", "-").replace("\\", "-").strip();
        return safe.isEmpty() ? "Turnier" : safe;
    }
}
