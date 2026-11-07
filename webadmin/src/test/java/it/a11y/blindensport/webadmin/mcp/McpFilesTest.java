package it.a11y.blindensport.webadmin.mcp;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class McpFilesTest {
    @Test
    void aLinkWorksOnce() {
        McpFiles files = new McpFiles();
        String token = files.put("a.zip", "application/zip", new byte[] {1});
        assertEquals("a.zip", files.take(token).orElseThrow().name());
        assertTrue(files.take(token).isEmpty());
    }

    @Test
    void unknownTokensGetNothing() {
        McpFiles files = new McpFiles();
        assertTrue(files.take("nope").isEmpty());
        assertTrue(files.take(null).isEmpty());
    }

    @Test
    void tokensAreLong() {
        assertEquals(64, new McpFiles().put("a", "b", new byte[0]).length());
    }
}
