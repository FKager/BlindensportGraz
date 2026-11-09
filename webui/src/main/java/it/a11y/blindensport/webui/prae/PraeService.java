package it.a11y.blindensport.webui.prae;

import it.a11y.blindensport.webui.club.ClubModels.Attendance;
import it.a11y.blindensport.webui.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webui.club.ClubStore;
import it.a11y.blindensport.webui.members.Dates;
import it.a11y.blindensport.webui.members.MemberRecord;
import it.a11y.blindensport.webui.members.MemberStore;
import it.a11y.blindensport.webui.prae.PraeForm.Person;
import it.a11y.blindensport.webui.xlsx.XlsxPatch;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

/** Reads what a PRAE needs as the signed-in user and works out the forms. */
public final class PraeService {
    public static final String VEREIN = "Grazer VSC";

    private final ClubStore club;
    private final MemberStore roster;

    public PraeService(ClubStore club, MemberStore roster) {
        this.club = club;
        this.roster = roster;
    }

    /**
     * Forms for one event: a tournament's own, or those of a training's name in
     * its month, since a form covers all sessions of that name.
     *
     * @param memberId only this person, or null for everyone
     * @param withPrivate read SVNR, IBAN and birth date for the real forms; off for a preview
     */
    public List<PraeForm> forEvent(ClubEvent event, String memberId, boolean withPrivate) {
        if ("tournament".equals(event.kind())) {
            List<Attendance> attendances = club.attendances(event.id());
            return forPeople(memberId, withPrivate, p -> PraeCalculator.tournamentForms(p, event, attendances));
        }
        if (!"training".equals(event.kind())) {
            throw new IllegalArgumentException("PRAE gibt es nur für Trainings und Turniere.");
        }
        LocalDate date = LocalDate.ofInstant(event.startDate(), Dates.CLUB_ZONE);
        return forMonth(date.getMonthValue(), date.getYear(), memberId, withPrivate).stream()
                .filter(f -> f.purpose().equals(event.title())).toList();
    }

    /** Every training's forms in a month. Tournaments are filed per tournament, as in the app. */
    public List<PraeForm> forMonth(int month, int year, String memberId, boolean withPrivate) {
        List<ClubEvent> trainings = club.events().stream().filter(e -> "training".equals(e.kind()))
                .filter(e -> {
                    LocalDate date = LocalDate.ofInstant(e.startDate(), Dates.CLUB_ZONE);
                    return date.getMonthValue() == month && date.getYear() == year;
                }).toList();
        List<Attendance> attendances = club.attendances(trainings.stream().map(ClubEvent::id).toList());
        return forPeople(memberId, withPrivate, p -> PraeCalculator.monthForms(p, month, year, trainings, attendances));
    }

    private List<PraeForm> forPeople(String memberId, boolean withPrivate, Function<Person, List<PraeForm>> forms) {
        Map<String, MemberRecord> members = roster.all(withPrivate).stream()
                .collect(Collectors.toMap(m -> m.id().toLowerCase(Locale.ROOT), m -> m, (a, b) -> a));
        List<Person> people = PraeCalculator.eligiblePeople(club.memberships(), members::get, club.accounts());
        String wanted = memberId == null ? null : memberId.toLowerCase(Locale.ROOT);
        List<PraeForm> result = new ArrayList<>();
        for (Person person : people) {
            boolean selected = wanted == null || wanted.equals(person.id())
                    || (person.member() != null && wanted.equals(person.member().id().toLowerCase(Locale.ROOT)));
            if (selected) {
                result.addAll(forms.apply(person));
            }
        }
        return result;
    }

    /** All forms and their Darstellung as one zip; names made unique so nothing overwrites. */
    public static byte[] zip(List<PraeForm> forms) {
        return XlsxPatch.zip(files(forms));
    }

    /** Each form and its Darstellung, named as in the app's Sammelabrechnung. */
    public static LinkedHashMap<String, byte[]> files(List<PraeForm> forms) {
        LinkedHashMap<String, byte[]> files = new LinkedHashMap<>();
        for (PraeForm form : forms) {
            XlsxPatch.addUnique(files, PraeExporter.fileName(form, "PRAE"), PraeExporter.mainForm(form));
            XlsxPatch.addUnique(files, PraeExporter.fileName(form, "PRAE-Darstellung"), PraeExporter.darstellung(form, VEREIN));
        }
        return files;
    }
}
