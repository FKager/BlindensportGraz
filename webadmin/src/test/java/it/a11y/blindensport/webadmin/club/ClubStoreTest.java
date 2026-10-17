package it.a11y.blindensport.webadmin.club;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.github.tomakehurst.wiremock.WireMockServer;
import it.a11y.blindensport.webadmin.club.ClubModels.Attendance;
import it.a11y.blindensport.webadmin.club.ClubModels.BudgetEntry;
import it.a11y.blindensport.webadmin.supabase.Postgrest;
import it.a11y.blindensport.webadmin.supabase.SupabaseHttp;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

import static com.github.tomakehurst.wiremock.client.WireMock.aResponse;
import static com.github.tomakehurst.wiremock.client.WireMock.containing;
import static com.github.tomakehurst.wiremock.client.WireMock.equalTo;
import static com.github.tomakehurst.wiremock.client.WireMock.matchingJsonPath;
import static com.github.tomakehurst.wiremock.client.WireMock.post;
import static com.github.tomakehurst.wiremock.client.WireMock.postRequestedFor;
import static com.github.tomakehurst.wiremock.client.WireMock.urlPathEqualTo;
import static com.github.tomakehurst.wiremock.core.WireMockConfiguration.options;

/** Row shapes the app's sync expects: lowercase ids, updated_by, PRAE only when attended, positive amounts. */
class ClubStoreTest {
    private static final UUID ADMIN = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private WireMockServer mock;
    private ClubStore store;

    @BeforeEach
    void setUp() {
        mock = new WireMockServer(options().dynamicPort());
        mock.start();
        mock.stubFor(post(urlPathEqualTo("/rest/v1/attendances")).willReturn(aResponse().withStatus(201)));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/budget_entries")).willReturn(aResponse().withStatus(201)));
        store = new ClubStore(new Postgrest(new SupabaseHttp(mock.baseUrl(), new ObjectMapper()), "anon", () -> "t"), ADMIN);
    }

    @AfterEach
    void tearDown() {
        mock.stop();
    }

    @Test
    void attendanceDropsPraeWhenAbsent() {
        store.saveAttendance(new Attendance("ABC-1", "e", "m", false, BigDecimal.TEN));
        mock.verify(postRequestedFor(urlPathEqualTo("/rest/v1/attendances"))
                .withQueryParam("on_conflict", equalTo("id"))
                .withRequestBody(matchingJsonPath("$[0].id", equalTo("abc-1")))
                .withRequestBody(containing("\"prae_amount\":null"))
                .withRequestBody(matchingJsonPath("$[0].updated_by", equalTo(ADMIN.toString()))));
    }

    @Test
    void budgetAmountIsStoredPositive() {
        store.saveBudget(new BudgetEntry("b", "eventCost", new BigDecimal("-12.50"), Instant.parse("2026-10-17T10:00:00Z"),
                "", null, store.createdBy()));
        mock.verify(postRequestedFor(urlPathEqualTo("/rest/v1/budget_entries"))
                .withRequestBody(containing("\"amount\":12.50"))
                .withRequestBody(matchingJsonPath("$[0].created_by", equalTo(ADMIN.toString().toUpperCase()))));
    }
}
