package it.a11y.blindensport.webui.mcp;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.quarkiverse.mcp.server.ToolCallException;
import io.quarkus.vertx.http.runtime.CurrentVertxRequest;
import it.a11y.blindensport.webui.supabase.DbErrorMessages;
import it.a11y.blindensport.webui.supabase.SupabaseException;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.jboss.logging.Logger;

/** The one way into an MCP tool: the signed-in user, German errors, and a log line that holds no data. */
@ApplicationScoped
public class McpToolRunner {
    private static final Logger LOG = Logger.getLogger(McpToolRunner.class);

    @Inject
    CurrentVertxRequest request;

    @Inject
    ObjectMapper json;

    String run(String tool, McpToolSupport.Action action) {
        McpUser user = request.getCurrent() == null ? null : request.getCurrent().get(McpAuthFilter.USER);
        if (user == null) {
            throw new ToolCallException("Nicht angemeldet.");
        }
        LOG.infof("MCP %s by %s", tool, user.id());
        try {
            return json.writeValueAsString(action.run(user));
        } catch (SupabaseException e) {
            LOG.infof("MCP %s refused by the database: %s", tool, e.getMessage());
            throw new ToolCallException(DbErrorMessages.german(e));
        } catch (IllegalArgumentException e) {
            throw new ToolCallException(e.getMessage());
        } catch (JsonProcessingException e) {
            throw new IllegalStateException(e);
        }
    }
}
