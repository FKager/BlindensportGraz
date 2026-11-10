package it.a11y.blindensport.webui.prae;

import it.a11y.blindensport.webui.club.ClubModels.Attendance;
import it.a11y.blindensport.webui.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webui.club.ClubModels.Membership;
import it.a11y.blindensport.webui.members.MemberRecord;
import it.a11y.blindensport.webui.prae.PraeForm.DayEntry;
import it.a11y.blindensport.webui.prae.PraeForm.Person;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.function.Function;

import static it.a11y.blindensport.webui.members.Dates.CLUB_ZONE;

/**
 * Who gets which PRAE form — port of PraeCalculator in the app's
 * PraeCalculation.swift. Keep the two in step: the same rules, in the same
 * order, so the app and this server file the same paperwork. Amounts come
 * from Attendance.praeAmount. The legal caps are flagged, not enforced.
 */
public final class PraeCalculator {
    public static final double DAILY_CAP = 120;
    public static final double MONTHLY_CAP = 720;

    private PraeCalculator() {
    }

    /** First and last name of someone known by an app account only. */
    public record AccountName(String firstName, String lastName) {
        String fullName() {
            return (firstName + " " + lastName).trim();
        }
    }

    /** Coaches and assistants across all teams, one entry per person, by last name. */
    public static List<Person> eligiblePeople(List<Membership> memberships, Function<String, MemberRecord> members,
                                              Map<String, AccountName> accounts) {
        Map<String, List<Membership>> byPerson = new LinkedHashMap<>();
        for (Membership m : memberships) {
            if (m.isHelper()) {
                String key = m.userId() != null ? m.userId() : m.memberId() != null ? m.memberId() : m.id();
                byPerson.computeIfAbsent(key, k -> new ArrayList<>()).add(m);
            }
        }
        List<Person> people = new ArrayList<>();
        byPerson.forEach((key, list) -> {
            Membership first = list.get(0);
            MemberRecord member = list.stream().filter(m -> m.memberId() != null).findFirst()
                    .map(m -> members.apply(m.memberId())).orElse(null);
            AccountName account = first.userId() == null ? null : accounts.get(first.userId());
            String last = account != null ? account.lastName() : member != null ? member.lastName() : "";
            String firstName = account != null ? account.firstName() : member != null ? member.firstName() : "";
            String display = account != null ? account.fullName() : member != null ? member.fullName() : "?";
            people.add(new Person(key, display, last, firstName, list.stream().map(Membership::id).toList(), member));
        });
        people.sort(Comparator.comparing(Person::lastName).thenComparing(Person::firstName));
        return people;
    }

    /**
     * One form per training name the person was deployed for in the month:
     * sessions of a name stay on one form, two sessions on one day are summed,
     * and a name whose amounts are all zero gets no form. Cancelled
     * ("Abgesagt") trainings count for nothing, as on the KostZ.
     *
     * @param trainings   every training, with
     * @param attendances their attendance rows
     */
    public static List<PraeForm> monthForms(Person person, int month, int year, List<ClubEvent> trainings,
                                            List<Attendance> attendances) {
        Set<String> memberships = Set.copyOf(person.membershipIds());
        Map<String, ClubEvent> events = new LinkedHashMap<>();
        trainings.forEach(e -> events.put(e.id(), e));
        List<Attendance> relevant = attendances.stream()
                .filter(a -> a.attended() && events.containsKey(a.eventId())
                        && "training".equals(events.get(a.eventId()).kind())
                        && !events.get(a.eventId()).isCancelled()
                        && memberships.contains(a.membershipId()))
                .sorted(Comparator.<Attendance, java.time.Instant>comparing(a -> events.get(a.eventId()).startDate())
                        .thenComparing(a -> events.get(a.eventId()).title()))
                .toList();

        Map<String, Map<Integer, Double>> amountsByTitle = new LinkedHashMap<>();
        Map<Integer, Double> personDayTotals = new TreeMap<>();
        for (Attendance a : relevant) {
            ClubEvent event = events.get(a.eventId());
            LocalDate date = LocalDate.ofInstant(event.startDate(), CLUB_ZONE);
            if (date.getMonthValue() != month || date.getYear() != year || a.praeAmount() == null) {
                continue;
            }
            double amount = a.praeAmount().doubleValue();
            amountsByTitle.computeIfAbsent(event.title(), t -> new TreeMap<>()).merge(date.getDayOfMonth(), amount, Double::sum);
            personDayTotals.merge(date.getDayOfMonth(), amount, Double::sum);
        }

        List<PraeForm> forms = new ArrayList<>();
        amountsByTitle.forEach((title, amounts) -> {
            List<DayEntry> entries = amounts.entrySet().stream()
                    .map(e -> new DayEntry(e.getKey(), e.getValue(), title)).toList();
            PraeForm form = new PraeForm(person, false, month, year, title, entries, personDayTotals, false);
            if (form.total() > 0) {
                forms.add(form);
            }
        });
        return forms;
    }

    /**
     * One tournament's forms for a person, one per calendar month it touches.
     * The amount is entered once for the whole tournament, so it's spread over
     * all its days first and only then grouped, which keeps the months adding
     * up to exactly what was entered.
     */
    public static List<PraeForm> tournamentForms(Person person, ClubEvent tournament, List<Attendance> attendances) {
        Set<String> memberships = Set.copyOf(person.membershipIds());
        LocalDate firstDay = LocalDate.ofInstant(tournament.startDate(), CLUB_ZONE);
        int dayCount = tournament.dayCount();

        record YearMonth(int year, int month) implements Comparable<YearMonth> {
            @Override
            public int compareTo(YearMonth o) {
                return year != o.year ? Integer.compare(year, o.year) : Integer.compare(month, o.month);
            }
        }

        Map<YearMonth, Map<Integer, Double>> amountsByMonth = new TreeMap<>();
        for (Attendance a : attendances) {
            if (!a.attended() || a.praeAmount() == null || !memberships.contains(a.membershipId())) {
                continue;
            }
            List<Double> perDay = spreadEvenly(a.praeAmount().doubleValue(), dayCount);
            for (int i = 0; i < dayCount; i++) {
                LocalDate date = firstDay.plusDays(i);
                amountsByMonth.computeIfAbsent(new YearMonth(date.getYear(), date.getMonthValue()), k -> new TreeMap<>())
                        .merge(date.getDayOfMonth(), perDay.get(i), Double::sum);
            }
        }

        boolean severalMonths = amountsByMonth.size() > 1;
        List<PraeForm> forms = new ArrayList<>();
        amountsByMonth.forEach((key, amounts) -> {
            List<DayEntry> entries = amounts.entrySet().stream()
                    .map(e -> new DayEntry(e.getKey(), e.getValue(), tournament.title())).toList();
            PraeForm form = new PraeForm(person, true, key.month(), key.year(), tournament.title(), entries, Map.of(),
                    severalMonths);
            if (form.total() > 0) {
                forms.add(form);
            }
        });
        return forms;
    }

    /**
     * Splits an amount across days in whole euros: every day gets the
     * rounded-down share and the middle day the remainder (€100 over 3 days →
     * 33/34/33). "Middle" is dayCount / 2, 0-indexed.
     */
    public static List<Double> spreadEvenly(double amount, int dayCount) {
        if (dayCount <= 0) {
            return List.of();
        }
        if (dayCount == 1) {
            return List.of(amount);
        }
        double lowerShare = Math.floor(amount / dayCount);
        double middleShare = amount - lowerShare * (dayCount - 1);
        List<Double> shares = new ArrayList<>();
        for (int i = 0; i < dayCount; i++) {
            shares.add(i == dayCount / 2 ? middleShare : lowerShare);
        }
        return shares;
    }
}
