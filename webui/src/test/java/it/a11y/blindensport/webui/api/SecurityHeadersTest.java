package it.a11y.blindensport.webui.api;

import io.quarkus.test.common.QuarkusTestResource;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.response.Response;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

import static io.restassured.RestAssured.given;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Every kind of response carries the security headers from
 * application.properties: Vaadin pages, the REST API, the calendar feed, the
 * MCP endpoint (refused before it reaches the MCP extension) and errors.
 */
@QuarkusTest
@QuarkusTestResource(SupabaseMock.class)
class SecurityHeadersTest {
    @ParameterizedTest
    @ValueSource(strings = {"/login", "/api/session", "/calendar/not-a-token", "/mcp", "/does-not-exist"})
    void everyResponseHasTheSecurityHeaders(String path) {
        Response response = given().redirects().follow(false).get(path);

        assertEquals("max-age=31536000; includeSubDomains", response.header("Strict-Transport-Security"), path);
        assertTrue(response.header("Content-Security-Policy").contains("frame-ancestors 'self'"), path);
        assertEquals("nosniff", response.header("X-Content-Type-Options"), path);
        assertEquals("same-origin", response.header("Referrer-Policy"), path);
    }
}
