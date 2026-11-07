package it.a11y.blindensport.webui.api;

import it.a11y.blindensport.webui.auth.AdminSession;
import it.a11y.blindensport.webui.auth.AdminSessions;
import it.a11y.blindensport.webui.members.MemberStore;
import it.a11y.blindensport.webui.mcp.McpTokens;
import it.a11y.blindensport.webui.supabase.GoTrue;
import io.vertx.core.http.HttpServerRequest;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

import java.util.List;

/**
 * The signed-in person's own MCP tokens. Creating one asks for the password
 * again: it opens the separate Supabase session the token stands for, and
 * proves it's the person, not a browser left open.
 */
@Path("/api/mcp-tokens")
@Produces(MediaType.APPLICATION_JSON)
public class McpTokensResource {
    public record NewToken(String password, String label) {
    }

    @Inject
    AdminSessions sessions;

    @Inject
    McpTokens tokens;

    @GET
    public List<McpTokens.Info> list(@Context ContainerRequestContext request) {
        return tokens.list(CurrentAdmin.require(request).db());
    }

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    public Response create(NewToken body, @Context ContainerRequestContext request, @Context HttpServerRequest http) {
        AdminSession admin = CurrentAdmin.require(request);
        if (body == null || body.password() == null) {
            throw new ApiException(400, "Passwort fehlt.");
        }
        GoTrue.Tokens session = sessions.confirmPassword(admin, body.password(), SessionResource.clientAddress(http));
        try {
            return Response.status(201).entity(tokens.create(admin.db(), session, body.label())).build();
        } catch (IllegalArgumentException e) {
            throw new ApiException(400, e.getMessage());
        }
    }

    @DELETE
    @Path("{id}")
    public Response revoke(@PathParam("id") String id, @Context ContainerRequestContext request) {
        String key = MemberStore.key(id).orElseThrow(() -> ApiException.notFound(id));
        tokens.revoke(CurrentAdmin.require(request).db(), key);
        return Response.noContent().build();
    }
}
