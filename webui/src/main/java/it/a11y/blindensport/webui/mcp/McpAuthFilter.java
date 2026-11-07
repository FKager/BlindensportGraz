package it.a11y.blindensport.webui.mcp;

import io.quarkus.vertx.http.runtime.filters.Filters;
import io.vertx.ext.web.RoutingContext;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.inject.Inject;
import org.jboss.logging.Logger;

/**
 * Everything under /mcp needs a signed-in coach, admin or root. No or a bad
 * token gets the 401 + WWW-Authenticate that starts the client's OAuth sign-in.
 * Runs as a Vert.x filter since the MCP extension's routes aren't JAX-RS.
 */
@ApplicationScoped
public class McpAuthFilter {
    static final String USER = "bsg.mcp.user";
    private static final Logger LOG = Logger.getLogger(McpAuthFilter.class);
    private static final String BEARER = "Bearer ";
    private static final int PRIORITY = 500;

    @Inject
    McpIdentity identity;

    @Inject
    McpConfig config;

    void register(@Observes Filters filters) {
        filters.register(this::handle, PRIORITY);
    }

    private void handle(RoutingContext context) {
        String path = context.normalizedPath();
        if (!"/mcp".equals(path) && !path.startsWith("/mcp/")) {
            context.next();
            return;
        }
        String header = context.request().getHeader("Authorization");
        if (header == null || !header.regionMatches(true, 0, BEARER, 0, BEARER.length())) {
            challenge(context, 401, null);
            return;
        }
        String token = header.substring(BEARER.length()).trim();
        // GoTrue is called over blocking HTTP. The request body waits meanwhile,
        // so it isn't lost before the MCP route's body handler attaches.
        context.request().pause();
        context.vertx().<McpIdentity.Outcome>executeBlocking(() -> identity.resolve(token), false).onComplete(result -> {
            context.request().resume();
            if (result.failed()) {
                LOG.warnf("MCP sign-in check failed: %s", result.cause().getMessage());
                context.response().setStatusCode(503).end();
            } else if (result.result().user() != null) {
                context.put(USER, result.result().user());
                context.next();
            } else if (result.result().refusal() == McpIdentity.Refusal.NO_ACCESS) {
                challenge(context, 403, "insufficient_scope");
            } else {
                challenge(context, 401, "invalid_token");
            }
        });
    }

    private void challenge(RoutingContext context, int status, String error) {
        String metadata = config.publicUrl() + "/.well-known/oauth-protected-resource/mcp";
        context.response().setStatusCode(status)
                .putHeader("WWW-Authenticate", "Bearer resource_metadata=\"" + metadata + "\""
                        + (error == null ? "" : ", error=\"" + error + "\""))
                .end();
    }
}
