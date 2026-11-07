package it.a11y.blindensport.webui.mcp;

import it.a11y.blindensport.webui.auth.SessionExpiredException;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class McpTokensTest {
    @Test
    void onlyTheTokenOpensTheSealedSession() {
        String sealed = McpTokens.seal("token-a", "refresh-token");
        assertEquals("refresh-token", McpTokens.unseal("token-a", sealed));
        assertThrows(SessionExpiredException.class, () -> McpTokens.unseal("token-b", sealed));
    }

    @Test
    void sealedTextHidesTheSessionAndDiffersEachTime() {
        String sealed = McpTokens.seal("token-a", "refresh-token");
        assertFalse(sealed.contains("refresh"));
        assertNotEquals(sealed, McpTokens.seal("token-a", "refresh-token"));
    }

    @Test
    void aTamperedSessionIsRefused() {
        String sealed = McpTokens.seal("token-a", "refresh-token");
        String swapped = sealed.charAt(20) == 'A' ? "B" : "A";
        assertThrows(SessionExpiredException.class,
                () -> McpTokens.unseal("token-a", sealed.substring(0, 20) + swapped + sealed.substring(21)));
    }

    @Test
    void theHashIsNotTheToken() {
        assertFalse(McpTokens.hash("bsg_mcp_abc").contains("abc"));
        assertEquals(McpTokens.hash("x"), McpTokens.hash("x"));
    }
}
