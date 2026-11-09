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
     * Every training of a month.
     *
     * @param withPrivate read SVNR, IBAN and birth date, needed for the PRAE files; off to only show amounts
     */
    public Reports.Month month(int month, int year, boolean withPrivate) {
        if (month < 1 || month > 12) {
            throw new IllegalArgumentException("Monat muss zwischen 1 und 12 liegen.");
        }
        List<ClubEvent> trainings = club.events().stream().filter(e -> "training".equals(e.kind()))
                .filter(e -> {
                    LocalDate date = LocalDate.ofInstant(e.startDate(), CLUB_ZONE);
                    return date.getMonthValue() == month && date.getYear() == year;
                }).toList();
        List<Attendance> attendances = club.attendances(trainings.stream().map(ClubEvent::id).toList());
        List<Person> people = PraeCalculator.eligiblePeople(club.memberships(), members(withPrivate)::get, club.accounts());
        List<PraeForm> prae = new ArrayList<>();
        for (Person person : people) {
            prae.addAll(PraeCalculator.monthForms(person, month, year, trainings, attendances));
        }
        return new Reports.Month(month, year, KostZ.month(month, year, people, trainings, attendances), prae);
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
