package it.a11y.blindensport.webadmin.api;

import it.a11y.blindensport.webadmin.auth.AdminSession;
import it.a11y.blindensport.webadmin.auth.AdminSessions;
import jakarta.inject.Inject;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.core.Cookie;
import jakarta.ws.rs.core.Response;
import org.jboss.resteasy.reactive.server.ServerRequestFilter;

import java.util.Optional;

/**
 * Everything under /api needs a signed-in admin, except signing in itself;
 * the calendar feed has its own token. Changing requests must also carry
 * {@code X-Requested-With: blindensport-admin}: with the SameSite=Strict
 * cookie this blocks cross-site request forgery, because a foreign page
 * can't set custom headers without a CORS preflight, which this server
 * never answers.
 */
public class ApiAuthFilter {
    public static final String COOKIE = "bsg_admin_session";
    public static final String CSRF_HEADER = "X-Requested-With";
    public static final String CSRF_VALUE = "blindensport-admin";
    static final String SESSION_PROPERTY = AdminSession.class.getName();

    @Inject
    AdminSessions sessions;

    @ServerRequestFilter
    public Optional<Response> filter(ContainerRequestContext request) {
        String path = request.getUriInfo().getPath();
        if (!path.equals("/api") && !path.startsWith("/api/")) {
            return Optional.empty();
        }
        if (!"GET".equals(request.getMethod()) && !CSRF_VALUE.equals(request.getHeaderString(CSRF_HEADER))) {
            return Optional.of(ApiExceptionMappers.error(403, "Missing " + CSRF_HEADER + " header."));
        }
        Cookie cookie = request.getCookies().get(COOKIE);
        Optional<AdminSession> session = sessions.get(cookie == null ? null : cookie.getValue());
        session.ifPresent(s -> request.setProperty(SESSION_PROPERTY, s));
        if (path.equals("/api/session")) {
            return Optional.empty();
        }
        if (session.isEmpty()) {
            return Optional.of(ApiExceptionMappers.error(401, "Bitte anmelden."));
        }
        return Optional.empty();
    }
}
