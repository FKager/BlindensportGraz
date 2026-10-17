package it.a11y.blindensport.webadmin.auth;

import com.fasterxml.jackson.databind.JsonNode;
import it.a11y.blindensport.webadmin.supabase.Postgrest;

import java.util.Collections;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

import static it.a11y.blindensport.webadmin.supabase.Postgrest.eq;

/**
 * Role and permissions as the database grants them right now (tables, not
 * the JWT, so a role change counts on the next lookup). No {@code user_roles}
 * row = pending account; a blocked account gets the same: role null, no
 * permissions.
 */
public record Access(String role, Set<String> permissions) {
    public static final Access NONE = new Access(null, Set.of());

    public boolean canUseWebAdmin() {
        return role != null && !Collections.disjoint(permissions, Permission.WEB_ACCESS);
    }

    /** Looked up with the user's own token (own user_roles row and role_permissions are readable). */
    public static Access load(Postgrest db, UUID userId) {
        JsonNode blocked = db.rpc("is_blocked", java.util.Map.of());
        if (blocked.asBoolean(false)) {
            return NONE;
        }
        var roles = db.select("user_roles", "role", eq("user_id", userId));
        if (roles.isEmpty() || !roles.get(0).hasNonNull("role")) {
            return NONE;
        }
        String role = roles.get(0).get("role").asText();
        Set<String> permissions = new HashSet<>();
        db.select("role_permissions", "permission", eq("role", role))
                .forEach(row -> permissions.add(row.path("permission").asText()));
        return new Access(role, Set.copyOf(permissions));
    }
}
