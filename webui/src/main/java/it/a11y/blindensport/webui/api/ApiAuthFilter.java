package it.a11y.blindensport.webui.api;

import it.a11y.blindensport.webui.auth.Access;
import it.a11y.blindensport.webui.auth.AdminSession;
import it.a11y.blindensport.webui.auth.AdminSessions;
import it.a11y.blindensport.webui.auth.Permission;
import it.a11y.blindensport.webui.mcp.McpIdentity;
import it.a11y.blindensport.webui.mcp.McpUser;
import it.a11y.blindensport.webui.supabase.Supabase;
import jakarta.inject.Inject;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.core.Cookie;
import jakarta.ws.rs.core.Response;
import org.jboss.resteasy.reactive.server.ServerRequestFilter;

import java.util.HashSet;
import java.util.Optional;
import java.util.Set;

/**
 * Everything under /api needs a signed-in admin, except signing in itself;
 * the calendar feed has its own token. Two ways in:
 * <ul>
 *   <li>The session cookie of {@code POST /api/session}. Changing requests
 *       must also carry {@code X-Requested-With: blindensport-admin}: with
 *       the SameSite=Strict cookie this blocks cross-site request forgery,
 *       because a foreign page can't set custom headers without a CORS
 *       preflight, which this server never answers.</li>
 *   <li>A personal token ({@code Authorization: Bearer bsg_mcp_…}, the same
 *       tokens as for MCP), e.g. for the {@code bsg} command line tool. A
 *       browser never sends it by itself, so no forgery header is needed.</li>
 * </ul>
 */
public class ApiAuthFilter {
    public static final String COOKIE = "bsg_admin_session";
    public static final String CSRF_HEADER = "X-Requested-With";
    public static final String CSRF_VALUE = "blindensport-admin";
    static final String SESSION_PROPERTY = AdminSession.class.getName();
    private static final String BEARER = "Bearer ";

    @Inject
    AdminSessions sessions;

    @Inject
    McpIdentity identity;

    @Inject
    Supabase supabase;

    @ServerRequestFilter
    public Optional<Response> filter(ContainerRequestContext request) {
        String path = request.getUriInfo().getPath();
        if (!path.equals("/api") && !path.startsWith("/api/")) {
            return Optional.empty();
        }
        String authorization = request.getHeaderString("Authorization");
        if (authorization != null && authorization.regionMatches(true, 0, BEARER, 0, BEARER.length())) {
            return byToken(request, authorization.substring(BEARER.length()).trim());
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
        if (!session.get().canUseWebUi()) {
            return Optional.of(ApiExceptionMappers.error(403, "Keine Berechtigung."));
        }
        return Optional.empty();
    }

    /** A personal token: who it belongs to, cached for a minute by {@link McpIdentity}. */
    private Optional<Response> byToken(ContainerRequestContext request, String token) {
        McpIdentity.Outcome outcome = identity.resolve(token);
        if (outcome.user() == null) {
            return Optional.of(outcome.refusal() == McpIdentity.Refusal.NO_ACCESS
                    ? ApiExceptionMappers.error(403, "Keine Berechtigung.")
                    : ApiExceptionMappers.error(401, "Token ungültig, abgelaufen oder widerrufen."));
        }
        McpUser user = outcome.user();
        request.setProperty(SESSION_PROPERTY,
                AdminSession.forToken(supabase, user.id(), user.email(), withoutProtectedRead(user.access()),
                        user.accessToken()));
        return Optional.empty();
    }

    /**
     * A token keeps the promise of the token page for the REST API too:
     * protected member data (SVNR, IBAN, birth date, health) is never
     * returned, and nothing is deleted (MembersResource refuses it). Writing
     * protected data, e.g. in an import, still needs members.private.write.
     */
    static Access withoutProtectedRead(Access access) {
        Set<String> permissions = new HashSet<>(access.permissions());
        permissions.remove(Permission.MEMBERS_PRIVATE_READ);
        return new Access(access.role(), Set.copyOf(permissions), access.blocked());
    }
}
