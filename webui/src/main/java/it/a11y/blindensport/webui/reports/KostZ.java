package it.a11y.blindensport.webui.reports;

import it.a11y.blindensport.webui.club.ClubModels.Attendance;
import it.a11y.blindensport.webui.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webui.prae.PraeForm.Person;
import it.a11y.blindensport.webui.xlsx.XlsxPatch;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import static it.a11y.blindensport.webui.members.Dates.CLUB_ZONE;

/**
 * Sport Austria's "KostZ" (Kostenzusammenstellung) — port of the app's
 * KostZCalculation.swift and KostZExport.swift. Only the line "HONORARE /
 * VERGÜTUNGEN" (I15), the period, the number of people, BETRIFFT and ORT are
 * filled; every other cost line and all BEILAGE numbers stay for the
 * treasurer. The I26 SUM formula is left as it is and recalculates on open.
 *
 * <p>A month's KostZ covers every training of the month (tournaments file
 * their own, so nothing is counted twice).
 *
 * @param betrifft C3: the training names of the month, comma-joined, or the tournament's title
 * @param ort      H3: "Graz" for trainings, the tournament's city; null leaves it blank
 * @param dayCount I5: number of trainings in the month, or the tournament's days
 * @param people   helpers with an amount above 0, by last name
 */
public record KostZ(String betrifft, String ort, LocalDate start, LocalDate end, int dayCount,
                    List<PersonAmount> people) {
    static final String TEMPLATE = "reports/KostZ_Kostenzusammenstellung.xlsx";
    private static final DateTimeFormatter DAY = DateTimeFormatter.ofPattern("dd.MM.uuuu");

    /** One helper's summed honorarium. */
    public record PersonAmount(Person person, double amount) {
    }

    public double total() {
        return people.stream().mapToDouble(PersonAmount::amount).sum();
    }

    public int personCount() {
        return people.size();
    }

    /**
     * Every training in the month: amounts from attended rows with a PRAE
     * amount; period and day count from the trainings held, whether or not
     * anyone was paid. A month without trainings falls back to the calendar
     * month with 0 days, as in the app.
     */
    public static KostZ month(int month, int year, List<Person> eligible, List<ClubEvent> events,
                              List<Attendance> attendances) {
        List<ClubEvent> trainings = events.stream()
                .filter(e -> "training".equals(e.kind()))
                .filter(e -> {
                    LocalDate date = LocalDate.ofInstant(e.startDate(), CLUB_ZONE);
                    return date.getMonthValue() == month && date.getYear() == year;
                })
                .sorted(Comparator.comparing(ClubEvent::startDate))
                .toList();
        Set<String> trainingIds = new java.util.HashSet<>();
        Set<String> names = new LinkedHashSet<>();
        for (ClubEvent training : trainings) {
            trainingIds.add(training.id());
            names.add(training.title());
        }
        List<Attendance> relevant = attendances.stream().filter(a -> trainingIds.contains(a.eventId())).toList();

        LocalDate firstOfMonth = LocalDate.of(year, month, 1);
        LocalDate start = trainings.isEmpty() ? firstOfMonth
                : LocalDate.ofInstant(trainings.get(0).startDate(), CLUB_ZONE);
        LocalDate end = trainings.isEmpty() ? firstOfMonth.withDayOfMonth(firstOfMonth.lengthOfMonth())
                : LocalDate.ofInstant(trainings.get(trainings.size() - 1).startDate(), CLUB_ZONE);
        return new KostZ(String.join(", ", names), "Graz", start, end, trainings.size(),
                amounts(eligible, relevant));
    }

    /** One tournament, from its own attendance rows. */
    public static KostZ tournament(ClubEvent tournament, List<Person> eligible, List<Attendance> attendances) {
        String ort = tournament.city().isBlank() ? null
                : Places.withForeignCountry(tournament.city(), tournament.country());
        List<Attendance> own = attendances.stream().filter(a -> tournament.id().equals(a.eventId())).toList();
        return new KostZ(tournament.title(), ort, LocalDate.ofInstant(tournament.startDate(), CLUB_ZONE),
                LocalDate.ofInstant(tournament.endDate(), CLUB_ZONE), tournament.dayCount(), amounts(eligible, own));
    }

    private static List<PersonAmount> amounts(List<Person> eligible, List<Attendance> attendances) {
        Map<String, Person> byMembership = new HashMap<>();
        eligible.forEach(p -> p.membershipIds().forEach(id -> byMembership.put(id, p)));
        Map<String, Double> sums = new HashMap<>();
        for (Attendance a : attendances) {
            Person person = byMembership.get(a.membershipId());
            if (a.attended() && a.praeAmount() != null && person != null) {
                sums.merge(person.id(), a.praeAmount().doubleValue(), Double::sum);
            }
        }
        List<PersonAmount> result = new ArrayList<>();
        for (Person person : eligible) {
            double amount = sums.getOrDefault(person.id(), 0.0);
            if (amount > 0) {
                result.add(new PersonAmount(person, amount));
            }
        }
        return result;
    }

    /** The filled template. */
    public byte[] xlsx() {
        return XlsxPatch.fillTemplate(TEMPLATE, Map.of(), xml -> {
            String p = XlsxPatch.setText(xml, "C3", betrifft);
            if (ort != null) {
                p = XlsxPatch.setText(p, "H3", ort);
            }
            p = XlsxPatch.setText(p, "D5", DAY.format(start));
            p = XlsxPatch.setText(p, "G5", DAY.format(end));
            p = XlsxPatch.setNumber(p, "I5", (double) dayCount);
            p = XlsxPatch.setNumber(p, "E7", (double) personCount());
            if (total() > 0) {
                p = XlsxPatch.setNumber(p, "I15", total());
            }
            return p;
        });
    }
}
