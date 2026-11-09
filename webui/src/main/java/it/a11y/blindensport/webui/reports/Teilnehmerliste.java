package it.a11y.blindensport.webui.reports;

import it.a11y.blindensport.webui.club.ClubModels.Attendance;
import it.a11y.blindensport.webui.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webui.club.ClubModels.Membership;
import it.a11y.blindensport.webui.members.MemberRecord;
import it.a11y.blindensport.webui.prae.PraeCalculator.AccountName;
import it.a11y.blindensport.webui.xlsx.XlsxPatch;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.Predicate;

import static it.a11y.blindensport.webui.members.Dates.CLUB_ZONE;

/**
 * Sport Austria's "TeilnehmerInnenliste (TN)" for one tournament — port of
 * the app's TeilnehmerlisteExport.swift, using the club's 15-row template.
 * A tournament files two: Sportler (players) and Helfer (coaches and
 * assistants), as in the app's Berichte menu.
 *
 * @param ort  H3: the tournament's city, plus a foreign country
 * @param rows everyone counted (D7); only the first {@link #MAX_ROWS} fit the form
 */
public record Teilnehmerliste(String betrifft, String ort, LocalDate start, LocalDate end, List<Row> rows) {
    /** The template's numbered rows (sheet rows 10–24); the layout can't grow. */
    public static final int MAX_ROWS = 15;
    static final String TEMPLATE = "reports/TN_TeilnehmerInnenliste.xlsx";
    private static final int FIRST_ROW = 10;
    private static final DateTimeFormatter DAY = DateTimeFormatter.ofPattern("dd.MM.uuuu");

    /**
     * One participant. Attendance is one yes/no per event, so everyone gets
     * the event's day count.
     *
     * @param name    "Nachname Vorname" (the column is "FAMILIEN- und VORNAME")
     * @param wohnort the roster entry's city; empty for someone with an app account only
     */
    public record Row(String name, String wohnort, String lastName, String firstName) {
    }

    /** Players and helpers of one tournament. */
    public record Pair(Teilnehmerliste sportler, Teilnehmerliste helfer) {
    }

    /** Inclusive, at least 1. */
    public int dayCount() {
        return (int) Math.max(1, ChronoUnit.DAYS.between(start, end) + 1);
    }

    /** True when more people attended than the form has rows. */
    public boolean overflows() {
        return rows.size() > MAX_ROWS;
    }

    /**
     * Attended rows of the tournament, one per person (an app account or a
     * roster entry, as in the app), by last name, split by role: players to
     * Sportler, coaches and assistants to Helfer.
     */
    public static Pair forTournament(ClubEvent tournament, List<Attendance> attendances, List<Membership> memberships,
                                     Map<String, MemberRecord> members, Map<String, AccountName> accounts) {
        Map<String, Membership> byId = new HashMap<>();
        memberships.forEach(m -> byId.put(m.id(), m));
        Set<String> seen = new HashSet<>();
        List<Membership> attended = new ArrayList<>();
        for (Attendance a : attendances) {
            Membership m = byId.get(a.membershipId());
            if (!a.attended() || !tournament.id().equals(a.eventId()) || m == null) {
                continue;
            }
            String key = m.userId() != null ? m.userId() : m.memberId() != null ? m.memberId() : m.id();
            if (seen.add(key)) {
                attended.add(m);
            }
        }
        String ort = Places.withForeignCountry(tournament.city(), tournament.country());
        LocalDate start = LocalDate.ofInstant(tournament.startDate(), CLUB_ZONE);
        LocalDate end = LocalDate.ofInstant(tournament.endDate(), CLUB_ZONE);
        Predicate<Membership> player = m -> "player".equals(m.role());
        return new Pair(
                new Teilnehmerliste(tournament.title(), ort, start, end, rows(attended, player, members, accounts)),
                new Teilnehmerliste(tournament.title(), ort, start, end,
                        rows(attended, Membership::isHelper, members, accounts)));
    }

    private static List<Row> rows(List<Membership> attended, Predicate<Membership> role,
                                  Map<String, MemberRecord> members, Map<String, AccountName> accounts) {
        return attended.stream().filter(role).map(m -> row(m, members, accounts))
                .sorted(Comparator.comparing(Row::lastName).thenComparing(Row::firstName))
                .toList();
    }

    private static Row row(Membership m, Map<String, MemberRecord> members, Map<String, AccountName> accounts) {
        MemberRecord member = m.memberId() == null ? null : members.get(m.memberId());
        if (m.userId() != null) {
            AccountName account = accounts.get(m.userId());
            String first = account == null ? "" : account.firstName();
            String last = account == null ? "" : account.lastName();
            String display = (first + " " + last).trim();
            return new Row(display.isEmpty() ? "?" : display, "", last, first);
        }
        if (member != null) {
            return new Row(member.lastName() + " " + member.firstName(), member.city(), member.lastName(),
                    member.firstName());
        }
        return new Row("?", "", "", "");
    }

    /** The filled template. */
    public byte[] xlsx() {
        return XlsxPatch.fillTemplate(TEMPLATE, Map.of(), xml -> {
            String p = XlsxPatch.setText(xml, "C3", betrifft);
            p = XlsxPatch.setText(p, "H3", ort);
            p = XlsxPatch.setText(p, "D5", DAY.format(start));
            p = XlsxPatch.setText(p, "F5", DAY.format(end));
            p = XlsxPatch.setInteger(p, "H5", dayCount());
            p = XlsxPatch.setInteger(p, "D7", rows.size());
            for (int i = 0; i < Math.min(rows.size(), MAX_ROWS); i++) {
                int sheetRow = FIRST_ROW + i;
                Row row = rows.get(i);
                p = XlsxPatch.setText(p, "B" + sheetRow, row.name());
                if (!row.wohnort().isEmpty()) {
                    p = XlsxPatch.setText(p, "D" + sheetRow, row.wohnort());
                }
                p = XlsxPatch.setInteger(p, "F" + sheetRow, dayCount());
            }
            return p;
        });
    }
}
