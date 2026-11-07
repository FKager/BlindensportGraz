package it.a11y.blindensport.webadmin.mcp;

import io.smallrye.config.ConfigMapping;
import io.smallrye.config.WithDefault;

import java.util.Optional;

/** {@code webadmin.mcp.*}: the addresses MCP clients are told about. */
@ConfigMapping(prefix = "webadmin.mcp")
public interface McpConfig {
    /** This server as the outside world reaches it, without a trailing slash. */
    @WithDefault("https://bs.a11y.it")
    String publicUrl();

    /** The OAuth issuer; empty means {@code <supabase.url>/auth/v1}. */
    Optional<String> oauthIssuer();
}
