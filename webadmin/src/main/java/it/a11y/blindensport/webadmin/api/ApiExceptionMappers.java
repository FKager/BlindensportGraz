package it.a11y.blindensport.webadmin.api;

import it.a11y.blindensport.webadmin.auth.SessionExpiredException;
import it.a11y.blindensport.webadmin.auth.SignInException;
import it.a11y.blindensport.webadmin.supabase.DbErrorMessages;
import it.a11y.blindensport.webadmin.supabase.SupabaseException;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.jboss.logging.Logger;
import org.jboss.resteasy.reactive.server.ServerExceptionMapper;

import java.io.UncheckedIOException;
import java.util.LinkedHashMap;
import java.util.Map;

/** Every API error as {@code {"error": true, "reason": "..."}} (admin-session.js and scripts read {@code reason}). */
public class ApiExceptionMappers {
    private static final Logger LOG = Logger.getLogger(ApiExceptionMappers.class);

    @ServerExceptionMapper
    public Response api(ApiException e) {
        return error(e.status(), e.getMessage());
    }

    @ServerExceptionMapper
    public Response signIn(SignInException e) {
        return error(e.status(), e.getMessage());
    }

    @ServerExceptionMapper
    public Response expired(SessionExpiredException e) {
        return error(401, "Bitte anmelden.");
    }

    @ServerExceptionMapper
    public Response supabase(SupabaseException e) {
        if (e.isUnauthenticated()) {
            return error(401, "Bitte anmelden.");
        }
        if (e.isPermissionDenied() || e.status() < 500) {
            return error(e.isPermissionDenied() ? 403 : 400, DbErrorMessages.german(e));
        }
        LOG.error("Supabase error", e);
        return error(502, DbErrorMessages.german(e));
    }

    @ServerExceptionMapper
    public Response unreachable(UncheckedIOException e) {
        LOG.error("Supabase unreachable", e);
        return error(502, "Die Datenbank ist gerade nicht erreichbar.");
    }

    @ServerExceptionMapper
    public Response invalid(IllegalArgumentException e) {
        return error(400, e.getMessage());
    }

    static Response error(int status, String reason) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("error", true);
        body.put("reason", reason);
        return Response.status(status).type(MediaType.APPLICATION_JSON).entity(body).build();
    }
}
