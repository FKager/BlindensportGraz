package it.a11y.blindensport.webui.prae;

import it.a11y.blindensport.webui.members.MemberRecord;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * One PRAE form: one person, one calendar month, one training name or one
 * tournament. Corresponds to the app's PraeMonthSummary / PraeTournamentSummary.
 *
 * @param purpose            T11 "Verwendungszweck": the training or tournament title
 * @param personDayTotals    the person's amount per day across all their trainings that
 *                           month, since the legal caps apply to the person, not one form
 * @param spansSeveralMonths a tournament running into the next month
 */
public record PraeForm(Person person, boolean tournament, int month, int year, String purpose, List<DayEntry> entries,
                       Map<Integer, Double> personDayTotals, boolean spansSeveralMonths) {
    private static final Locale AUSTRIA = Locale.forLanguageTag("de-AT");

    /**
     * A helper across all their teams. {@code member} (with protected fields)
     * is null for someone known only by an app account, whose form has no
     * address, as in the app.
     */
    public record Person(String id, String displayName, String lastName, String firstName, List<String> membershipIds,
                         MemberRecord member) {
        /** "Nachname, Vorname", the form's convention. */
        public String formName() {
            String last = lastName.trim();
            String first = firstName.trim();
            return last.isEmpty() || first.isEmpty() ? displayName : last + ", " + first;
        }

        /**
         * Street, zip and city; the country only when it is set and not Österreich
         * (Member.addressWithForeignCountry in the app).
         */
        public String address() {
            if (member == null) {
                return "";
            }
            String zipCity = String.join(" ", present(member.zip(), member.city()));
            String country = member.country() == null ? "" : member.country().strip();
            boolean foreign = !country.isEmpty() && !country.equals("Österreich");
            return String.join(", ", present(member.street(), zipCity, foreign ? country : ""));
        }

        private static List<String> present(String... parts) {
            return List.of(parts).stream().filter(p -> !p.isBlank()).toList();
        }
    }

    public record DayEntry(int day, double amount, String purpose) {
    }

    public double total() {
        return entries.stream().mapToDouble(DayEntry::amount).sum();
    }

    /** The person's total that month; a tournament's form stands on its own, as in the app. */
    public double personTotal() {
        return personDayTotals.isEmpty() ? total()
                : personDayTotals.values().stream().mapToDouble(Double::doubleValue).sum();
    }

    /** Readable warnings about the legal caps. They are flagged, never enforced. */
    public List<String> capWarnings() {
        List<String> warnings = new ArrayList<>();
        if (personTotal() > PraeCalculator.MONTHLY_CAP) {
            warnings.add("Monatsgrenze von 720 € überschritten: " + personTotal() + " €");
        }
        for (DayEntry entry : entries) {
            if (personDayTotals.getOrDefault(entry.day(), entry.amount()) > PraeCalculator.DAILY_CAP) {
                warnings.add("Tagesgrenze von 120 € am " + entry.day() + ". überschritten");
            }
        }
        return warnings;
    }

    /** "August". */
    String monthName() {
        return DateTimeFormatter.ofPattern("LLLL", AUSTRIA).format(LocalDate.of(year, month, 1));
    }

    /** "August 2026". */
    String monthLabel() {
        return DateTimeFormatter.ofPattern("LLLL uuuu", AUSTRIA).format(LocalDate.of(year, month, 1));
    }
}
