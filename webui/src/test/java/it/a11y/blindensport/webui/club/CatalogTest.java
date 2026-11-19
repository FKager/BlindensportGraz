package it.a11y.blindensport.webui.club;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.github.tomakehurst.wiremock.WireMockServer;
import it.a11y.blindensport.webui.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webui.supabase.Postgrest;
import it.a11y.blindensport.webui.supabase.SupabaseHttp;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import static com.github.tomakehurst.wiremock.client.WireMock.absent;
import static com.github.tomakehurst.wiremock.client.WireMock.aResponse;
import static com.github.tomakehurst.wiremock.client.WireMock.equalTo;
import static com.github.tomakehurst.wiremock.client.WireMock.get;
import static com.github.tomakehurst.wiremock.client.WireMock.matchingJsonPath;
import static com.github.tomakehurst.wiremock.client.WireMock.post;
import static com.github.tomakehurst.wiremock.client.WireMock.postRequestedFor;
import static com.github.tomakehurst.wiremock.client.WireMock.urlPathEqualTo;
import static com.github.tomakehurst.wiremock.core.WireMockConfiguration.options;
import static org.junit.jupiter.api.Assertions.assertEquals;

/** Sports and event types (migration 20261119000001) as the web UI reads and writes them. */
class CatalogTest {
    private static final UUID ADMIN = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private WireMockServer mock;
    private ClubStore store;

    @BeforeEach
    void setUp() {
        mock = new WireMockServer(options().dynamicPort());
        mock.start();
        mock.stubFor(post(urlPathEqualTo("/rest/v1/events")).willReturn(aResponse().withStatus(201)));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/sports")).willReturn(aResponse().withStatus(201)));
        mock.stubFor(post(urlPathEqualTo("/rest/v1/rpc/rename_sport")).willReturn(aResponse().withStatus(204)));
        store = new ClubStore(new Postgrest(new SupabaseHttp(mock.baseUrl(), new ObjectMapper()), "anon", () -> "t"), ADMIN);
    }

    @AfterEach
    void tearDown() {
        mock.stop();
    }

    private static ClubEvent event(String kind, String sport, String type) {
        return new ClubEvent("e1", kind, "T", sport, "", "", "", "", "", Instant.parse("2026-11-20T17:00:00Z"),
                Instant.parse("2026-11-20T19:00:00Z"), "", "", null, null, null, List.of(), "", type);
    }

    @Test
    void typeNameFallsBackToTheKindsDefaultAndToOlderPlainEvents() {
        assertEquals("Training", event("training", "Torball", "").typeName());
        assertEquals("Trainingslager", event("training", "Torball", "Trainingslager").typeName());
        assertEquals("Langlaufkurs", event("event", "Langlaufkurs", "").typeName(), "old picker stored it in sport");
        assertEquals("", event("event", "Torball", null).eventType(), "null becomes empty");
    }

    @Test
    void eventTypeIsSentOnlyWhenSet() {
        store.saveEvent(event("training", "Torball", ""));
        mock.verify(postRequestedFor(urlPathEqualTo("/rest/v1/events"))
                .withRequestBody(matchingJsonPath("$[0].event_type", absent())));
        store.saveEvent(event("event", "Ski", "Kurs"));
        mock.verify(postRequestedFor(urlPathEqualTo("/rest/v1/events"))
                .withRequestBody(matchingJsonPath("$[0].event_type", equalTo("Kurs"))));
    }

    @Test
    void namesAreCleanedAndRenameGoesThroughTheServerFunction() {
        assertEquals("Tisch tennis", ClubStore.cleanName("  Tisch \t tennis "));
        store.addSport("  Tischtennis ", 100);
        mock.verify(postRequestedFor(urlPathEqualTo("/rest/v1/sports"))
                .withRequestBody(matchingJsonPath("$[0].name", equalTo("Tischtennis")))
                .withRequestBody(matchingJsonPath("$[0].updated_by", equalTo(ADMIN.toString()))));
        store.renameSport("abc", " Torball  (Halle) ");
        mock.verify(postRequestedFor(urlPathEqualTo("/rest/v1/rpc/rename_sport"))
                .withRequestBody(matchingJsonPath("$.p_id", equalTo("abc")))
                .withRequestBody(matchingJsonPath("$.p_name", equalTo("Torball (Halle)"))));
    }

    @Test
    void pickersFallBackToTheBuiltInSportsWhenTheListCantBeRead() {
        mock.stubFor(get(urlPathEqualTo("/rest/v1/sports")).willReturn(aResponse().withStatus(404)));
        assertEquals(ClubModels.SPORTS, store.sportNames());
    }

    @Test
    void pickersOfferActiveSportsInTheirOrder() {
        mock.stubFor(get(urlPathEqualTo("/rest/v1/sports")).willReturn(aResponse().withStatus(200)
                .withHeader("Content-Type", "application/json")
                .withBody("""
                        [{"id":"1","name":"Torball","is_active":true,"sort_order":10},
                         {"id":"2","name":"Ski","is_active":false,"sort_order":20},
                         {"id":"3","name":"Goalball","is_active":true,"sort_order":30}]""")));
        assertEquals(List.of("Torball", "Goalball"), store.sportNames());
    }

    @Test
    void eventTypeNamesAreFilteredByBehaviour() {
        mock.stubFor(get(urlPathEqualTo("/rest/v1/event_types")).willReturn(aResponse().withStatus(200)
                .withHeader("Content-Type", "application/json")
                .withBody("""
                        [{"id":"1","name":"Training","behavior":"training","is_active":true,"sort_order":10},
                         {"id":"2","name":"Trainingslager","behavior":"training","is_active":true,"sort_order":15},
                         {"id":"3","name":"Kurs","behavior":"event","is_active":true,"sort_order":30}]""")));
        assertEquals(List.of("Training", "Trainingslager"), store.eventTypeNames("training"));
        assertEquals(List.of("Kurs"), store.eventTypeNames("event"));
    }
}
