package it.a11y.blindensport.webadmin.mcp;

import it.a11y.blindensport.webadmin.supabase.SupabaseConfig;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * RFC 9728 metadata: how an MCP client finds out that /mcp is protected and
 * that Supabase Auth is its authorization server. The 401 from
 * {@link McpAuthFilter} points here.
 */
@Path("/.well-known/oauth-protected-resource")
@Produces(MediaType.APPLICATION_JSON)
public class ProtectedResourceMetadata {
    @Inject
    McpConfig config;

    @Inject
    SupabaseConfig supabase;

    @GET
    public Map<String, Object> root() {
        return metadata();
    }

    @GET
    @Path("mcp")
    public Map<String, Object> mcp() {
        return metadata();
    }

    private Map<String, Object> metadata() {
        String issuer = config.oauthIssuer().filter(i -> !i.isBlank())
                .orElse(supabase.url().replaceAll("/$", "") + "/auth/v1");
        Map<String, Object> metadata = new LinkedHashMap<>();
        metadata.put("resource", config.publicUrl() + "/mcp");
        metadata.put("authorization_servers", List.of(issuer));
        metadata.put("bearer_methods_supported", List.of("header"));
        metadata.put("resource_name", "Blindensport Graz");
        return metadata;
    }
}
