package it.a11y.blindensport.webui.mcp;

import com.github.tomakehurst.wiremock.WireMockServer;
import io.quarkus.test.common.QuarkusTestResource;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.Response;
import it.a11y.blindensport.webui.api.SupabaseMock;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.UUID;

import static com.github.tomakehurst.wiremock.client.WireMock.aResponse;
import static com.github.tomakehurst.wiremock.client.WireMock.get;
import static com.github.tomakehurst.wiremock.client.WireMock.getRequestedFor;
import static com.github.tomakehurst.wiremock.client.WireMock.okJson;
import static com.github.tomakehurst.wiremock.client.WireMock.post;
import static com.github.tomakehurst.wiremock.client.WireMock.postRequestedFor;
import static com.github.tomakehurst.wiremock.client.WireMock.urlPathEqualTo;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.containsString;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** /mcp against a mocked Supabase: who gets in, and what never comes out. */
@QuarkusTest
@QuarkusTestResource(SupabaseMock.class)
class McpServerTest {
    private static final String MEMBER_ID = "44444444-4444-4444-4444-444444444444";
    private static final UUID ADMIN = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID PLAIN = UUID.fromString("33333333-3333-3333-3333-333333333333");

    private WireMockServer mock;

    private static com.github.tomakehurst.wiremock.matching.StringValuePattern wm(String value) {
        return com.github.tomakehurst.wiremock.client.WireMock.equalTo(value);
    }

    @BeforeEach
    void stub() {
        mock = SupabaseMock.server;
        mock.resetAll();
        mock.stubFor(get(urlPathEqualTo("/auth/v1/user")).atPriority(10)
                .willReturn(aResponse().withStatus(401).withBody("{\"code\":\"bad_jwt\"}")));
        account("admin-mcp-token", ADMIN, "admin", "[{\"permission\":\"members.manage\"},{\"permission\":\"events.manage\"}]");
        account("member-mcp-token", PLAIN, "member", "[]");
        mock.stubFor(get(urlPathEqualTo("/rest/v1/members")).willReturn(okJson("[{\"id\":\"" + MEMBER_ID
                + "\",\"first_name\":\"Anna\",\"last_name\":\"Muster\",\"member_number\":\"7\",\"sport_id\":\"\","
                + "\"default_function\":\"\",\"member_of_gvsc\":true,\"joined_at\":\"2020-01-01T00:00:00+00:00\","
                + "\"status\":\"active\"}]")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/member_contacts")).willReturn(okJson("[{\"id\":\"" + MEMBER_ID
                + "\",\"street\":\"Gasse 1\",\"zip\":\"8010\",\"city\":\"Graz\",\"country\":\"\",\"email\":\"\","
                + "\"phone\":\"\",\"notes\":\"\",\"gender\":\"w\",\"title\":\"\"}]")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/team_memberships")).willReturn(okJson("[]")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/teams")).willReturn(okJson("[]")));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/members")).willReturn(aResponse().withStatus(201)));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/member_contacts")).willReturn(aResponse().withStatus(201)));
    }

    private void account(String token, UUID id, String role, String permissions) {
        mock.stubFor(get(urlPathEqualTo("/auth/v1/user")).atPriority(1)
                .withHeader("Authorization", wm("Bearer " + token))
                .willReturn(okJson("{\"id\":\"" + id + "\",\"email\":\"x@example.org\"}")));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/rpc/is_blocked")).withHeader("Authorization", wm("Bearer " + token))
                .willReturn(okJson("false")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/user_roles")).withHeader("Authorization", wm("Bearer " + token))
                .willReturn(okJson("[{\"role\":\"" + role + "\"}]")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/role_permissions")).withQueryParam("role", wm("eq." + role))
                .willReturn(okJson(permissions)));
    }

    private static Response mcp(String token, String session, String body) {
        var request = given().contentType(ContentType.JSON).accept("application/json, text/event-stream").body(body);
        if (token != null) {
            request = request.header("Authorization", "Bearer " + token);
        }
        if (session != null) {
            request = request.header("Mcp-Session-Id", session);
        }
        return request.when().post("/mcp");
    }

    private static String initialize(String token) {
        String session = mcp(token, null, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{"
                + "\"protocolVersion\":\"2025-06-18\",\"capabilities\":{},\"clientInfo\":{\"name\":\"t\",\"version\":\"1\"}}}")
                .then().statusCode(200).extract().header("Mcp-Session-Id");
        mcp(token, session, "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}");
        return session;
    }

    private static String call(String token, String session, String tool, String arguments) {
        return mcp(token, session, "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\""
                + tool + "\",\"arguments\":" + arguments + "}}").then().statusCode(200).extract().asString();
    }

    @Test
    void withoutATokenTheClientIsSentToSignIn() {
        mcp(null, null, "{}").then().statusCode(401)
                .header("WWW-Authenticate", containsString("resource_metadata="))
                .header("WWW-Authenticate", containsString("/.well-known/oauth-protected-resource/mcp"));
    }

    @Test
    void metadataNamesSupabaseAsAuthorizationServer() {
        given().when().get("/.well-known/oauth-protected-resource/mcp").then().statusCode(200)
                .body("resource", org.hamcrest.Matchers.endsWith("/mcp"))
                .body("authorization_servers[0]", org.hamcrest.Matchers.endsWith("/auth/v1"));
    }

    @Test
    void aTokenSupabaseRefusesIs401() {
        mcp("forged", null, "{}").then().statusCode(401).header("WWW-Authenticate", containsString("invalid_token"));
    }

    @Test
    void aPlainMemberHasNoAccess() {
        mcp("member-mcp-token", null, "{}").then().statusCode(403);
    }

    @Test
    void theLegacyEndpointIsProtectedToo() {
        given().when().get("/mcp/sse").then().statusCode(401);
    }

    @Test
    void noToolDeletesAnything() {
        String session = initialize("admin-mcp-token");
        String tools = mcp("admin-mcp-token", session, "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}")
                .then().statusCode(200).extract().asString();
        List<String> names = io.restassured.path.json.JsonPath.from(tools).getList("result.tools.name");
        assertTrue(names.contains("create_prae_forms"), tools);
        assertTrue(names.stream().noneMatch(n -> n.contains("delete") || n.contains("remove")), tools);
        List<Boolean> destructive = io.restassured.path.json.JsonPath.from(tools).getList("result.tools.annotations.destructiveHint");
        assertFalse(destructive.contains(true), tools);
    }

    @Test
    void memberResultsHoldNoProtectedData() {
        String session = initialize("admin-mcp-token");
        String result = call("admin-mcp-token", session, "get_member", "{\"member_id\":\"" + MEMBER_ID + "\"}");
        assertTrue(result.contains("Gasse 1"), result);
        for (String field : List.of("svnr", "iban", "birth", "medical", "disability", "consent")) {
            assertFalse(result.toLowerCase().contains(field), field + " in " + result);
        }
        mock.verify(0, getRequestedFor(urlPathEqualTo("/rest/v1/member_private")));
    }

    @Test
    void everyCallRunsAsTheUser() {
        String session = initialize("admin-mcp-token");
        call("admin-mcp-token", session, "list_members", "{}");
        mock.verify(getRequestedFor(urlPathEqualTo("/rest/v1/members")).withHeader("Authorization", wm("Bearer admin-mcp-token")));
    }

    @Test
    void aNewMemberStartsAsNewAndNothingProtectedIsWritten() {
        String session = initialize("admin-mcp-token");
        String result = call("admin-mcp-token", session, "create_member", "{\"first_name\":\"Neu\",\"last_name\":\"Mitglied\"}");
        assertTrue(result.contains("\\\"status\\\":\\\"new\\\""), result);
        mock.verify(postRequestedFor(urlPathEqualTo("/rest/v1/members")));
        mock.verify(0, postRequestedFor(urlPathEqualTo("/rest/v1/member_private")));
    }

    @Test
    void withoutThePermissionAToolExplainsItself() {
        String session = initialize("admin-mcp-token");
        String result = call("admin-mcp-token", session, "create_prae_forms", "{\"month\":3,\"year\":2026}");
        assertTrue(result.contains("\"isError\":true"), result);
        assertTrue(result.contains("members.private.read"), result);
    }

    @Test
    void anUnknownDownloadIs404() {
        given().when().get("/mcp-files/unknown").then().statusCode(404);
    }

    @Test
    void anIdThatIsNoUuidNeverReachesTheDatabase() {
        String session = initialize("admin-mcp-token");
        String result = call("admin-mcp-token", session, "get_member", "{\"member_id\":\"x&id=neq.0\"}");
        assertTrue(result.contains("\"isError\":true"), result);
        assertEquals(0, mock.findAll(getRequestedFor(urlPathEqualTo("/rest/v1/members"))).size());
    }
}
