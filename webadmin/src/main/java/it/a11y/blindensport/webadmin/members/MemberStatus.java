package it.a11y.blindensport.webadmin.members;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * {@code members.status} (supabase/migrations/20261107000001_member_status.sql).
 * Removing an entry takes two steps: anyone with members.manage marks it
 * {@link #DELETE}, then root removes it with the delete_member RPC.
 */
public final class MemberStatus {
    public static final String NEW = "new";
    public static final String ACTIVE = "active";
    public static final String DELETE = "delete";

    public static final List<String> ALL = List.of(NEW, ACTIVE, DELETE);

    public static final Map<String, String> LABELS;

    static {
        Map<String, String> labels = new LinkedHashMap<>();
        labels.put(NEW, "Neu");
        labels.put(ACTIVE, "Aktiv");
        labels.put(DELETE, "Zum Löschen markiert");
        LABELS = java.util.Collections.unmodifiableMap(labels);
    }

    private MemberStatus() {
    }

    /** The German name; an unknown value is shown as it is. */
    public static String label(String status) {
        return LABELS.getOrDefault(status, status == null ? "" : status);
    }

    public static boolean isValid(String status) {
        return ALL.contains(status);
    }
}
