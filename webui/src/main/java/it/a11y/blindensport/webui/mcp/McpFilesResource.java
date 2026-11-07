package it.a11y.blindensport.webui.mcp;

import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.core.Response;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

/** {@code GET /mcp-files/{token}}: the one-time link of {@link McpFiles}. The token is the only credential. */
@Path("/mcp-files")
public class McpFilesResource {
    @Inject
    McpFiles files;

    @GET
    @Path("{token}")
    public Response download(@PathParam("token") String token) {
        McpFiles.File file = files.take(token).orElseThrow(NotFoundException::new);
        String encoded = URLEncoder.encode(file.name(), StandardCharsets.UTF_8).replace("+", "%20");
        return Response.ok(file.content(), file.contentType())
                .header("Content-Disposition", "attachment; filename*=UTF-8''" + encoded)
                .header("Cache-Control", "no-store")
                .header("X-Content-Type-Options", "nosniff")
                .build();
    }
}
