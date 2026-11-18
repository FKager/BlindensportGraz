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
import static com.github.tomakehurst.wiremock.client.WireMock.matchingJsonPath;
import static com.github.tomakehurst.wiremock.client.WireMock.okJson;
import static com.github.tomakehurst.wiremock.client.WireMock.post;
import static com.github.tomakehurst.wiremock.client.WireMock.postRequestedFor;
import static com.github.tomakehurst.wiremock.client.WireMock.urlPathEqualTo;
import static com.github.tomakehurst.wiremock.client.WireMock.urlPathMatching;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.containsString;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** /mcp against a mocked Supabase: who gets in, and what never comes out. */
@QuarkusTest
@QuarkusTestResource(SupabaseMock.class)
class McpServerTest {
    private static final String ADMIN_TOKEN = McpTokens.PREFIX + "admin";
    private static final String MEMBER_TOKEN = McpTokens.PREFIX + "member";
    private static final String OFFICE_TOKEN = McpTokens.PREFIX + "office";
    private static final String KASSA_TOKEN = McpTokens.PREFIX + "kassa";
    private static final String ROOT_TOKEN = McpTokens.PREFIX + "root";
    private static final String MEMBER_ID = "44444444-4444-4444-4444-444444444444";
    private static final UUID ADMIN = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID PLAIN = UUID.fromString("33333333-3333-3333-3333-333333333333");
    private static final UUID OFFICE = UUID.fromString("22222222-2222-2222-2222-222222222222");

    private WireMockServer mock;

    private static com.github.tomakehurst.wiremock.matching.StringValuePattern wm(String value) {
        return com.github.tomakehurst.wiremock.client.WireMock.equalTo(value);
    }

    @BeforeEach
    void stub() {
        mock = SupabaseMock.server;
        mock.resetAll();
        mock.stubFor(post(urlPathEqualTo("/rest/v1/rpc/mcp_token_session")).atPriority(10).willReturn(okJson("[]")));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/rpc/mcp_token_update")).willReturn(okJson("null")));
        account(ADMIN_TOKEN, ADMIN, "admin", "[{\"permission\":\"members.manage\"},{\"permission\":\"events.manage\"}]");
        account(MEMBER_TOKEN, PLAIN, "member", "[]");
        account(OFFICE_TOKEN, OFFICE, "office", "[{\"permission\":\"members.manage\"}]");
        account(KASSA_TOKEN, UUID.fromString("66666666-0000-0000-0000-000000000001"), "kassa",
                "[{\"permission\":\"club.manage\"},{\"permission\":\"events.manage\"}]");
        account(ROOT_TOKEN, UUID.fromString("66666666-0000-0000-0000-000000000002"), "root",
                "[{\"permission\":\"club.manage\"},{\"permission\":\"events.manage\"},"
                        + "{\"permission\":\"members.private.read\"}]");
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

    private void account(String mcpToken, UUID id, String role, String permissions) {
        String refresh = "refresh-" + role;
        String access = "access-" + role;
        mock.stubFor(post(urlPathEqualTo("/rest/v1/rpc/mcp_token_session")).atPriority(1)
                .withRequestBody(matchingJsonPath("$.p_token_hash", wm(McpTokens.hash(mcpToken))))
                .willReturn(okJson("[{\"user_id\":\"" + id + "\",\"sealed_session\":\"" + McpTokens.seal(mcpToken, refresh) + "\"}]")));
        mock.stubFor(post(urlPathEqualTo("/auth/v1/token")).withQueryParam("grant_type", wm("refresh_token"))
                .withRequestBody(matchingJsonPath("$.refresh_token", wm(refresh)))
                .willReturn(okJson("{\"access_token\":\"" + access + "\",\"refresh_token\":\"next-" + role + "\",\"expires_in\":3600,"
                        + "\"user\":{\"id\":\"" + id + "\",\"email\":\"x@example.org\"}}")));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/rpc/is_blocked")).withHeader("Authorization", wm("Bearer " + access))
                .willReturn(okJson("false")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/user_roles")).withHeader("Authorization", wm("Bearer " + access))
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
    void withoutATokenThereIsNoEntry() {
        mcp(null, null, "{}").then().statusCode(401).header("WWW-Authenticate", containsString("Bearer"));
    }

    @Test
    void anUnknownTokenIs401() {
        mcp(McpTokens.PREFIX + "forged", null, "{}").then().statusCode(401);
    }

    @Test
    void aSupabaseTokenIsNoMcpToken() {
        mcp("eyJhbGciOi.payload.signature", null, "{}").then().statusCode(401);
        mock.verify(0, postRequestedFor(urlPathEqualTo("/rest/v1/rpc/mcp_token_session")));
    }

    @Test
    void aRefreshedSessionIsStoredOnlySealed() {
        initialize(ADMIN_TOKEN);
        for (var call : mock.findAll(postRequestedFor(urlPathEqualTo("/rest/v1/rpc/mcp_token_update")))) {
            assertFalse(call.getBodyAsString().contains("next-admin"), call.getBodyAsString());
        }
    }

    @Test
    void aPlainMemberHasNoAccess() {
        mcp(MEMBER_TOKEN, null, "{}").then().statusCode(403);
    }

    @Test
    void theLegacyEndpointIsProtectedToo() {
        given().when().get("/mcp/sse").then().statusCode(401);
    }

    @Test
    void onlyATournamentDocumentCanBeDeleted() {
        String session = initialize(ADMIN_TOKEN);
        String tools = mcp(ADMIN_TOKEN, session, "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}")
                .then().statusCode(200).extract().asString();
        var list = io.restassured.path.json.JsonPath.from(tools);
        List<String> names = list.getList("result.tools.name");
        assertTrue(names.contains("create_prae_forms"), tools);
        assertEquals(List.of("delete_tournament_document"),
                names.stream().filter(n -> n.contains("delete") || n.contains("remove")).toList(), tools);
        List<String> destructive = list.getList("result.tools.findAll { it.annotations.destructiveHint == true }.name");
        assertEquals(List.of("delete_tournament_document"), destructive, tools);
    }

    // ------------------------------------------------- tournament reports

    private static List<String> zipEntries(String url) throws java.io.IOException {
        byte[] zip = given().when().get(url).then().statusCode(200).extract().asByteArray();
        List<String> names = new java.util.ArrayList<>();
        try (var in = new java.util.zip.ZipInputStream(new java.io.ByteArrayInputStream(zip))) {
            for (var e = in.getNextEntry(); e != null; e = in.getNextEntry()) {
                names.add(e.getName());
            }
        }
        return names;
    }

    private static String downloadPath(String result) {
        return result.replaceAll("(?s).*(/mcp-files/[0-9a-f]+).*", "$1");
    }

    @Test
    void aTournamentsReportsComeAsOneZipWithItsDocumentsFirst() throws java.io.IOException {
        it.a11y.blindensport.webui.api.ReportsFixture.stubClubData(mock);
        String session = initialize(ROOT_TOKEN);
        String result = call(ROOT_TOKEN, session, "create_tournament_reports",
                "{\"tournament_id\":\"" + it.a11y.blindensport.webui.api.ReportsFixture.TOURNAMENT + "\"}");
        assertFalse(result.contains("\"isError\":true"), result);
        assertTrue(result.contains("kostz_total"), result);
        assertEquals(List.of("Einladung.pdf", "KostZ.xlsx", "PRAE_Muster_Erika.xlsx", "PRAE-Darstellung_Muster_Erika.xlsx",
                "TeilnehmerInnenliste-Sportler.xlsx", "TeilnehmerInnenliste-Helfer.xlsx"), zipEntries(downloadPath(result)));
        assertFalse(result.contains("AT00"), "no IBAN in the tool result: " + result);
    }

    @Test
    void withoutPrivateReadTheReportsLeaveOutPrae() throws java.io.IOException {
        it.a11y.blindensport.webui.api.ReportsFixture.stubClubData(mock);
        String session = initialize(KASSA_TOKEN);
        String tournament = it.a11y.blindensport.webui.api.ReportsFixture.TOURNAMENT;
        String result = call(KASSA_TOKEN, session, "create_tournament_reports", "{\"tournament_id\":\"" + tournament + "\"}");
        assertTrue(result.contains("prae_note"), result);
        assertEquals(List.of("Einladung.pdf", "KostZ.xlsx", "TeilnehmerInnenliste-Sportler.xlsx",
                "TeilnehmerInnenliste-Helfer.xlsx"), zipEntries(downloadPath(result)));
        mock.verify(0, getRequestedFor(urlPathEqualTo("/rest/v1/member_private")));

        String asked = call(KASSA_TOKEN, session, "create_tournament_reports",
                "{\"tournament_id\":\"" + tournament + "\",\"prae\":true}");
        assertTrue(asked.contains("members.private.read"), asked);
    }

    @Test
    void tournamentReportsNeedClubManage() {
        String session = initialize(ADMIN_TOKEN);
        String result = call(ADMIN_TOKEN, session, "create_tournament_reports",
                "{\"tournament_id\":\"" + TOURNAMENT_ID + "\",\"prae\":false}");
        assertTrue(result.contains("club.manage"), result);
    }

    // ------------------------------------------------ tournament documents

    private static final String TOURNAMENT_ID = "55555555-5555-5555-5555-555555555555";
    private static final String DOCUMENT_ID = "66666666-6666-6666-6666-666666666666";

    private void tournament() {
        mock.stubFor(get(urlPathEqualTo("/rest/v1/events")).willReturn(okJson("[{\"id\":\"" + TOURNAMENT_ID
                + "\",\"kind\":\"tournament\",\"title\":\"Alpencup\",\"sport\":\"Torball\",\"location\":\"\","
                + "\"street\":\"\",\"zip\":\"\",\"city\":\"Graz\",\"country\":\"\","
                + "\"start_date\":\"2026-12-05T08:00:00+00:00\",\"end_date\":\"2026-12-06T17:00:00+00:00\","
                + "\"notes\":\"\",\"status\":\"planned\",\"team_ids\":[],\"created_by\":\"\"}]")));
    }

    private void document() {
        mock.stubFor(get(urlPathEqualTo("/rest/v1/tournament_invitations")).willReturn(okJson("[{\"id\":\"" + DOCUMENT_ID
                + "\",\"tournament_id\":\"" + TOURNAMENT_ID + "\",\"storage_path\":\"" + DOCUMENT_ID + ".txt\","
                + "\"file_name\":\"Einladung.txt\",\"content_type\":\"text/plain\",\"uploaded_by\":\"\","
                + "\"uploaded_at\":\"2026-11-18T10:00:00+00:00\"}]")));
        mock.stubFor(get(urlPathEqualTo("/storage/v1/object/tournament-invitations/" + DOCUMENT_ID + ".txt"))
                .willReturn(aResponse().withStatus(200).withBody("Einladung zum Alpencup am 5. Dezember")));
    }

    @Test
    void aDocumentIsUploadedAsTheUserFileFirst() {
        tournament();
        mock.stubFor(post(urlPathMatching("/storage/v1/object/tournament-invitations/.*\\.pdf"))
                .willReturn(okJson("{\"Key\":\"x\"}")));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/tournament_invitations")).willReturn(aResponse().withStatus(201)));
        String session = initialize(ADMIN_TOKEN);
        String content = java.util.Base64.getEncoder().encodeToString("%PDF-1.4 test".getBytes());
        String result = call(ADMIN_TOKEN, session, "upload_tournament_document", "{\"tournament_id\":\"" + TOURNAMENT_ID
                + "\",\"file_name\":\"Einladung.pdf\",\"content_base64\":\"" + content + "\"}");
        assertFalse(result.contains("\"isError\":true"), result);
        assertTrue(result.contains("Einladung.pdf"), result);
        mock.verify(postRequestedFor(urlPathMatching("/storage/v1/object/tournament-invitations/.*\\.pdf"))
                .withHeader("Authorization", wm("Bearer access-admin"))
                .withHeader("Content-Type", wm("application/pdf")));
        mock.verify(postRequestedFor(urlPathEqualTo("/rest/v1/tournament_invitations"))
                .withRequestBody(matchingJsonPath("$[0].tournament_id", wm(TOURNAMENT_ID)))
                .withRequestBody(matchingJsonPath("$[0].file_name", wm("Einladung.pdf")))
                .withRequestBody(matchingJsonPath("$[0].content_type", wm("application/pdf"))));
    }

    @Test
    void anUnsupportedFileIsRefusedBeforeAnyUpload() {
        tournament();
        String session = initialize(ADMIN_TOKEN);
        String result = call(ADMIN_TOKEN, session, "upload_tournament_document", "{\"tournament_id\":\"" + TOURNAMENT_ID
                + "\",\"file_name\":\"tool.exe\",\"content_base64\":\"AAAA\"}");
        assertTrue(result.contains("\"isError\":true"), result);
        assertTrue(result.contains("nicht unterst"), result);
        assertEquals(0, mock.findAll(postRequestedFor(urlPathMatching("/storage/.*"))).size());
    }

    @Test
    void uploadingNeedsEventsManage() {
        String session = initialize(OFFICE_TOKEN);
        String result = call(OFFICE_TOKEN, session, "upload_tournament_document", "{\"tournament_id\":\"" + TOURNAMENT_ID
                + "\",\"file_name\":\"a.pdf\",\"content_base64\":\"AAAA\"}");
        assertTrue(result.contains("events.manage"), result);
        assertEquals(0, mock.findAll(postRequestedFor(urlPathMatching("/storage/.*"))).size());
    }

    @Test
    void aDocumentComesWithItsTextAndAOneTimeLink() {
        tournament();
        document();
        String session = initialize(ADMIN_TOKEN);
        String listed = call(ADMIN_TOKEN, session, "list_tournament_documents", "{\"tournament_id\":\"" + TOURNAMENT_ID + "\"}");
        assertTrue(listed.contains(DOCUMENT_ID), listed);
        String result = call(ADMIN_TOKEN, session, "get_tournament_document", "{\"document_id\":\"" + DOCUMENT_ID + "\"}");
        assertTrue(result.contains("Einladung zum Alpencup am 5. Dezember"), result);
        String url = result.replaceAll("(?s).*(/mcp-files/[0-9a-f]+).*", "$1");
        given().when().get(url).then().statusCode(200).body(containsString("Alpencup"));
        given().when().get(url).then().statusCode(404);
    }

    @Test
    void deletingRemovesRowAndFile() {
        document();
        mock.stubFor(com.github.tomakehurst.wiremock.client.WireMock.delete(urlPathEqualTo("/rest/v1/tournament_invitations"))
                .willReturn(okJson("[{\"id\":\"" + DOCUMENT_ID + "\"}]")));
        mock.stubFor(com.github.tomakehurst.wiremock.client.WireMock.delete(urlPathEqualTo("/storage/v1/object/tournament-invitations"))
                .willReturn(okJson("[]")));
        String session = initialize(ADMIN_TOKEN);
        String result = call(ADMIN_TOKEN, session, "delete_tournament_document", "{\"document_id\":\"" + DOCUMENT_ID + "\"}");
        assertTrue(result.contains("Einladung.txt"), result);
        mock.verify(com.github.tomakehurst.wiremock.client.WireMock.deleteRequestedFor(
                urlPathEqualTo("/storage/v1/object/tournament-invitations"))
                .withRequestBody(matchingJsonPath("$.prefixes[0]", wm(DOCUMENT_ID + ".txt"))));
    }

    @Test
    void memberResultsHoldNoProtectedData() {
        String session = initialize(ADMIN_TOKEN);
        String result = call(ADMIN_TOKEN, session, "get_member", "{\"member_id\":\"" + MEMBER_ID + "\"}");
        assertTrue(result.contains("Gasse 1"), result);
        for (String field : List.of("svnr", "iban", "birth", "medical", "disability", "consent")) {
            assertFalse(result.toLowerCase().contains(field), field + " in " + result);
        }
        mock.verify(0, getRequestedFor(urlPathEqualTo("/rest/v1/member_private")));
    }

    @Test
    void everyCallRunsAsTheUser() {
        String session = initialize(ADMIN_TOKEN);
        call(ADMIN_TOKEN, session, "list_members", "{}");
        mock.verify(getRequestedFor(urlPathEqualTo("/rest/v1/members")).withHeader("Authorization", wm("Bearer access-admin")));
    }

    @Test
    void aNewMemberStartsAsNewAndNothingProtectedIsWritten() {
        String session = initialize(ADMIN_TOKEN);
        String result = call(ADMIN_TOKEN, session, "create_member", "{\"first_name\":\"Neu\",\"last_name\":\"Mitglied\"}");
        assertTrue(result.contains("\\\"status\\\":\\\"new\\\""), result);
        mock.verify(postRequestedFor(urlPathEqualTo("/rest/v1/members")));
        mock.verify(0, postRequestedFor(urlPathEqualTo("/rest/v1/member_private")));
    }

    @Test
    void withoutThePermissionAToolExplainsItself() {
        String session = initialize(ADMIN_TOKEN);
        String result = call(ADMIN_TOKEN, session, "create_prae_forms", "{\"month\":3,\"year\":2026}");
        assertTrue(result.contains("\"isError\":true"), result);
        assertTrue(result.contains("members.private.read"), result);
    }

    @Test
    void anUnknownDownloadIs404() {
        given().when().get("/mcp-files/unknown").then().statusCode(404);
    }

    @Test
    void anIdThatIsNoUuidNeverReachesTheDatabase() {
        String session = initialize(ADMIN_TOKEN);
        String result = call(ADMIN_TOKEN, session, "get_member", "{\"member_id\":\"x&id=neq.0\"}");
        assertTrue(result.contains("\"isError\":true"), result);
        assertEquals(0, mock.findAll(getRequestedFor(urlPathEqualTo("/rest/v1/members"))).size());
    }
}
