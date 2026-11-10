package it.a11y.blindensport.webui.reports;

import it.a11y.blindensport.webui.club.ClubModels.Attendance;
import it.a11y.blindensport.webui.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webui.club.ClubModels.Membership;
import it.a11y.blindensport.webui.club.ClubStore;
import it.a11y.blindensport.webui.members.MemberRecord;
import it.a11y.blindensport.webui.members.MemberStore;
import it.a11y.blindensport.webui.prae.PraeCalculator;
import it.a11y.blindensport.webui.prae.PraeCalculator.AccountName;
import it.a11y.blindensport.webui.prae.PraeForm;
import it.a11y.blindensport.webui.prae.PraeForm.Person;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.stream.Collectors;

import static it.a11y.blindensport.webui.members.Dates.CLUB_ZONE;

/**
 * Reads what one period's invoicing needs, as the signed-in user (RLS
 * applies), and works it out. Shared by the "Abrechnung" page and
 * /api/reports.
 */
public final class ReportService {
    private final ClubStore club;
    private final MemberStore roster;

    public ReportService(ClubStore club, MemberStore roster) {
        this.club = club;
        this.roster = roster;
    }

    /**
     * The trainings of a month: KostZ and PRAE count only {@code sport}'s
     * trainings, and the Trainingsfrequenzliste of that sport runs from the
     * season's start (Jänner or Juli) to the month's end.
     *
     * @param sport       a training sport, or null for every sport (then without Trainingsfrequenzliste)
     * @param withPrivate read SVNR, IBAN and birth date, needed for the PRAE files; off to only show amounts
     */
    public Reports.Month month(int month, int year, String sport, boolean withPrivate) {
        if (month < 1 || month > 12) {
            throw new IllegalArgumentException("Monat muss zwischen 1 und 12 liegen.");
        }
        List<ClubEvent> events = club.events();
        List<ClubEvent> trainings = events.stream().filter(e -> "training".equals(e.kind()) && !e.isCancelled())
                .filter(e -> sport == null || sport.equals(e.sport()))
                .filter(e -> {
                    LocalDate date = LocalDate.ofInstant(e.startDate(), CLUB_ZONE);
                    return date.getMonthValue() == month && date.getYear() == year;
                }).toList();
        List<ClubEvent> season = sport == null ? List.of() : events.stream()
                .filter(e -> "training".equals(e.kind()) && sport.equals(e.sport()) && !e.isCancelled())
                .filter(e -> {
                    LocalDate date = LocalDate.ofInstant(e.startDate(), CLUB_ZONE);
                    return date.getYear() == year && date.getMonthValue() <= month
                            && (date.getMonthValue() <= 6) == (month <= 6);
                }).toList();
        List<String> ids = java.util.stream.Stream.concat(trainings.stream(), season.stream())
                .map(ClubEvent::id).distinct().toList();
        List<Attendance> attendances = ids.isEmpty() ? List.of() : club.attendances(ids);
        List<Membership> memberships = club.memberships();
        Map<String, MemberRecord> members = members(withPrivate);
        Map<String, AccountName> accounts = club.accounts();
        List<Person> people = PraeCalculator.eligiblePeople(memberships, members::get, accounts);
        List<PraeForm> prae = new ArrayList<>();
        for (Person person : people) {
            prae.addAll(PraeCalculator.monthForms(person, month, year, trainings, attendances));
        }
        Trainingsfrequenzliste frequenz = sport == null ? null
                : Trainingsfrequenzliste.seasonUpTo(sport, month, year, season, attendances, club.teams(),
                memberships, members, accounts);
        return new Reports.Month(month, year, sport, KostZ.month(month, year, people, trainings, attendances), prae,
                frequenz);
    }

    /** One tournament, by id. */
    public Reports.Tournament tournament(String id, boolean withPrivate) {
        ClubEvent event = club.event(id.toLowerCase(Locale.ROOT))
                .filter(e -> "tournament".equals(e.kind()))
                .orElseThrow(() -> new IllegalArgumentException("Turnier nicht gefunden."));
        List<Attendance> attendances = club.attendances(event.id());
        List<Membership> memberships = club.memberships();
        Map<String, MemberRecord> members = members(withPrivate);
        Map<String, AccountName> accounts = club.accounts();
        List<Person> people = PraeCalculator.eligiblePeople(memberships, members::get, accounts);
        List<PraeForm> prae = new ArrayList<>();
        for (Person person : people) {
            prae.addAll(PraeCalculator.tournamentForms(person, event, attendances));
        }
        return new Reports.Tournament(event, KostZ.tournament(event, people, attendances), prae,
                Teilnehmerliste.forTournament(event, attendances, memberships, members, accounts));
    }

    /**
     * The Trainingsfrequenzliste of one training sport and half year
     * (1 = Jänner–Juni, 2 = Juli–Dezember). Reads no private data.
     */
    public Trainingsfrequenzliste trainingsfrequenzliste(String sport, int half, int year) {
        if (half != 1 && half != 2) {
            throw new IllegalArgumentException("Halbjahr muss 1 oder 2 sein.");
        }
        List<ClubEvent> trainings = club.events().stream()
                .filter(e -> "training".equals(e.kind()) && sport.equals(e.sport()))
                .filter(e -> LocalDate.ofInstant(e.startDate(), CLUB_ZONE).getYear() == year).toList();
        List<Attendance> attendances = trainings.isEmpty() ? List.of()
                : club.attendances(trainings.stream().map(ClubEvent::id).toList());
        return Trainingsfrequenzliste.of(sport, half, year, trainings, attendances, club.teams(), club.memberships(),
                members(false), club.accounts());
    }

    /** Sports that have trainings, for the Trainingsfrequenzliste. */
    public List<String> trainingSports() {
        return Trainingsfrequenzliste.sports(club.events());
    }

    /** All tournaments, latest first, to choose from. */
    public List<ClubEvent> tournaments() {
        return club.events().stream().filter(e -> "tournament".equals(e.kind()))
                .sorted(Comparator.comparing(ClubEvent::startDate).reversed()).toList();
    }

    private Map<String, MemberRecord> members(boolean withPrivate) {
        return roster.all(withPrivate).stream()
                .collect(Collectors.toMap(m -> m.id().toLowerCase(Locale.ROOT), m -> m, (a, b) -> a));
    }
}
