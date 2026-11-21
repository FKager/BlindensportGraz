package it.a11y.blindensport.webui.api;

import io.quarkus.test.common.QuarkusTestResource;
import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;

/** /q/openapi describes the REST API the bsg tool uses, and nothing behind a token link. */
@QuarkusTest
@QuarkusTestResource(SupabaseMock.class)
class OpenApiTest {
    @Test
    void theRestApiIsDescribed() {
        given().queryParam("format", "json").get("/q/openapi").then().statusCode(200)
                .body(containsString("/api/accounts/{account}/role"))
                .body(containsString("/api/members/import"))
                .body(containsString("Blindensport Graz REST API"))
                .body(not(containsString("/calendar/")))
                .body(not(containsString("/mcp-files")));
    }
}
