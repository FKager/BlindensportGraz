package it.a11y.blindensport.webui.mcp;

import com.github.tomakehurst.wiremock.WireMockServer;
import io.quarkus.test.common.QuarkusTestResource;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import it.a11y.blindensport.webui.api.SupabaseMock;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static com.github.tomakehurst.wiremock.client.WireMock.aResponse;
import static com.github.tomakehurst.wiremock.client.WireMock.get;
import static com.github.tomakehurst.wiremock.client.WireMock.matchingJsonPath;
import static com.github.tomakehurst.wiremock.client.WireMock.okJson;
import static com.github.tomakehurst.wiremock.client.WireMock.post;
import static com.github.tomakehurst.wiremock.client.WireMock.postRequestedFor;
import static com.github.tomakehurst.wiremock.client.WireMock.urlPathEqualTo;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.contains;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasSize;

/**
 * The REST API with a personal token (the MCP tokens), as the {@code bsg}
 * command line tool uses it: who gets in, what they may do, and that the
 * token's stored session is never signed out or refreshed by a request.
 */
@QuarkusTest
@QuarkusTestResource(SupabaseMock.class)
class TokenApiTest {
    private static final String ROOT_TOKEN = McpTokens.PREFIX + "api-root";
    private static final String COACH_TOKEN = McpTokens.PREFIX + "api-coach";
    private static final String MEMBER_TOKEN = McpTokens.PREFIX + "api-member";
    private static final UUID ROOT = UUID.fromString("77777777-0000-0000-0000-000000000001");
    private static final UUID COACH = UUID.fromString("77777777-0000-0000-0000-000000000002");
    private static final UUID MEMBER = UUID.fromString("77777777-0000-0000-0000-000000000003");
    private static final String ANNA = "77777777-0000-0000-0000-0000000000aa";
    private static final String MEMBER_ID = "77777777-0000-0000-0000-0000000000bb";

    private WireMockServer mock;

    @BeforeEach
    void stub() {
        mock = SupabaseMock.server;
        mock.resetAll();
        mock.stubFor(post(urlPathEqualTo("/rest/v1/rpc/mcp_token_session")).atPriority(10).willReturn(okJson("[]")));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/rpc/mcp_token_update")).willReturn(okJson("null")));
        account(ROOT_TOKEN, ROOT, "root", "[{\"permission\":\"roles.assign\"},{\"permission\":\"users.approve\"},"
                + "{\"permission\":\"members.manage\"},{\"permission\":\"members.private.read\"},"
                + "{\"permission\":\"members.private.write\"}]");
        account(COACH_TOKEN, COACH, "coach", "[{\"permission\":\"events.manage\"},{\"permission\":\"teams.manage\"}]");
        account(MEMBER_TOKEN, MEMBER, "member", "[]");

        mock.stubFor(get(urlPathEqualTo("/rest/v1/user_roles")).withQueryParam("select", wm("user_id,role"))
                .willReturn(okJson("[{\"user_id\":\"" + ANNA + "\",\"role\":\"member\"},"
                        + "{\"user_id\":\"" + ROOT + "\",\"role\":\"root\"}]")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/account_approvals")).willReturn(okJson(
                "[{\"user_id\":\"" + ANNA + "\",\"member_id\":\"aaaaaaaa-0000-0000-0000-000000000001\","
                        + "\"approved_at\":\"2026-10-01T10:00:00+00:00\"}]")));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/rpc/blocked_accounts")).willReturn(okJson("[]")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/profiles")).willReturn(okJson(
                "[{\"id\":\"" + ANNA + "\",\"email\":\"anna@example.org\",\"first_name\":\"Anna\",\"last_name\":\"Muster\","
                        + "\"created_at\":\"2026-09-01T10:00:00+00:00\"},"
                        + "{\"id\":\"" + ROOT + "\",\"email\":\"root@example.org\",\"first_name\":\"Root\",\"last_name\":\"Admin\","
                        + "\"created_at\":\"2026-08-01T10:00:00+00:00\"}]")));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/rpc/set_user_role")).willReturn(aResponse().withStatus(204)));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/members")).willReturn(okJson("[{\"id\":\"" + MEMBER_ID
                + "\",\"first_name\":\"Anna\",\"last_name\":\"Muster\",\"member_number\":\"7\",\"sport_id\":\"\","
                + "\"default_function\":\"\",\"member_of_gvsc\":true,\"joined_at\":\"2020-01-01T00:00:00+00:00\","
                + "\"status\":\"delete\"}]")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/member_contacts")).willReturn(okJson("[]")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/member_private")).willReturn(okJson("[{\"member_id\":\"" + MEMBER_ID
                + "\",\"svnr\":\"1234010180\",\"iban\":\"AT611904300234573201\"}]")));
    }

    /** A personal token whose sealed session refreshes to "access-<role>". */
    private void account(String token, UUID id, String role, String permissions) {
        String refresh = "refresh-" + role;
        String access = "access-" + role;
        mock.stubFor(post(urlPathEqualTo("/rest/v1/rpc/mcp_token_session")).atPriority(1)
                .withRequestBody(matchingJsonPath("$.p_token_hash", wm(McpTokens.hash(token))))
                .willReturn(okJson("[{\"user_id\":\"" + id + "\",\"sealed_session\":\"" + McpTokens.seal(token, refresh) + "\"}]")));
        mock.stubFor(post(urlPathEqualTo("/auth/v1/token")).withQueryParam("grant_type", wm("refresh_token"))
                .withRequestBody(matchingJsonPath("$.refresh_token", wm(refresh)))
                .willReturn(okJson("{\"access_token\":\"" + access + "\",\"refresh_token\":\"next-" + role + "\","
                        + "\"expires_in\":3600,\"user\":{\"id\":\"" + id + "\",\"email\":\"" + role + "@example.org\"}}")));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/rpc/is_blocked")).withHeader("Authorization", wm("Bearer " + access))
                .willReturn(okJson("false")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/user_roles")).withQueryParam("user_id", wm("eq." + id))
                .willReturn(okJson("[{\"role\":\"" + role + "\"}]")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/role_permissions")).withQueryParam("role", wm("eq." + role))
                .willReturn(okJson(permissions)));
    }

    private static com.github.tomakehurst.wiremock.matching.StringValuePattern wm(String value) {
        return com.github.tomakehurst.wiremock.client.WireMock.equalTo(value);
    }

    private static io.restassured.specification.RequestSpecification as(String token) {
        return given().header("Authorization", "Bearer " + token);
    }

    @Test
    void aTokenSignsInWithoutACookie() {
        as(ROOT_TOKEN).get("/api/session").then().statusCode(200).body("email", equalTo("root@example.org"));
    }

    @Test
    void anUnknownTokenIsRefused() {
        as(McpTokens.PREFIX + "forged").get("/api/accounts").then().statusCode(401)
                .body("reason", containsString("Token"));
    }

    @Test
    void aPlainMemberHasNoAccess() {
        as(MEMBER_TOKEN).get("/api/accounts").then().statusCode(403);
    }

    @Test
    void accountsNeedAnAccountPermission() {
        as(COACH_TOKEN).get("/api/accounts").then().statusCode(403);
    }

    @Test
    void rootListsTheAccounts() {
        as(ROOT_TOKEN).get("/api/accounts").then().statusCode(200)
                .body("email", contains("root@example.org", "anna@example.org"))
                .body("find { it.email == 'anna@example.org' }.role", equalTo("member"))
                .body("find { it.email == 'anna@example.org' }.approved", equalTo(true));
    }

    /** A token is no cookie a foreign page could ride on, so no forgery header is needed. */
    @Test
    void changingARoleByEmailNeedsNoForgeryHeader() {
        as(ROOT_TOKEN).contentType(ContentType.JSON).body("{\"role\":\"coach\"}")
                .put("/api/accounts/ANNA@example.org/role").then().statusCode(200).body("email", equalTo("anna@example.org"));
        mock.verify(postRequestedFor(urlPathEqualTo("/rest/v1/rpc/set_user_role"))
                .withHeader("Authorization", wm("Bearer access-root"))
                .withRequestBody(matchingJsonPath("$.target", wm(ANNA)))
                .withRequestBody(matchingJsonPath("$.new_role", wm("coach"))));
    }

    @Test
    void anUnknownRoleOrAccountIsRefused() {
        as(ROOT_TOKEN).contentType(ContentType.JSON).body("{\"role\":\"kaiser\"}")
                .put("/api/accounts/" + ANNA + "/role").then().statusCode(400);
        as(ROOT_TOKEN).contentType(ContentType.JSON).body("{\"role\":\"coach\"}")
                .put("/api/accounts/nobody@example.org/role").then().statusCode(404);
        mock.verify(0, postRequestedFor(urlPathEqualTo("/rest/v1/rpc/set_user_role")));
    }

    @Test
    void rolesNeedRolesAssign() {
        as(COACH_TOKEN).contentType(ContentType.JSON).body("{\"role\":\"coach\"}")
                .put("/api/accounts/" + ANNA + "/role").then().statusCode(403);
    }

    /** The token's session is shared by all its requests; one request ending must not sign it out. */
    @Test
    void aRequestNeverSignsTheTokenOut() {
        as(ROOT_TOKEN).get("/api/accounts").then().statusCode(200);
        as(ROOT_TOKEN).get("/api/accounts").then().statusCode(200);
        mock.verify(0, postRequestedFor(urlPathEqualTo("/auth/v1/logout")));
    }

    @Test
    void theImportModeIsChecked() {
        as(ROOT_TOKEN).contentType(ContentType.JSON).body("[]").post("/api/members/import?mode=merge")
                .then().statusCode(400);
        as(ROOT_TOKEN).contentType(ContentType.JSON).body("[]").post("/api/members/import?mode=fill")
                .then().statusCode(200).body("total", equalTo(0)).body("messages", hasSize(0));
    }

    /** The token page promises no protected data; the REST API keeps it even for root. */
    @Test
    void aTokenNeverReadsProtectedData() {
        String body = as(ROOT_TOKEN).get("/api/members").then().statusCode(200).extract().asString();
        org.junit.jupiter.api.Assertions.assertFalse(body.contains("1234010180") || body.contains("AT61"), body);
        mock.verify(0, com.github.tomakehurst.wiremock.client.WireMock.getRequestedFor(urlPathEqualTo("/rest/v1/member_private")));
    }

    @Test
    void aTokenDeletesNothing() {
        as(ROOT_TOKEN).delete("/api/members/" + MEMBER_ID + "?confirm=Anna%20Muster").then().statusCode(403)
                .body("reason", containsString("Token"));
        mock.verify(0, postRequestedFor(urlPathEqualTo("/rest/v1/rpc/delete_member")));
    }
}
