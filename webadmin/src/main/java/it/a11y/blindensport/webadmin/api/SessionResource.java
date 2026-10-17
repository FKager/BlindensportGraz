package it.a11y.blindensport.webadmin.api;

import it.a11y.blindensport.webadmin.auth.AdminSession;
import it.a11y.blindensport.webadmin.auth.AdminSessions;
import io.vertx.core.http.HttpServerRequest;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.Cookie;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.NewCookie;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.config.inject.ConfigProperty;

import java.util.List;

/** POST/GET/DELETE /api/session — sign in with a Supabase account, show the current admin, sign out. */
@Path("/api/session")
@Produces(MediaType.APPLICATION_JSON)
public class SessionResource {
    public record Credentials(String email, String password) {
    }

    public record SessionInfo(String email, String role, List<String> permissions) {
        static SessionInfo of(AdminSession session) {
            return new SessionInfo(session.email(), session.role(),
                    session.permissions().stream().sorted().toList());
        }
    }

    @Inject
    AdminSessions sessions;

    @ConfigProperty(name = "webadmin.session-cookie-secure")
    boolean secureCookie;

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    public Response signIn(Credentials credentials, @Context HttpServerRequest http) {
        if (credentials == null) {
            throw new ApiException(400, "E-Mail und Passwort fehlen.");
        }
        String token = sessions.signIn(credentials.email(), credentials.password(), clientAddress(http));
        AdminSession session = sessions.get(token).orElseThrow();
        return Response.ok(SessionInfo.of(session))
                .cookie(cookie(token, (int) AdminSessions.ABSOLUTE_TIMEOUT.toSeconds()))
                .build();
    }

    @GET
    public SessionInfo current(@Context ContainerRequestContext request) {
        return SessionInfo.of(CurrentAdmin.require(request));
    }

    @DELETE
    public Response signOut(@Context ContainerRequestContext request) {
        Cookie cookie = request.getCookies().get(ApiAuthFilter.COOKIE);
        if (cookie != null) {
            sessions.remove(cookie.getValue());
        }
        return Response.noContent().cookie(cookie("", 0)).build();
    }

    private NewCookie cookie(String value, int maxAge) {
        return new NewCookie.Builder(ApiAuthFilter.COOKIE)
                .value(value)
                .path("/")
                .maxAge(maxAge)
                .secure(secureCookie)
                .httpOnly(true)
                .sameSite(NewCookie.SameSite.STRICT)
                .build();
    }

    static String clientAddress(HttpServerRequest http) {
        return AdminSessions.clientKey(http.getHeader("X-Forwarded-For"),
                http.remoteAddress() == null ? null : http.remoteAddress().hostAddress());
    }
}
