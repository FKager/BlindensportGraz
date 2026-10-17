package it.a11y.blindensport.webadmin.members;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.github.tomakehurst.wiremock.WireMockServer;
import it.a11y.blindensport.webadmin.supabase.Postgrest;
import it.a11y.blindensport.webadmin.supabase.SupabaseHttp;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

import static com.github.tomakehurst.wiremock.client.WireMock.aResponse;
import static com.github.tomakehurst.wiremock.client.WireMock.anyRequestedFor;
import static com.github.tomakehurst.wiremock.client.WireMock.anyUrl;
import static com.github.tomakehurst.wiremock.client.WireMock.containing;
import static com.github.tomakehurst.wiremock.client.WireMock.delete;
import static com.github.tomakehurst.wiremock.client.WireMock.deleteRequestedFor;
import static com.github.tomakehurst.wiremock.client.WireMock.equalTo;
import static com.github.tomakehurst.wiremock.client.WireMock.okJson;
import static com.github.tomakehurst.wiremock.client.WireMock.patch;
import static com.github.tomakehurst.wiremock.client.WireMock.patchRequestedFor;
import static com.github.tomakehurst.wiremock.client.WireMock.post;
import static com.github.tomakehurst.wiremock.client.WireMock.postRequestedFor;
import static com.github.tomakehurst.wiremock.client.WireMock.urlPathEqualTo;
import static com.github.tomakehurst.wiremock.core.WireMockConfiguration.options;
import static org.junit.jupiter.api.Assertions.assertThrows;

/** Approve / reject of member change requests against a mocked PostgREST. */
class ChangeRequestStoreTest {
    private static final String MEMBER = "44444444-4444-4444-4444-444444444444";
    private static final UUID REVIEWER = UUID.fromString("11111111-1111-1111-1111-111111111111");

    private WireMockServer mock;
    private ChangeRequestStore store;

    @BeforeEach
    void setUp() {
        mock = new WireMockServer(options().dynamicPort());
        mock.start();
        store = new ChangeRequestStore(new Postgrest(new SupabaseHttp(mock.baseUrl(), new ObjectMapper()),
                "anon", () -> "user-token"));
        mock.stubFor(patch(urlPathEqualTo("/rest/v1/members")).willReturn(okJson("[{\"id\":\"" + MEMBER + "\"}]")));
        mock.stubFor(patch(urlPathEqualTo("/rest/v1/member_change_requests")).willReturn(okJson("[{\"id\":\"r1\"}]")));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/member_contacts")).willReturn(aResponse().withStatus(201)));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/rpc/apply_member_private_request")).willReturn(aResponse().withStatus(204)));
        mock.stubFor(delete(urlPathEqualTo("/rest/v1/member_private_requests")).willReturn(okJson("[]")));
    }

    @AfterEach
    void tearDown() {
        mock.stop();
    }

    private ChangeRequestStore.ChangeRequest request() {
        Map<String, String> fields = new LinkedHashMap<>();
        ChangeRequestStore.FIELD_LABELS.keySet().forEach(k -> fields.put(k, ""));
        fields.put("first_name", "Anna");
        fields.put("last_name", "Muster");
        fields.put("city", "Wien");
        return new ChangeRequestStore.ChangeRequest("r1", MEMBER.toUpperCase(), "", Instant.now(), "pending", "", null, fields);
    }

    @Test
    void approveWritesFieldsAppliesPrivateProposalAndMarksReviewed() {
        store.approve(request(), true, REVIEWER);
        mock.verify(patchRequestedFor(urlPathEqualTo("/rest/v1/members"))
                .withQueryParam("id", equalTo("eq." + MEMBER))
                .withHeader("Authorization", equalTo("Bearer user-token"))
                .withRequestBody(containing("\"first_name\":\"Anna\"")));
        mock.verify(postRequestedFor(urlPathEqualTo("/rest/v1/member_contacts"))
                .withRequestBody(containing("\"city\":\"Wien\"")));
        mock.verify(postRequestedFor(urlPathEqualTo("/rest/v1/rpc/apply_member_private_request"))
                .withRequestBody(containing(MEMBER)));
        mock.verify(patchRequestedFor(urlPathEqualTo("/rest/v1/member_change_requests"))
                .withRequestBody(containing("\"status\":\"approved\""))
                .withRequestBody(containing("\"reviewed_by\":\"" + REVIEWER.toString().toUpperCase() + "\"")));
    }

    @Test
    void approveWithoutProposalNeverTouchesProtectedData() {
        store.approve(request(), false, REVIEWER);
        mock.verify(0, postRequestedFor(urlPathEqualTo("/rest/v1/rpc/apply_member_private_request")));
        mock.verify(0, anyRequestedFor(urlPathEqualTo("/rest/v1/member_private")));
    }

    @Test
    void approveFailsWhenTheMemberIsGone() {
        mock.stubFor(patch(urlPathEqualTo("/rest/v1/members")).willReturn(okJson("[]")));
        assertThrows(IllegalArgumentException.class, () -> store.approve(request(), false, REVIEWER));
        mock.verify(0, patchRequestedFor(urlPathEqualTo("/rest/v1/member_change_requests")));
    }

    @Test
    void rejectMarksRejectedAndDropsTheProposal() {
        store.reject(request(), true, REVIEWER);
        mock.verify(patchRequestedFor(urlPathEqualTo("/rest/v1/member_change_requests"))
                .withRequestBody(containing("\"status\":\"rejected\"")));
        mock.verify(deleteRequestedFor(urlPathEqualTo("/rest/v1/member_private_requests"))
                .withQueryParam("member_id", equalTo("eq." + MEMBER)));
        mock.verify(0, patchRequestedFor(urlPathEqualTo("/rest/v1/members")));
        mock.verify(0, anyRequestedFor(anyUrl()).withHeader("apikey", equalTo("service")));
    }
}
