package it.a11y.blindensport.webui.ui;

import it.a11y.blindensport.webui.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webui.club.ClubModels.Membership;

import java.util.List;
import java.util.function.Function;

/** Test access to the package-private roster rule. */
public final class AttendanceRosterAccess {
    private AttendanceRosterAccess() {
    }

    public static List<Membership> roster(ClubEvent event, List<Membership> all, Function<Membership, String> name) {
        return AttendanceDialog.rosterAcrossTeams(event, all, name);
    }
}
