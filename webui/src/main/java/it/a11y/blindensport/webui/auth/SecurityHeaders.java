package it.a11y.blindensport.webui.auth;

import io.quarkus.vertx.http.runtime.filters.Filters;
import io.vertx.core.MultiMap;
import io.vertx.ext.web.RoutingContext;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;

import java.util.Map;

/**
 * Security headers on every response, whichever proxy is in front (Traefik
 * on nuc, or Caddy from docker-compose.yml). A Vert.x filter, because
 * {@code quarkus.http.header.*} doesn't reach Vaadin's Undertow responses.
 *
 * <ul>
 * <li>HSTS: browsers ignore it over plain http, so local testing is unaffected.</li>
 * <li>CSP: only framing, {@code <base>}, plugins and form targets. Script and
 *     style rules would need testing against Vaadin's inline bootstrap first.</li>
 * <li>Referrer-Policy: the token URLs ({@code /calendar/…}, {@code /mcp-files/…})
 *     never go to other sites.</li>
 * </ul>
 */
@ApplicationScoped
public class SecurityHeaders {
    /** Before everything else, so responses that filters end early (MCP 401) get them too. */
    private static final int PRIORITY = 1000;

    static final Map<String, String> HEADERS = Map.of(
            "Strict-Transport-Security", "max-age=31536000; includeSubDomains",
            "Content-Security-Policy", "frame-ancestors 'self'; base-uri 'self'; object-src 'none'; form-action 'self'",
            "X-Content-Type-Options", "nosniff",
            "Referrer-Policy", "same-origin");

    void register(@Observes Filters filters) {
        filters.register(this::handle, PRIORITY);
    }

    private void handle(RoutingContext context) {
        context.addHeadersEndHandler(v -> {
            MultiMap headers = context.response().headers();
            HEADERS.forEach(headers::set);
        });
        context.next();
    }
}
