package it.a11y.blindensport.webui.mcp;

import it.a11y.blindensport.webui.auth.Access;
import it.a11y.blindensport.webui.club.ClubStore;
import it.a11y.blindensport.webui.members.MemberStore;
import it.a11y.blindensport.webui.supabase.Postgrest;

import java.util.UUID;

/**
 * The person an MCP request acts for. All database work runs with their own
 * token (anon key + their JWT), so RLS and the RPCs decide what is allowed,
 * exactly as in the app. The MCP server has no rights of its own.
 */
public record McpUser(UUID id, String email, Access access, Postgrest db) {
    public boolean can(String permission) {
        return access.permissions().contains(permission);
    }

    public ClubStore club() {
        return new ClubStore(db, id);
    }

    public MemberStore roster() {
        return new MemberStore(db);
    }
}
