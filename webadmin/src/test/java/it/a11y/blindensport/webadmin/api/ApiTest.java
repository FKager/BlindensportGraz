package it.a11y.blindensport.webadmin.api;

import com.github.tomakehurst.wiremock.WireMockServer;
import io.quarkus.test.common.QuarkusTestResource;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;

import static com.github.tomakehurst.wiremock.client.WireMock.aResponse;
import static com.github.tomakehurst.wiremock.client.WireMock.containing;
import static com.github.tomakehurst.wiremock.client.WireMock.equalToJson;
import static com.github.tomakehurst.wiremock.client.WireMock.get;
import static com.github.tomakehurst.wiremock.client.WireMock.matchingJsonPath;
import static com.github.tomakehurst.wiremock.client.WireMock.okJson;
import static com.github.tomakehurst.wiremock.client.WireMock.post;
import static com.github.tomakehurst.wiremock.client.WireMock.postRequestedFor;
import static com.github.tomakehurst.wiremock.client.WireMock.urlPathEqualTo;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.notNullValue;

/**
 * The REST contract of the Swift server (session, CSRF, members CRUD,
 * protected fields, calendar feed) against a mocked Supabase. Every data
 * call must carry the admin's own token, never the service key.
 */
@QuarkusTest
@QuarkusTestResource(SupabaseMock.class)
class ApiTest {
    private static final String CSRF = "X-Requested-With";
    private static final String CSRF_VALUE = "blindensport-admin";
    private static final UUID ADMIN = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID COACH = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID MEMBER = UUID.fromString("33333333-3333-3333-3333-333333333333");
    private static final String MEMBER_ID = "44444444-4444-4444-4444-444444444444";
    private static final AtomicInteger IP = new AtomicInteger(1);

    private WireMockServer mock;

    private static com.github.tomakehurst.wiremock.matching.StringValuePattern wm(String value) {
        return com.github.tomakehurst.wiremock.client.WireMock.equalTo(value);
    }

    @BeforeEach
    void stubSupabase() {
        mock = SupabaseMock.server;
        mock.resetAll();
        stubAccount("admin@example.org", "admin-token", ADMIN, "admin",
                "\"members.manage\",\"members.private.read\",\"members.private.write\",\"events.manage\"");
        stubAccount("coach@example.org", "coach-token", COACH, "coach", "\"events.manage\",\"teams.manage\"");
        stubAccount("member@example.org", "member-token", MEMBER, "member", "");
        mock.stubFor(post(urlPathEqualTo("/auth/v1/token")).atPriority(10)
                .willReturn(aResponse().withStatus(400).withBody("{\"error\":\"invalid_grant\"}")));
        mock.stubFor(post(urlPathEqualTo("/auth/v1/logout")).willReturn(aResponse().withStatus(204)));
    }

    private void stubAccount(String email, String token, UUID id, String role, String permissions) {
        mock.stubFor(post(urlPathEqualTo("/auth/v1/token")).atPriority(1)
                .withQueryParam("grant_type", wm("password"))
                .withRequestBody(matchingJsonPath("$.email", wm(email)))
                .withRequestBody(matchingJsonPath("$.password", wm("richtig")))
                .willReturn(okJson("{\"access_token\":\"" + token + "\",\"refresh_token\":\"r\",\"expires_in\":3600,"
                        + "\"user\":{\"id\":\"" + id + "\",\"email\":\"" + email + "\"}}")));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/rpc/is_blocked"))
                .withHeader("Authorization", wm("Bearer " + token)).willReturn(okJson("false")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/user_roles"))
                .withHeader("Authorization", wm("Bearer " + token))
                .willReturn(okJson("[{\"role\":\"" + role + "\"}]")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/role_permissions"))
                .withQueryParam("role", wm("eq." + role))
                .willReturn(okJson(permissions.isEmpty() ? "[]"
                        : "[" + String.join(",", java.util.Arrays.stream(permissions.split(","))
                                .map(p -> "{\"permission\":" + p + "}").toList()) + "]")));
    }

    private String signIn(String email) {
        return given().contentType(ContentType.JSON).header(CSRF, CSRF_VALUE)
                .header("X-Forwarded-For", "10.0.0." + IP.incrementAndGet())
                .body("{\"email\":\"" + email + "\",\"password\":\"richtig\"}")
                .when().post("/api/session")
                .then().statusCode(200)
                .extract().cookie("bsg_admin_session");
    }

    private void stubMember() {
        mock.stubFor(get(urlPathEqualTo("/rest/v1/members")).willReturn(okJson("[{\"id\":\"" + MEMBER_ID
                + "\",\"first_name\":\"Anna\",\"last_name\":\"Muster\",\"member_number\":\"7\",\"sport_id\":\"\","
                + "\"default_function\":\"\",\"member_of_gvsc\":true,\"joined_at\":\"2020-01-01T00:00:00+00:00\"}]")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/member_contacts")).willReturn(okJson("[{\"id\":\"" + MEMBER_ID
                + "\",\"street\":\"Gasse 1\",\"zip\":\"8010\",\"city\":\"Graz\",\"country\":\"\",\"email\":\"\","
                + "\"phone\":\"\",\"notes\":\"\",\"gender\":\"w\",\"title\":\"\"}]")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/member_private")).willReturn(okJson("[{\"member_id\":\""
                + MEMBER_ID + "\",\"svnr\":\"1234\",\"iban\":\"AT00\",\"birth_date\":\"1990-05-03\","
                + "\"last_medical_examination\":null}]")));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/members")).willReturn(aResponse().withStatus(201)));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/member_contacts")).willReturn(aResponse().withStatus(201)));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/member_private")).willReturn(aResponse().withStatus(201)));
    }

    @Test
    void wrongPasswordIs401WithGermanReason() {
        given().contentType(ContentType.JSON).header(CSRF, CSRF_VALUE).header("X-Forwarded-For", "10.1.0.1")
                .body("{\"email\":\"admin@example.org\",\"password\":\"falsch\"}")
                .when().post("/api/session")
                .then().statusCode(401).body("error", equalTo(true)).body("reason", equalTo("E-Mail oder Passwort falsch."));
    }

    @Test
    void fiveFailuresLockTheClientOut() {
        for (int i = 0; i < 5; i++) {
            given().contentType(ContentType.JSON).header(CSRF, CSRF_VALUE).header("X-Forwarded-For", "10.2.0.1")
                    .body("{\"email\":\"admin@example.org\",\"password\":\"falsch\"}")
                    .post("/api/session").then().statusCode(401);
        }
        given().contentType(ContentType.JSON).header(CSRF, CSRF_VALUE).header("X-Forwarded-For", "10.2.0.1")
                .body("{\"email\":\"admin@example.org\",\"password\":\"richtig\"}")
                .post("/api/session").then().statusCode(429);
    }

    @Test
    void changingRequestsNeedTheCsrfHeader() {
        given().contentType(ContentType.JSON).body("{\"email\":\"admin@example.org\",\"password\":\"richtig\"}")
                .when().post("/api/session")
                .then().statusCode(403).body("reason", containsString("X-Requested-With"));
    }

    @Test
    void apiNeedsASession() {
        given().when().get("/api/members").then().statusCode(401).body("reason", equalTo("Bitte anmelden."));
        given().when().get("/api/session").then().statusCode(401);
    }

    @Test
    void pendingMemberAccountCannotSignIn() {
        given().contentType(ContentType.JSON).header(CSRF, CSRF_VALUE).header("X-Forwarded-For", "10.3.0.1")
                .body("{\"email\":\"member@example.org\",\"password\":\"richtig\"}")
                .when().post("/api/session")
                .then().statusCode(403);
    }

    @Test
    void sessionInfoAndCookieFlags() {
        given().contentType(ContentType.JSON).header(CSRF, CSRF_VALUE).header("X-Forwarded-For", "10.4.0.1")
                .body("{\"email\":\"Admin@Example.org \",\"password\":\"richtig\"}")
                .when().post("/api/session")
                .then().statusCode(200)
                .header("Set-Cookie", containsString("HttpOnly"))
                .header("Set-Cookie", containsString("SameSite=Strict"))
                .body("email", equalTo("admin@example.org"))
                .body("role", equalTo("admin"))
                .body("permissions", hasItem("members.private.read"));
    }

    @Test
    void adminReadsMembersWithProtectedFieldsUsingOwnToken() {
        stubMember();
        String cookie = signIn("admin@example.org");
        given().cookie("bsg_admin_session", cookie)
                .when().get("/api/members")
                .then().statusCode(200)
                .body("", hasSize(1))
                .body("[0].id", equalTo(MEMBER_ID.toUpperCase()))
                .body("[0].city", equalTo("Graz"))
                .body("[0].svnr", equalTo("1234"))
                .body("[0].birthDate", equalTo("1990-05-03T00:00:00Z"))
                .body("[0].joinedAt", equalTo("2020-01-01T00:00:00Z"))
                .body("[0]", not(org.hamcrest.Matchers.hasKey("lastMedicalExamination")));
        mock.verify(com.github.tomakehurst.wiremock.client.WireMock.getRequestedFor(urlPathEqualTo("/rest/v1/members"))
                .withHeader("Authorization", wm("Bearer admin-token"))
                .withHeader("apikey", wm("test-anon-key")));
    }

    @Test
    void coachHasNoMemberAccess() {
        String cookie = signIn("coach@example.org");
        given().cookie("bsg_admin_session", cookie)
                .when().get("/api/members")
                .then().statusCode(403).body("reason", equalTo("Keine Berechtigung (members.manage)."));
    }

    @Test
    void putWithNullClearsTheBirthDate() {
        stubMember();
        String cookie = signIn("admin@example.org");
        given().cookie("bsg_admin_session", cookie).header(CSRF, CSRF_VALUE).contentType(ContentType.JSON)
                .body("{\"firstName\":\"Anna\",\"lastName\":\"Muster\",\"birthDate\":null}")
                .when().put("/api/members/" + MEMBER_ID.toUpperCase())
                .then().statusCode(200)
                .body("svnr", equalTo("1234"))
                .body("", not(org.hamcrest.Matchers.hasKey("birthDate")));
        mock.verify(postRequestedFor(urlPathEqualTo("/rest/v1/member_private"))
                .withQueryParam("on_conflict", wm("member_id"))
                .withRequestBody(equalToJson("[{\"member_id\":\"" + MEMBER_ID + "\",\"svnr\":\"1234\",\"iban\":\"AT00\","
                        + "\"birth_date\":null,\"last_medical_examination\":null,\"updated_by\":\"" + ADMIN + "\"}]")));
    }

    @Test
    void putWithoutPrivateFieldsLeavesMemberPrivateAlone() {
        stubMember();
        String cookie = signIn("admin@example.org");
        given().cookie("bsg_admin_session", cookie).header(CSRF, CSRF_VALUE).contentType(ContentType.JSON)
                .body("{\"firstName\":\"Anna\",\"lastName\":\"Neu\",\"city\":\"Wien\"}")
                .when().put("/api/members/" + MEMBER_ID)
                .then().statusCode(200).body("lastName", equalTo("Neu")).body("svnr", equalTo("1234"));
        mock.verify(0, postRequestedFor(urlPathEqualTo("/rest/v1/member_private")));
        mock.verify(postRequestedFor(urlPathEqualTo("/rest/v1/member_contacts"))
                .withRequestBody(containing("\"city\":\"Wien\"")));
    }

    @Test
    void unknownMemberIs404() {
        mock.stubFor(get(urlPathEqualTo("/rest/v1/members")).willReturn(okJson("[]")));
        String cookie = signIn("admin@example.org");
        given().cookie("bsg_admin_session", cookie).header(CSRF, CSRF_VALUE)
                .when().delete("/api/members/" + UUID.randomUUID())
                .then().statusCode(404);
        given().cookie("bsg_admin_session", cookie)
                .when().get("/api/members/not-a-uuid")
                .then().statusCode(404);
    }

    @Test
    void importSkipsBadRowsAndReportsCounts() {
        stubMember();
        String cookie = signIn("admin@example.org");
        given().cookie("bsg_admin_session", cookie).header(CSRF, CSRF_VALUE).contentType(ContentType.JSON)
                .body("[{\"firstName\":\"A\",\"lastName\":\"B\",\"plz\":\"8010\"},{\"firstName\":\"\",\"lastName\":\"X\"},"
                        + "{\"id\":\"nope\",\"firstName\":\"C\",\"lastName\":\"D\"}]")
                .when().post("/api/members/import")
                .then().statusCode(200)
                .body("succeeded", equalTo(1)).body("failed", equalTo(2)).body("total", equalTo(3))
                .body("messages", hasSize(3));
        mock.verify(0, postRequestedFor(urlPathEqualTo("/rest/v1/member_private")));
    }

    @Test
    void signOutEndsTheSession() {
        String cookie = signIn("admin@example.org");
        given().cookie("bsg_admin_session", cookie).header(CSRF, CSRF_VALUE)
                .when().delete("/api/session").then().statusCode(204);
        given().cookie("bsg_admin_session", cookie).when().get("/api/session").then().statusCode(401);
        mock.verify(postRequestedFor(urlPathEqualTo("/auth/v1/logout")));
    }

    @Test
    void calendarFeedUsesServiceKeyAndFiltersByTeam() {
        mock.stubFor(get(urlPathEqualTo("/rest/v1/profiles")).withQueryParam("calendar_token", wm("eq.abc123"))
                .withHeader("apikey", wm("test-service-key"))
                .willReturn(okJson("[{\"id\":\"" + MEMBER + "\"}]")));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/rpc/unblocked_user_ids"))
                .willReturn(okJson("[\"" + MEMBER + "\"]")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/user_roles")).withHeader("apikey", wm("test-service-key"))
                .willReturn(okJson("[{\"role\":\"member\"}]")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/team_memberships"))
                .willReturn(okJson("[{\"team_id\":\"AAAAAAAA-0000-0000-0000-000000000000\"}]")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/events")).withQueryParam("kind", wm("in.(training,tournament)"))
                .willReturn(okJson("[{\"id\":\"e1\",\"title\":\"Eigenes Team\",\"location\":\"Halle\","
                        + "\"start_date\":\"2026-10-20T16:00:00+00:00\",\"end_date\":\"2026-10-20T18:00:00+00:00\","
                        + "\"team_ids\":[\"aaaaaaaa-0000-0000-0000-000000000000\"]},"
                        + "{\"id\":\"e2\",\"title\":\"Fremdes Team\",\"location\":\"\","
                        + "\"start_date\":\"2026-10-21T16:00:00+00:00\",\"end_date\":\"2026-10-21T18:00:00+00:00\","
                        + "\"team_ids\":[\"bbbbbbbb-0000-0000-0000-000000000000\"]}]")));
        given().when().get("/calendar/abc123.ics")
                .then().statusCode(200)
                .contentType(containsString("text/calendar"))
                .body(containsString("UID:E1"))
                .body(containsString("SUMMARY:Eigenes Team"))
                .body(not(containsString("Fremdes Team")));
    }

    @Test
    void calendarFeedHidesUnknownAndMalformedTokens() {
        mock.stubFor(get(urlPathEqualTo("/rest/v1/profiles")).willReturn(okJson("[]")));
        given().when().get("/calendar/abcdef").then().statusCode(404);
        given().when().get("/calendar/x;drop").then().statusCode(404);
    }

    @Test
    void healthEndpointIsUp() {
        given().when().get("/q/health/live").then().statusCode(200).body("status", notNullValue());
    }
}
