package it.a11y.blindensport.webui.mcp;

import io.smallrye.config.ConfigMapping;
import io.smallrye.config.WithDefault;

/** {@code webui.mcp.*}: the address MCP clients are given. */
@ConfigMapping(prefix = "webui.mcp")
public interface McpConfig {
    /** This server as the outside world reaches it, without a trailing slash. */
    @WithDefault("https://bs.a11y.it")
    String publicUrl();
}
