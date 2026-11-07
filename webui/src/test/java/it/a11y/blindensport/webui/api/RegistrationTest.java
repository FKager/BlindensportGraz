package it.a11y.blindensport.webui.api;

import com.github.tomakehurst.wiremock.WireMockServer;
import io.quarkus.test.common.QuarkusTestResource;
import io.quarkus.test.junit.QuarkusTest;
import it.a11y.blindensport.webui.auth.AdminSessions;
import it.a11y.blindensport.webui.auth.SignInException;
import it.a11y.blindensport.webui.club.PublicSchedule;
import it.a11y.blindensport.webui.supabase.GoTrue;
import it.a11y.blindensport.webui.supabase.Supabase;
import jakarta.inject.Inject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import static com.github.tomakehurst.wiremock.client.WireMock.aResponse;
import static com.github.tomakehurst.wiremock.client.WireMock.containing;
import static com.github.tomakehurst.wiremock.client.WireMock.get;
import static com.github.tomakehurst.wiremock.client.WireMock.getRequestedFor;
import static com.github.tomakehurst.wiremock.client.WireMock.matchingJsonPath;
import static com.github.tomakehurst.wiremock.client.WireMock.okJson;
import static com.github.tomakehurst.wiremock.client.WireMock.post;
import static com.github.tomakehurst.wiremock.client.WireMock.postRequestedFor;
import static com.github.tomakehurst.wiremock.client.WireMock.put;
import static com.github.tomakehurst.wiremock.client.WireMock.urlPathEqualTo;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** Registering, signing in with a plain account, and what anyone may see without one. */
@QuarkusTest
@QuarkusTestResource(SupabaseMock.class)
class RegistrationTest {
    private static final UUID PLAIN = UUID.fromString("33333333-3333-3333-3333-333333333333");

    @Inject
    AdminSessions sessions;

    @Inject
    Supabase supabase;

    private WireMockServer mock;

    private static com.github.tomakehurst.wiremock.matching.StringValuePattern wm(String value) {
        return com.github.tomakehurst.wiremock.client.WireMock.equalTo(value);
    }

    @BeforeEach
    void stub() {
        mock = SupabaseMock.server;
        mock.resetAll();
    }

    private void account(String blocked, String rolesJson) {
        mock.stubFor(post(urlPathEqualTo("/auth/v1/token")).willReturn(okJson("{\"access_token\":\"t\",\"refresh_token\":\"r\","
                + "\"expires_in\":3600,\"user\":{\"id\":\"" + PLAIN + "\",\"email\":\"neu@example.org\"}}")));
        mock.stubFor(post(urlPathEqualTo("/auth/v1/logout")).willReturn(aResponse().withStatus(204)));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/rpc/is_blocked")).willReturn(okJson(blocked)));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/user_roles")).willReturn(okJson(rolesJson)));
    }

    @Test
    void registeringAsksSupabaseToLinkBackToTheWebUi() {
        mock.stubFor(post(urlPathEqualTo("/auth/v1/signup")).willReturn(okJson("{}")));
        sessions.register(" Neu@Example.org ", "passwort1234", "Neu", "Person", "10.1.0.1");
        mock.verify(postRequestedFor(urlPathEqualTo("/auth/v1/signup"))
                .withQueryParam("redirect_to", containing("/konto-bestaetigen"))
                .withRequestBody(matchingJsonPath("$.email", wm("neu@example.org")))
                .withRequestBody(matchingJsonPath("$.data.first_name", wm("Neu"))));
    }

    @Test
    void aRefusedRegistrationSaysSo() {
        mock.stubFor(post(urlPathEqualTo("/auth/v1/signup")).willReturn(aResponse().withStatus(422).withBody("{\"code\":\"weak_password\"}")));
        assertEquals(400, assertThrows(SignInException.class,
                () -> sessions.register("a@example.org", "passwort1234", "A", "B", "10.1.0.2")).status());
    }

    @Test
    void registeringIsLimitedPerClient() {
        mock.stubFor(post(urlPathEqualTo("/auth/v1/signup")).willReturn(okJson("{}")));
        for (int i = 0; i < 5; i++) {
            sessions.register("a" + i + "@example.org", "passwort1234", "A", "B", "10.1.0.3");
        }
        assertEquals(429, assertThrows(SignInException.class,
                () -> sessions.register("z@example.org", "passwort1234", "A", "B", "10.1.0.3")).status());
    }

    @Test
    void aPlainAccountSignsInToTheWebPagesWithoutStaffAccess() {
        account("false", "[]");
        var session = sessions.get(sessions.signInAccount("neu@example.org", "pw", "10.1.0.4")).orElseThrow();
        assertFalse(session.canUseWebUi());
    }

    @Test
    void theRestApiStaysForStaff() {
        account("false", "[]");
        assertEquals(403, assertThrows(SignInException.class, () -> sessions.signIn("neu@example.org", "pw", "10.1.0.5")).status());
    }

    @Test
    void aBlockedAccountIsNotLetIn() {
        account("true", "[]");
        assertEquals(403, assertThrows(SignInException.class, () -> sessions.signInAccount("neu@example.org", "pw", "10.1.0.6")).status());
    }

    @Test
    void aResetRequestLinksBackToTheWebUi() {
        mock.stubFor(post(urlPathEqualTo("/auth/v1/recover")).willReturn(okJson("{}")));
        sessions.requestPasswordReset(" Neu@Example.org ", "10.1.0.7");
        mock.verify(postRequestedFor(urlPathEqualTo("/auth/v1/recover"))
                .withQueryParam("redirect_to", containing("/passwort-neu"))
                .withRequestBody(matchingJsonPath("$.email", wm("neu@example.org"))));
    }

    @Test
    void aResetLinkGivesASessionOnce() {
        mock.stubFor(post(urlPathEqualTo("/auth/v1/verify")).willReturn(okJson("{\"access_token\":\"reset-token\"}")));
        assertEquals("reset-token", supabase.auth().recoverySession("abc").orElseThrow());
        mock.stubFor(post(urlPathEqualTo("/auth/v1/verify")).willReturn(aResponse().withStatus(403).withBody("{\"error_code\":\"otp_expired\"}")));
        assertTrue(supabase.auth().recoverySession("abc").isEmpty());
    }

    @Test
    void changingThePasswordTellsASameOneApart() {
        mock.stubFor(put(urlPathEqualTo("/auth/v1/user")).willReturn(okJson("{}")));
        assertEquals(GoTrue.PasswordChange.DONE, supabase.auth().changePassword("t", "passwort1234"));
        mock.stubFor(put(urlPathEqualTo("/auth/v1/user")).willReturn(aResponse().withStatus(422).withBody("{\"error_code\":\"same_password\"}")));
        assertEquals(GoTrue.PasswordChange.SAME_PASSWORD, supabase.auth().changePassword("t", "passwort1234"));
        mock.stubFor(put(urlPathEqualTo("/auth/v1/user")).willReturn(aResponse().withStatus(422).withBody("{\"error_code\":\"weak_password\"}")));
        assertEquals(GoTrue.PasswordChange.REFUSED, supabase.auth().changePassword("t", "passwort1234"));
    }

    @Test
    void confirmingReportsAUsedLink() {
        mock.stubFor(post(urlPathEqualTo("/auth/v1/verify")).willReturn(okJson("{}")));
        assertTrue(supabase.auth().confirmEmail("abc"));
        mock.stubFor(post(urlPathEqualTo("/auth/v1/verify")).willReturn(aResponse().withStatus(403).withBody("{\"code\":\"otp_expired\"}")));
        assertFalse(supabase.auth().confirmEmail("abc"));
    }

    @Test
    void theScheduleHoldsUpcomingEntriesWithoutCancelledOnesAndNoUser() {
        mock.stubFor(get(urlPathEqualTo("/rest/v1/public_schedule")).willReturn(okJson("["
                + "{\"kind\":\"training\",\"title\":\"Torball\",\"location\":\"\",\"city\":\"Graz\",\"start_date\":\"2031-03-10T17:00:00+00:00\",\"end_date\":\"2031-03-10T18:30:00+00:00\",\"status\":\"open\"},"
                + "{\"kind\":\"training\",\"title\":\"Abgesagt\",\"location\":\"Halle\",\"city\":\"\",\"start_date\":\"2031-03-11T17:00:00+00:00\",\"end_date\":\"2031-03-11T18:30:00+00:00\",\"status\":\"cancelled\"},"
                + "{\"kind\":\"tournament\",\"title\":\"Cup\",\"location\":\"Halle\",\"city\":\"Wien\",\"start_date\":\"2031-03-30T08:00:00+00:00\",\"end_date\":\"2031-04-01T16:00:00+00:00\",\"status\":\"planned\"}]")));
        List<PublicSchedule.Entry> entries = PublicSchedule.upcoming(supabase.asAnon(), LocalDate.of(2031, 3, 1));
        assertEquals(List.of("Torball", "Cup"), entries.stream().map(PublicSchedule.Entry::title).toList());
        assertEquals("Graz", entries.get(0).location(), "the city stands in for a missing place");
        assertEquals(LocalDate.of(2031, 4, 1), entries.get(1).lastDay());
        mock.verify(getRequestedFor(urlPathEqualTo("/rest/v1/public_schedule")).withoutHeader("Authorization"));
    }
}
