package it.a11y.blindensport.webadmin.accounts;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.github.tomakehurst.wiremock.WireMockServer;
import it.a11y.blindensport.webadmin.members.MemberPrivate;
import it.a11y.blindensport.webadmin.members.MemberRecord;
import it.a11y.blindensport.webadmin.supabase.DbErrorMessages;
import it.a11y.blindensport.webadmin.supabase.Postgrest;
import it.a11y.blindensport.webadmin.supabase.SupabaseException;
import it.a11y.blindensport.webadmin.supabase.SupabaseHttp;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import static com.github.tomakehurst.wiremock.client.WireMock.aResponse;
import static com.github.tomakehurst.wiremock.client.WireMock.equalToJson;
import static com.github.tomakehurst.wiremock.client.WireMock.get;
import static com.github.tomakehurst.wiremock.client.WireMock.okJson;
import static com.github.tomakehurst.wiremock.client.WireMock.post;
import static com.github.tomakehurst.wiremock.client.WireMock.postRequestedFor;
import static com.github.tomakehurst.wiremock.client.WireMock.urlPathEqualTo;
import static com.github.tomakehurst.wiremock.core.WireMockConfiguration.options;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AccountServiceTest {
    private static final UUID A = UUID.fromString("aaaaaaaa-0000-0000-0000-000000000001");
    private static final UUID B = UUID.fromString("bbbbbbbb-0000-0000-0000-000000000002");
    private static final String MEMBER = "44444444-4444-4444-4444-444444444444";

    private WireMockServer mock;
    private AccountService service;

    @BeforeEach
    void setUp() {
        mock = new WireMockServer(options().dynamicPort());
        mock.start();
        service = new AccountService(new Postgrest(new SupabaseHttp(mock.baseUrl(), new ObjectMapper()), "anon", () -> "t"));
    }

    @AfterEach
    void tearDown() {
        mock.stop();
    }

    @Test
    void listCombinesProfilesRolesApprovalsAndBlocks() {
        mock.stubFor(get(urlPathEqualTo("/rest/v1/profiles")).willReturn(okJson("[{\"id\":\"" + A
                + "\",\"email\":\"z@x.at\",\"first_name\":\"Zoe\",\"last_name\":\"Zett\",\"created_at\":\"2026-10-01T10:00:00+00:00\"},"
                + "{\"id\":\"" + B + "\",\"email\":\"a@x.at\",\"first_name\":\"Anna\",\"last_name\":\"Alpha\"},"
                + "{\"id\":\"cccccccc-0000-0000-0000-000000000003\",\"email\":\"\",\"first_name\":\"Ohne\",\"last_name\":\"Mail\"}]")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/user_roles")).willReturn(okJson("[{\"user_id\":\"" + A + "\",\"role\":\"admin\"}]")));
        mock.stubFor(get(urlPathEqualTo("/rest/v1/account_approvals")).willReturn(okJson(
                "[{\"user_id\":\"" + B + "\",\"member_id\":\"" + MEMBER + "\",\"approved_at\":\"2026-10-02T10:00:00+00:00\"}]")));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/rpc/blocked_accounts")).willReturn(okJson(
                "[{\"user_id\":\"" + B + "\",\"blocked_until\":\"2126-01-01T00:00:00+00:00\"}]")));
        List<AccountService.Account> accounts = service.all(true);
        assertEquals(2, accounts.size(), "accounts without e-mail are hidden");
        assertEquals("Anna Alpha", accounts.get(0).displayName());
        assertTrue(accounts.get(0).blocked());
        assertEquals(MEMBER.toUpperCase(), accounts.get(0).approval().memberId());
        assertNull(accounts.get(0).role());
        assertTrue(accounts.get(1).hasFullAccess());
        assertFalse(accounts.get(1).blocked());
    }

    @Test
    void rpcsSendTheExpectedParameters() {
        mock.stubFor(post(urlPathEqualTo("/rest/v1/rpc/approve_account")).willReturn(aResponse().withStatus(204)));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/rpc/set_user_role")).willReturn(aResponse().withStatus(204)));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/rpc/create_activation_code")).willReturn(okJson("\"ABCD-EFGH\"")));
        service.approve(A, MEMBER.toUpperCase());
        service.setRole(A, null);
        assertEquals("ABCD-EFGH", service.createActivationCode(A, null));
        mock.verify(postRequestedFor(urlPathEqualTo("/rest/v1/rpc/approve_account"))
                .withRequestBody(equalToJson("{\"target\":\"" + A + "\",\"p_member_id\":\"" + MEMBER + "\"}")));
        mock.verify(postRequestedFor(urlPathEqualTo("/rest/v1/rpc/set_user_role"))
                .withRequestBody(equalToJson("{\"target\":\"" + A + "\",\"new_role\":null}")));
        mock.verify(postRequestedFor(urlPathEqualTo("/rest/v1/rpc/create_activation_code"))
                .withRequestBody(equalToJson("{\"target\":\"" + A + "\",\"p_member_id\":null}")));
        assertThrows(IllegalArgumentException.class, () -> service.setRole(A, "superuser"));
    }

    @Test
    void lastRootGuardBecomesAGermanMessage() {
        mock.stubFor(post(urlPathEqualTo("/rest/v1/rpc/set_user_role")).willReturn(aResponse().withStatus(400)
                .withBody("{\"code\":\"P0001\",\"message\":\"cannot remove the last root account\"}")));
        SupabaseException e = assertThrows(SupabaseException.class, () -> service.setRole(A, "admin"));
        assertEquals("Das letzte Root-Konto kann nicht entfernt werden.", DbErrorMessages.german(e));
    }

    @Test
    void suggestionPrefersEmailThenFullName() {
        var byName = member("1", "Anna", "Alpha", "");
        var byMail = member("2", "Other", "Person", "A@X.at ");
        var account = new AccountService.Account(A, "a@x.at", "anna", "alpha", Instant.now(), null, null, false);
        assertEquals("2", AccountService.suggest(account, List.of(byName, byMail)).orElseThrow().member().id());
        assertTrue(AccountService.suggest(account, List.of(byMail)).orElseThrow().byEmail());
        var noMail = new AccountService.Account(A, "q@x.at", "Anna", "Alpha", Instant.now(), null, null, false);
        assertFalse(AccountService.suggest(noMail, List.of(byName)).orElseThrow().byEmail());
        var noName = new AccountService.Account(A, "q@x.at", "", "Alpha", Instant.now(), null, null, false);
        assertTrue(AccountService.suggest(noName, List.of(byName)).isEmpty());
    }

    private static MemberRecord member(String id, String first, String last, String email) {
        return new MemberRecord(id, first, last, "", "", "", "", email, "", "", Instant.now(), "", "", "", "", "",
                true, MemberPrivate.EMPTY);
    }
}
