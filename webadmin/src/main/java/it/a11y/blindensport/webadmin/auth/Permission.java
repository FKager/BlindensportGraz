package it.a11y.blindensport.webadmin.auth;

import java.util.Map;
import java.util.Set;

/** {@code public.app_permission} values (supabase/migrations/20261008000001_rbac.sql). */
public final class Permission {
    public static final String EVENTS_MANAGE = "events.manage";
    public static final String TEAMS_MANAGE = "teams.manage";
    public static final String MEMBERS_MANAGE = "members.manage";
    public static final String MEMBERS_PRIVATE_READ = "members.private.read";
    public static final String MEMBERS_PRIVATE_WRITE = "members.private.write";
    public static final String USERS_APPROVE = "users.approve";
    public static final String ROLES_ASSIGN = "roles.assign";
    public static final String BUDGET_MANAGE = "budget.manage";
    public static final String ROLELOG_READ = "rolelog.read";
    public static final String CLUB_MANAGE = "club.manage";

    /** Any one of these lets an account use the web admin (coach, admin, root). */
    public static final Set<String> WEB_ACCESS = Set.of(MEMBERS_MANAGE, EVENTS_MANAGE, TEAMS_MANAGE, USERS_APPROVE);

    /** German role names, as the app shows them. */
    public static final Map<String, String> ROLE_NAMES = Map.of(
            "admin", "Admin", "root", "Root", "coach", "Trainer:in", "member", "Mitglied");

    private Permission() {
    }
}
