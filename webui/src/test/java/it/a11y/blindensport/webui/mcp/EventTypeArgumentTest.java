package it.a11y.blindensport.webui.mcp;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.github.tomakehurst.wiremock.WireMockServer;
import it.a11y.blindensport.webui.club.ClubStore;
import it.a11y.blindensport.webui.supabase.Postgrest;
import it.a11y.blindensport.webui.supabase.SupabaseHttp;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static com.github.tomakehurst.wiremock.client.WireMock.aResponse;
import static com.github.tomakehurst.wiremock.client.WireMock.get;
import static com.github.tomakehurst.wiremock.client.WireMock.urlPathEqualTo;
import static com.github.tomakehurst.wiremock.core.WireMockConfiguration.options;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

/** The MCP tools' event_type argument: default per kind, must exist and match the kind. */
class EventTypeArgumentTest {
    private WireMockServer mock;
    private ClubStore club;

    @BeforeEach
    void setUp() {
        mock = new WireMockServer(options().dynamicPort());
        mock.start();
        mock.stubFor(get(urlPathEqualTo("/rest/v1/event_types")).willReturn(aResponse().withStatus(200)
                .withHeader("Content-Type", "application/json")
                .withBody("""
                        [{"id":"1","name":"Training","behavior":"training","is_active":true,"sort_order":10},
                         {"id":"2","name":"Turnier","behavior":"tournament","is_active":true,"sort_order":20},
                         {"id":"3","name":"Kurs","behavior":"event","is_active":true,"sort_order":30}]""")));
        club = new ClubStore(new Postgrest(new SupabaseHttp(mock.baseUrl(), new ObjectMapper()), "anon", () -> "t"),
                UUID.randomUUID());
    }

    @AfterEach
    void tearDown() {
        mock.stop();
    }

    @Test
    void blankMeansTheKindsDefault() {
        assertEquals("Training", ClubTools.eventType(club, "training", null));
        assertEquals("Turnier", ClubTools.eventType(club, "tournament", " "));
        assertEquals("", ClubTools.eventType(club, "event", null));
    }

    @Test
    void aListedTypeIsMatchedIgnoringCase() {
        assertEquals("Kurs", ClubTools.eventType(club, "event", " kurs "));
    }

    @Test
    void anUnknownTypeOrOneWithAnotherBehaviourIsRefused() {
        assertThrows(IllegalArgumentException.class, () -> ClubTools.eventType(club, "event", "Weltraumflug"));
        assertThrows(IllegalArgumentException.class, () -> ClubTools.eventType(club, "training", "Kurs"));
    }
}
