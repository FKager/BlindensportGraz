package it.a11y.blindensport.webui.reports;

import it.a11y.blindensport.webui.club.ClubModels.Attendance;
import it.a11y.blindensport.webui.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webui.club.ClubModels.Membership;
import it.a11y.blindensport.webui.club.ClubModels.Team;
import it.a11y.blindensport.webui.members.MemberRecord;
import it.a11y.blindensport.webui.prae.PraeCalculator.AccountName;
import it.a11y.blindensport.webui.xlsx.XlsxPatch;

import java.time.LocalDate;
import java.time.LocalTime;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;

import static it.a11y.blindensport.webui.members.Dates.CLUB_ZONE;

/**
 * Sport Austria's Trainingsfrequenzliste for one training sport and half
 * year — port of the app's TrainingsfrequenzlisteCalculation.swift and
 * TrainingsfrequenzlisteExport.swift. The template is the club's filled-in
 * Torball 2026 list; its header, dates, names and "j"/"n" cells are
 * overwritten, everything else stays as it is.
 *
 * @param title     P3 "Sportart": the earliest training's title, else the sport
 * @param location  Y3 "Sportstätte": the earliest training's venue; null if none
 * @param startTime H4, the earliest training's start time; null without trainings
 * @param endTime   L4, its end time
 * @param dates     the training days, ascending, at most {@link #MAX_DATES}
 * @param people    players first, then coaches and assistants, each by last name; at most {@link #MAX_PEOPLE}
 * @param teams     names of the teams assigned to the period's trainings, in order of their first training
 * @param missingDates  training days that didn't fit the form
 * @param missingPeople people who didn't fit the form
 */
public record Trainingsfrequenzliste(String sport, int half, int year, String title, String location,
                                     LocalTime startTime, LocalTime endTime, List<LocalDate> dates,
                                     List<Person> people, List<String> teams, int missingDates,
                                     int missingPeople) {
    /** Date columns D–AB. */
    public static final int MAX_DATES = 25;
    /** Person rows 8–31. */
    public static final int MAX_PEOPLE = 24;
    public static final String VEREIN = "Sektion Blindensport (GVSC)";
    static final String TEMPLATE = "reports/Trainingsfrequenzliste_Vorlage.xlsx";
    private static final int FIRST_DATE_COLUMN = 4;
    private static final int FIRST_ROW = 8;
    private static final LocalDate EXCEL_EPOCH = LocalDate.of(1899, 12, 30);

    /**
     * One roster row.
     *
     * @param roleSuffix "Übungsleiter(in)" / "Helfer(in)" after the last name, null for players
     * @param attended   the training days this person was marked present
     */
    public record Person(String firstName, String lastName, String roleSuffix, boolean helper,
                         Set<LocalDate> attended) {
        /** "Muster (Übungsleiterin)", as in column C. */
        public String lastNameWithRole() {
            return roleSuffix == null ? lastName : lastName + " (" + roleSuffix + ")";
        }

        public String displayName() {
            return (firstName + " " + lastName).trim();
        }
    }

    /** "1. Halbjahr (Jänner–Juni)". */
    public static String halfLabel(int half) {
        return half == 1 ? "1. Halbjahr (Jänner–Juni)" : "2. Halbjahr (Juli–Dezember)";
    }

    /** "Torball_H1-2026", the app's season-bundle label. */
    public String label() {
        return Reports.fileSafe(sport) + "_H" + half + "-" + year;
    }

    /** People marked present on {@code date}: the cached value of the "ges. TL" row. */
    public int present(LocalDate date) {
        return (int) people.stream().filter(p -> p.attended().contains(date)).count();
    }

    /** Distinct sports of all trainings, sorted. */
    public static List<String> sports(List<ClubEvent> events) {
        return events.stream().filter(e -> "training".equals(e.kind())).map(ClubEvent::sport)
                .filter(s -> s != null && !s.isBlank()).distinct().sorted().toList();
    }

    /**
     * The list for one sport and half year (1 = Jänner–Juni, 2 = Juli–Dezember).
     * The roster is every member of every team assigned to one of the period's
     * trainings, once per person (an app account or a roster entry), whether
     * they attended or not — as in the app. Unlike the app, a person on two
     * of those teams gets the attendance ticked on either team's training.
     *
     * @param attendances the attendances of {@code events}' trainings (others are ignored)
     */
    public static Trainingsfrequenzliste of(String sport, int half, int year, List<ClubEvent> events,
                                            List<Attendance> attendances, List<Team> teams,
                                            List<Membership> memberships, Map<String, MemberRecord> members,
                                            Map<String, AccountName> accounts) {
        return of(sport, half, year, half == 1 ? 6 : 12, events, attendances, teams, memberships, members, accounts);
    }

    /**
     * The list from the start of {@code lastMonth}'s season (Jänner or Juli)
     * to the end of {@code lastMonth} — what a month's Sammelabrechnung
     * files: August covers Juli and August.
     */
    public static Trainingsfrequenzliste seasonUpTo(String sport, int lastMonth, int year, List<ClubEvent> events,
                                                    List<Attendance> attendances, List<Team> teams,
                                                    List<Membership> memberships, Map<String, MemberRecord> members,
                                                    Map<String, AccountName> accounts) {
        if (lastMonth < 1 || lastMonth > 12) {
            throw new IllegalArgumentException("Monat muss zwischen 1 und 12 liegen.");
        }
        return of(sport, lastMonth <= 6 ? 1 : 2, year, lastMonth, events, attendances, teams, memberships, members,
                accounts);
    }

    private static Trainingsfrequenzliste of(String sport, int half, int year, int lastMonth, List<ClubEvent> events,
                                             List<Attendance> attendances, List<Team> teams,
                                             List<Membership> memberships, Map<String, MemberRecord> members,
                                             Map<String, AccountName> accounts) {
        if (half != 1 && half != 2) {
            throw new IllegalArgumentException("Halbjahr muss 1 oder 2 sein.");
        }
        List<ClubEvent> trainings = trainings(sport, half, year, lastMonth, events);
        TreeSet<LocalDate> allDates = new TreeSet<>(trainings.stream().map(Trainingsfrequenzliste::day).toList());
        List<LocalDate> dates = allDates.stream().limit(MAX_DATES).toList();

        LinkedHashMap<String, Boolean> teamIds = new LinkedHashMap<>();
        trainings.forEach(t -> (t.teamIds() == null ? List.<String>of() : t.teamIds())
                .forEach(id -> teamIds.put(id, true)));

        // Attendance per person, not per team membership: someone on two teams of
        // this sport is listed once but may be ticked on either team's training.
        Map<String, String> personOf = new HashMap<>();
        memberships.forEach(m -> personOf.put(m.id(), personKey(m)));
        Map<String, ClubEvent> trainingById = new HashMap<>();
        trainings.forEach(t -> trainingById.put(t.id(), t));
        Map<String, Set<LocalDate>> attendedByPerson = new HashMap<>();
        for (Attendance a : attendances) {
            ClubEvent training = trainingById.get(a.eventId());
            String person = personOf.get(a.membershipId());
            if (!a.attended() || training == null || person == null) {
                continue;
            }
            LocalDate date = day(training);
            if (dates.contains(date)) {
                attendedByPerson.computeIfAbsent(person, k -> new HashSet<>()).add(date);
            }
        }

        Set<String> seen = new HashSet<>();
        List<Person> roster = new ArrayList<>();
        for (String teamId : teamIds.keySet()) {
            for (Membership m : memberships) {
                String key = personKey(m);
                if (teamId.equals(m.teamId()) && seen.add(key)) {
                    roster.add(person(m, members, accounts, attendedByPerson.getOrDefault(key, Set.of())));
                }
            }
        }
        List<Person> people = roster.stream()
                .sorted(Comparator.comparing(Person::helper).thenComparing(Person::lastName)
                        .thenComparing(Person::firstName))
                .limit(MAX_PEOPLE).toList();

        Map<String, String> teamNames = new HashMap<>();
        teams.forEach(t -> teamNames.put(t.id(), t.name()));
        List<String> assigned = teamIds.keySet().stream().map(id -> teamNames.getOrDefault(id, "?")).toList();

        ClubEvent first = trainings.stream().min(Comparator.comparing(ClubEvent::startDate)).orElse(null);
        String title = first != null && first.title() != null && !first.title().isEmpty() ? first.title() : sport;
        String location = first == null || first.location() == null || first.location().isEmpty() ? null
                : first.location();
        LocalTime start = first == null ? null : first.startDate().atZone(CLUB_ZONE).toLocalTime();
        LocalTime end = first == null ? null : first.endDate().atZone(CLUB_ZONE).toLocalTime();
        return new Trainingsfrequenzliste(sport, half, year, title, location, start, end, dates, people, assigned,
                allDates.size() - dates.size(), roster.size() - people.size());
    }

    private static List<ClubEvent> trainings(String sport, int half, int year, int lastMonth,
                                             List<ClubEvent> events) {
        return events.stream().filter(e -> "training".equals(e.kind()) && sport.equals(e.sport())).filter(e -> {
            LocalDate date = day(e);
            int month = date.getMonthValue();
            return date.getYear() == year && (half == 1 ? month <= 6 : month >= 7) && month <= lastMonth;
        }).sorted(Comparator.comparing(ClubEvent::startDate)).toList();
    }

    /** The person behind a membership: app account, else roster entry (TrainingDetailView.allMemberships). */
    private static String personKey(Membership m) {
        return m.userId() != null ? m.userId() : m.memberId() != null ? m.memberId() : m.id();
    }

    private static LocalDate day(ClubEvent e) {
        return LocalDate.ofInstant(e.startDate(), CLUB_ZONE);
    }

    private static Person person(Membership m, Map<String, MemberRecord> members, Map<String, AccountName> accounts,
                                 Set<LocalDate> attended) {
        String first = "";
        String last = "";
        boolean female = false;
        if (m.userId() != null) {
            AccountName account = accounts.get(m.userId());
            if (account != null) {
                first = account.firstName();
                last = account.lastName();
            }
        } else if (m.memberId() != null && members.get(m.memberId()) != null) {
            MemberRecord member = members.get(m.memberId());
            first = member.firstName();
            last = member.lastName();
            female = "f".equals(member.gender());
        }
        String suffix = switch (m.role() == null ? "" : m.role()) {
            case "coach" -> female ? "Übungsleiterin" : "Übungsleiter";
            case "assistant" -> female ? "Helferin" : "Helfer";
            default -> null;
        };
        return new Person(first, last, suffix, m.isHelper(), Set.copyOf(attended));
    }

    // ------------------------------------------------------------ the file

    /** The filled template. */
    public byte[] xlsx() {
        return XlsxPatch.fillTemplate(TEMPLATE, Map.of(), xml -> {
            String p = XlsxPatch.overwriteText(xml, "D3", VEREIN);
            p = XlsxPatch.overwriteText(p, "P3", title);
            p = location == null ? XlsxPatch.clearCell(p, "Y3") : XlsxPatch.overwriteText(p, "Y3", location);
            p = startTime == null ? XlsxPatch.clearCell(p, "H4")
                    : XlsxPatch.overwriteNumber(p, "H4", timeFraction(startTime));
            p = endTime == null ? XlsxPatch.clearCell(p, "L4") : XlsxPatch.overwriteNumber(p, "L4", timeFraction(endTime));
            p = XlsxPatch.overwriteNumber(p, "Y4", year);

            for (int i = 0; i < MAX_DATES; i++) {
                String ref = column(FIRST_DATE_COLUMN + i) + "6";
                p = i < dates.size() ? XlsxPatch.overwriteNumber(p, ref, serial(dates.get(i))) : XlsxPatch.clearCell(p, ref);
            }
            for (int r = 0; r < MAX_PEOPLE; r++) {
                int row = FIRST_ROW + r;
                Person person = r < people.size() ? people.get(r) : null;
                p = XlsxPatch.overwriteText(p, "A" + row, person == null ? "" : (r + 1) + ".");
                p = XlsxPatch.overwriteText(p, "B" + row, person == null ? "" : person.firstName());
                p = XlsxPatch.overwriteText(p, "C" + row, person == null ? "" : person.lastNameWithRole());
                for (int i = 0; i < MAX_DATES; i++) {
                    String ref = column(FIRST_DATE_COLUMN + i) + row;
                    p = person == null || i >= dates.size() ? XlsxPatch.clearCell(p, ref)
                            : XlsxPatch.overwriteText(p, ref, person.attended().contains(dates.get(i)) ? "j" : "n");
                }
            }
            for (int i = 0; i < MAX_DATES; i++) {
                double total = i < dates.size() ? present(dates.get(i)) : 0;
                p = XlsxPatch.setFormulaCachedValue(p, column(FIRST_DATE_COLUMN + i) + "32", total);
            }
            return p;
        });
    }

    /** Days since 1899-12-30, Excel's date serial (46029 = 2026-01-07). */
    static double serial(LocalDate date) {
        return ChronoUnit.DAYS.between(EXCEL_EPOCH, date);
    }

    /** A time of day as a fraction of 24 h (17:30 = 0.729…). */
    static double timeFraction(LocalTime time) {
        return time.toSecondOfDay() / 86400.0;
    }

    /** 4 → D, 28 → AB. */
    static String column(int number) {
        StringBuilder letters = new StringBuilder();
        for (int n = number; n > 0; n = (n - 1) / 26) {
            letters.insert(0, (char) ('A' + (n - 1) % 26));
        }
        return letters.toString();
    }
}
