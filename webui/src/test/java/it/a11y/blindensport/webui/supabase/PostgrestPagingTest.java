package it.a11y.blindensport.webui.supabase;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.github.tomakehurst.wiremock.WireMockServer;
import com.github.tomakehurst.wiremock.core.WireMockConfiguration;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

import static com.github.tomakehurst.wiremock.client.WireMock.absent;
import static com.github.tomakehurst.wiremock.client.WireMock.equalTo;
import static com.github.tomakehurst.wiremock.client.WireMock.get;
import static com.github.tomakehurst.wiremock.client.WireMock.getRequestedFor;
import static com.github.tomakehurst.wiremock.client.WireMock.okJson;
import static com.github.tomakehurst.wiremock.client.WireMock.urlPathEqualTo;
import static it.a11y.blindensport.webui.supabase.Postgrest.eq;
import static it.a11y.blindensport.webui.supabase.Postgrest.limit;
import static it.a11y.blindensport.webui.supabase.Postgrest.order;
import static org.junit.jupiter.api.Assertions.assertEquals;

/**
 * PostgREST cuts every answer at max_rows (1000) without saying so; a read
 * must page until everything is there, or reports silently miss rows.
 */
class PostgrestPagingTest {
    private WireMockServer server;
    private Postgrest db;

    @BeforeEach
    void start() {
        server = new WireMockServer(WireMockConfiguration.options().dynamicPort());
        server.start();
        db = new Postgrest(new SupabaseHttp("http://localhost:" + server.port(), new ObjectMapper()), "anon", () -> "token");
    }

    @AfterEach
    void stop() {
        server.stop();
    }

    /** {@code count} rows with ids a0000000…, in key order from {@code from}. */
    private static String rows(int from, int count) {
        return IntStream.range(from, from + count)
                .mapToObj(i -> "{\"id\":\"" + String.format("a%07d", i) + "\",\"event_id\":\"e\"}")
                .collect(Collectors.joining(",", "[", "]"));
    }

    @Test
    void aReadWithoutOrderPagesAfterTheLastKey() {
        server.stubFor(get(urlPathEqualTo("/rest/v1/attendances")).withQueryParam("id", absent())
                .willReturn(okJson(rows(0, Postgrest.PAGE_SIZE))));
        server.stubFor(get(urlPathEqualTo("/rest/v1/attendances"))
                .withQueryParam("id", equalTo("gt." + String.format("a%07d", Postgrest.PAGE_SIZE - 1)))
                .willReturn(okJson(rows(Postgrest.PAGE_SIZE, 5))));

        var all = db.select("attendances", "event_id", Postgrest.in("event_id", List.of("e")));

        assertEquals(Postgrest.PAGE_SIZE + 5, all.size());
        server.verify(2, getRequestedFor(urlPathEqualTo("/rest/v1/attendances"))
                .withQueryParam("order", equalTo("id.asc"))
                .withQueryParam("limit", equalTo(String.valueOf(Postgrest.PAGE_SIZE)))
                .withQueryParam("select", equalTo("event_id,id"))
                .withQueryParam("event_id", equalTo("in.(e)")));
    }

    @Test
    void anOrderedReadPagesByPositionWithTheKeyBreakingTies() {
        server.stubFor(get(urlPathEqualTo("/rest/v1/events")).withQueryParam("offset", equalTo("0"))
                .willReturn(okJson(rows(0, Postgrest.PAGE_SIZE))));
        // Something was added meanwhile: the last row of page 1 comes again first; it's kept once.
        server.stubFor(get(urlPathEqualTo("/rest/v1/events"))
                .withQueryParam("offset", equalTo(String.valueOf(Postgrest.PAGE_SIZE)))
                .willReturn(okJson(rows(Postgrest.PAGE_SIZE - 1, 3))));

        var all = db.select("events", "*", order("start_date.desc"));

        assertEquals(Postgrest.PAGE_SIZE + 2, all.size());
        server.verify(getRequestedFor(urlPathEqualTo("/rest/v1/events"))
                .withQueryParam("order", equalTo("start_date.desc,id.asc"))
                .withQueryParam("select", equalTo("*")));
    }

    @Test
    void aReadWithALimitIsOneRequestAsAsked() {
        server.stubFor(get(urlPathEqualTo("/rest/v1/role_change_log")).willReturn(okJson(rows(0, 50))));

        var rows = db.select("role_change_log", "id,new_role", order("changed_at.desc"), limit(50));

        assertEquals(50, rows.size());
        server.verify(1, getRequestedFor(urlPathEqualTo("/rest/v1/role_change_log"))
                .withQueryParam("offset", absent()).withQueryParam("order", equalTo("changed_at.desc")));
    }

    @Test
    void tablesWithAnotherKeyPageByThatKey() {
        server.stubFor(get(urlPathEqualTo("/rest/v1/user_roles")).willReturn(okJson("[{\"user_id\":\"u1\",\"role\":\"root\"}]")));

        db.select("user_roles", "role", eq("user_id", "u1"));

        server.verify(getRequestedFor(urlPathEqualTo("/rest/v1/user_roles"))
                .withQueryParam("order", equalTo("user_id.asc")).withQueryParam("select", equalTo("role,user_id")));
    }

    @Test
    void tieBreaksAndKeyColumns() {
        assertEquals("role.asc,permission.asc", Postgrest.withTieBreak("", List.of("role", "permission")));
        assertEquals("start_date.desc,id.asc", Postgrest.withTieBreak("start_date.desc", List.of("id")));
        assertEquals("id.desc", Postgrest.withTieBreak("id.desc", List.of("id")));
        assertEquals("*", Postgrest.withColumns("*", List.of("id")));
        assertEquals("id,name", Postgrest.withColumns("id,name", List.of("id")));
        assertEquals("name,id", Postgrest.withColumns("name", List.of("id")));
    }
}
