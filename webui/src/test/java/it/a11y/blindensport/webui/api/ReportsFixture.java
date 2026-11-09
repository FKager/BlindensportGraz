package it.a11y.blindensport.webui.api;

import com.github.tomakehurst.wiremock.WireMockServer;

import java.util.UUID;

import static com.github.tomakehurst.wiremock.client.WireMock.get;
import static com.github.tomakehurst.wiremock.client.WireMock.matchingJsonPath;
import static com.github.tomakehurst.wiremock.client.WireMock.okJson;
import static com.github.tomakehurst.wiremock.client.WireMock.post;
import static com.github.tomakehurst.wiremock.client.WireMock.urlPathEqualTo;

/**
 * Supabase stubs for the invoicing tests: accounts with and without
 * club.manage / members.private.read, one two-day tournament in Prague with
 * a paid coach and a player, and one paid training in March 2026.
 */
public final class ReportsFixture {
    public static final UUID ADMIN = UUID.fromString("11111111-1111-1111-1111-111111111111");
    public static final UUID TREASURER = UUID.fromString("55555555-5555-5555-5555-555555555555");
    public static final UUID COACH = UUID.fromString("22222222-2222-2222-2222-222222222222");
    public static final String TOURNAMENT = "aaaaaaaa-0000-0000-0000-000000000001";
    static final String COACH_MEMBER = "bbbbbbbb-0000-0000-0000-000000000001";
    static final String PLAYER_MEMBER = "bbbbbbbb-0000-0000-0000-000000000002";

    private ReportsFixture() {
    }

    private static com.github.tomakehurst.wiremock.matching.StringValuePattern wm(String value) {
        return com.github.tomakehurst.wiremock.client.WireMock.equalTo(value);
    }

    /** Resets the mock and stubs the three accounts and the club data. */
    public static void stub(WireMockServer mock) {
        mock.resetAll();
        stubAccount(mock, "admin@example.org", "admin-token", ADMIN, "admin",
                "\"club.manage\",\"members.private.read\",\"events.manage\"");
        stubAccount(mock, "kassa@example.org", "kassa-token", TREASURER, "kassa", "\"club.manage\",\"events.manage\"");
        stubAccount(mock, "coach@example.org", "coach-token", COACH, "coach", "\"events.manage\",\"teams.manage\"");
        stubClubData(mock);
    }

    private static void stubAccount(WireMockServer mock, String email, String token, UUID id, String role, String permissions) {
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
                .willReturn(okJson("[" + String.join(",", java.util.Arrays.stream(permissions.split(","))
                        .map(p -> "{\"permission\":" + p + "}").toList()) + "]")));
    }

    private static void stubClubData(WireMockServer mock) {
        mock.stubFor(get(urlPathEqualTo("/rest/v1/events")).willReturn(okJson("[" + event(TOURNAMENT, "tournament",
                "Cup/Prag", "2026-05-29T07:00:00+00:00", "2026-05-30T16:00:00+00:00", "Prag", "Tschechien") + ","
                + event("aaaaaaaa-0000-0000-0000-000000000002", "training", "Torball", "2026-03-03T17:00:00+00:00",
                "2026-03-03T19:00:00+00:00", "Graz", "") + "]")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/attendances")).willReturn(okJson("["
                + attendance("c1", TOURNAMENT, "cccccccc-0000-0000-0000-000000000001", 100) + ","
                + attendance("c2", TOURNAMENT, "cccccccc-0000-0000-0000-000000000002", null) + ","
                + attendance("c3", "aaaaaaaa-0000-0000-0000-000000000002", "cccccccc-0000-0000-0000-000000000001", 45)
                + "]")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/attendances")).atPriority(1)
                .withQueryParam("event_id", wm("eq." + TOURNAMENT)).willReturn(okJson("["
                        + attendance("c1", TOURNAMENT, "cccccccc-0000-0000-0000-000000000001", 100) + ","
                        + attendance("c2", TOURNAMENT, "cccccccc-0000-0000-0000-000000000002", null) + "]")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/team_memberships")).willReturn(okJson("["
                + "{\"id\":\"cccccccc-0000-0000-0000-000000000001\",\"team_id\":\"t\",\"member_id\":\"" + COACH_MEMBER
                + "\",\"user_id\":null,\"role\":\"coach\",\"joined_at\":\"2020-01-01T00:00:00+00:00\"},"
                + "{\"id\":\"cccccccc-0000-0000-0000-000000000002\",\"team_id\":\"t\",\"member_id\":\"" + PLAYER_MEMBER
                + "\",\"user_id\":null,\"role\":\"player\",\"joined_at\":\"2020-01-01T00:00:00+00:00\"}]")));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/rpc/account_directory")).willReturn(okJson("[]")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/members")).willReturn(okJson("["
                + member(COACH_MEMBER, "Erika", "Muster") + "," + member(PLAYER_MEMBER, "Zoe", "Zach") + "]")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/member_contacts")).willReturn(okJson("["
                + contact(COACH_MEMBER, "Graz") + "," + contact(PLAYER_MEMBER, "Wien") + "]")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/member_private")).willReturn(okJson("[{\"member_id\":\""
                + COACH_MEMBER + "\",\"svnr\":\"1234\",\"iban\":\"AT00\",\"birth_date\":\"1990-05-03\","
                + "\"last_medical_examination\":null}]")));
    }

    private static String event(String id, String kind, String title, String start, String end, String city,
                                String country) {
        return "{\"id\":\"" + id + "\",\"kind\":\"" + kind + "\",\"title\":\"" + title + "\",\"sport\":\"Torball\","
                + "\"location\":\"\",\"street\":\"\",\"zip\":\"\",\"city\":\"" + city + "\",\"country\":\"" + country
                + "\",\"start_date\":\"" + start + "\",\"end_date\":\"" + end + "\",\"notes\":\"\",\"status\":\"\","
                + "\"team_ids\":[],\"created_by\":\"\"}";
    }

    private static String attendance(String id, String event, String membership, Integer amount) {
        return "{\"id\":\"" + id + "\",\"event_id\":\"" + event + "\",\"membership_id\":\"" + membership
                + "\",\"attended\":true,\"prae_amount\":" + amount + "}";
    }

    private static String member(String id, String first, String last) {
        return "{\"id\":\"" + id + "\",\"first_name\":\"" + first + "\",\"last_name\":\"" + last
                + "\",\"member_number\":\"\",\"sport_id\":\"\",\"default_function\":\"\",\"member_of_gvsc\":true,"
                + "\"joined_at\":\"2020-01-01T00:00:00+00:00\"}";
    }

    private static String contact(String id, String city) {
        return "{\"id\":\"" + id + "\",\"street\":\"Gasse 1\",\"zip\":\"8010\",\"city\":\"" + city + "\","
                + "\"country\":\"\",\"email\":\"\",\"phone\":\"\",\"notes\":\"\",\"gender\":\"\",\"title\":\"\"}";
    }
}
