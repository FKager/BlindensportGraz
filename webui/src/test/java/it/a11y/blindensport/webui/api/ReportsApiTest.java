package it.a11y.blindensport.webui.api;

import com.github.tomakehurst.wiremock.WireMockServer;
import io.quarkus.test.common.QuarkusTestResource;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

import static com.github.tomakehurst.wiremock.client.WireMock.get;
import static com.github.tomakehurst.wiremock.client.WireMock.okJson;
import static com.github.tomakehurst.wiremock.client.WireMock.urlPathEqualTo;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasSize;
import static org.junit.jupiter.api.Assertions.assertEquals;

/** /api/reports against a mocked Supabase: permissions, JSON and the files. */
@QuarkusTest
@QuarkusTestResource(SupabaseMock.class)
class ReportsApiTest {
    private static final String TOURNAMENT = ReportsFixture.TOURNAMENT;
    private static final AtomicInteger IP = new AtomicInteger(1);

    private WireMockServer mock;

    private static com.github.tomakehurst.wiremock.matching.StringValuePattern wm(String value) {
        return com.github.tomakehurst.wiremock.client.WireMock.equalTo(value);
    }

    @BeforeEach
    void stubSupabase() {
        mock = SupabaseMock.server;
        ReportsFixture.stub(mock);
    }

    private String signIn(String email) {
        return given().contentType(ContentType.JSON).header("X-Requested-With", "blindensport-admin")
                .header("X-Forwarded-For", "10.9.0." + IP.incrementAndGet())
                .body("{\"email\":\"" + email + "\",\"password\":\"richtig\"}")
                .when().post("/api/session")
                .then().statusCode(200)
                .extract().cookie("bsg_admin_session");
    }

    private static List<String> entries(byte[] zip) throws IOException {
        List<String> names = new ArrayList<>();
        try (ZipInputStream in = new ZipInputStream(new ByteArrayInputStream(zip))) {
            for (ZipEntry e = in.getNextEntry(); e != null; e = in.getNextEntry()) {
                names.add(e.getName());
            }
        }
        return names;
    }

    @Test
    void reportsNeedClubManage() {
        String coach = signIn("coach@example.org");
        given().cookie("bsg_admin_session", coach).when().get("/api/reports/tournaments")
                .then().statusCode(403).body("reason", containsString("club.manage"));
    }

    @Test
    void tournamentSummaryHasKostZPraeAndParticipants() {
        String admin = signIn("admin@example.org");
        given().cookie("bsg_admin_session", admin).when().get("/api/reports/tournaments/" + TOURNAMENT)
                .then().statusCode(200)
                .body("kostz.ort", equalTo("Prag, Tschechien"))
                .body("kostz.days", equalTo(2))
                .body("kostz.total", equalTo(100.0f))
                .body("kostz.people", hasSize(1))
                .body("prae[0].person", equalTo("Erika Muster"))
                .body("teilnehmerSportler.names[0]", equalTo("Zach Zoe"))
                .body("teilnehmerHelfer.names[0]", equalTo("Muster Erika"));
    }

    @Test
    void tournamentBundleIsAZipOfTheChosenParts() throws IOException {
        String admin = signIn("admin@example.org");
        byte[] zip = given().cookie("bsg_admin_session", admin)
                .when().get("/api/reports/tournaments/" + TOURNAMENT + "/sammelabrechnung.zip")
                .then().statusCode(200).contentType("application/zip")
                .header("Content-Disposition", containsString("Sammelabrechnung_Cup-Prag.zip"))
                .extract().asByteArray();
        assertEquals(List.of("KostZ.xlsx", "PRAE_Muster_Erika.xlsx", "PRAE-Darstellung_Muster_Erika.xlsx",
                "TeilnehmerInnenliste-Sportler.xlsx", "TeilnehmerInnenliste-Helfer.xlsx"), entries(zip));

        byte[] noPrae = given().cookie("bsg_admin_session", admin)
                .when().get("/api/reports/tournaments/" + TOURNAMENT + "/sammelabrechnung.zip?prae=none&helfer=false")
                .then().statusCode(200).extract().asByteArray();
        assertEquals(List.of("KostZ.xlsx", "TeilnehmerInnenliste-Sportler.xlsx"), entries(noPrae));
    }

    @Test
    void praeFilesNeedPrivateRead() {
        String kassa = signIn("kassa@example.org");
        given().cookie("bsg_admin_session", kassa)
                .when().get("/api/reports/tournaments/" + TOURNAMENT + "/prae.zip")
                .then().statusCode(403).body("reason", containsString("members.private.read"));
        given().cookie("bsg_admin_session", kassa)
                .when().get("/api/reports/tournaments/" + TOURNAMENT + "/sammelabrechnung.zip?prae=none")
                .then().statusCode(200);
        given().cookie("bsg_admin_session", kassa)
                .when().get("/api/reports/tournaments/" + TOURNAMENT + "/kostz.xlsx")
                .then().statusCode(200)
                .contentType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
    }

    @Test
    void monthCoversOnlyTrainings() {
        String admin = signIn("admin@example.org");
        given().cookie("bsg_admin_session", admin).when().get("/api/reports/months/2026/3")
                .then().statusCode(200)
                .body("title", equalTo("März 2026"))
                .body("kostz.betrifft", equalTo("Torball"))
                .body("kostz.total", equalTo(45.0f))
                .body("prae[0].purpose", equalTo("Torball"));
        given().cookie("bsg_admin_session", admin).when().get("/api/reports/months/2026/13")
                .then().statusCode(400);
    }

    @Test
    void monthOfOneSportCountsOnlyItsTrainings() throws java.io.IOException {
        String admin = signIn("admin@example.org");
        given().cookie("bsg_admin_session", admin).when().get("/api/reports/months/2026/3?sport=Fußball")
                .then().statusCode(200)
                .body("kostz.total", equalTo(0.0f))
                .body("prae.size()", equalTo(0))
                .body("trainingsfrequenzliste.dates.size()", equalTo(0));
        given().cookie("bsg_admin_session", admin).when().get("/api/reports/months/2026/3?sport=Torball")
                .then().statusCode(200)
                .body("kostz.total", equalTo(45.0f))
                .body("trainingsfrequenzliste.dates", equalTo(List.of("2026-03-03")));
        given().cookie("bsg_admin_session", admin)
                .when().get("/api/reports/months/2026/3/trainingsfrequenzliste.xlsx?sport=Torball")
                .then().statusCode(200);
        byte[] zip = given().cookie("bsg_admin_session", admin)
                .when().get("/api/reports/months/2026/3/sammelabrechnung.zip?sport=Torball&kostz=false&prae=none")
                .then().statusCode(200).extract().asByteArray();
        java.util.List<String> names = new java.util.ArrayList<>();
        try (var in = new java.util.zip.ZipInputStream(new java.io.ByteArrayInputStream(zip))) {
            for (var e = in.getNextEntry(); e != null; e = in.getNextEntry()) {
                names.add(e.getName());
            }
        }
        assertEquals(List.of("Trainingsfrequenzliste.xlsx"), names);
    }

    @Test
    void unknownTournamentIs404() {
        mock.stubFor(get(urlPathEqualTo("/rest/v1/events")).atPriority(1)
                .withQueryParam("id", wm("eq.aaaaaaaa-0000-0000-0000-000000000009"))
                .willReturn(okJson("[]")));
        String admin = signIn("admin@example.org");
        given().cookie("bsg_admin_session", admin)
                .when().get("/api/reports/tournaments/aaaaaaaa-0000-0000-0000-000000000009")
                .then().statusCode(404).body("reason", equalTo("Turnier nicht gefunden."));
    }

    @Test
    void trainingsfrequenzlisteListsTheTeamWithAttendance() throws IOException {
        String kassa = signIn("kassa@example.org");
        given().cookie("bsg_admin_session", kassa).when().get("/api/reports/trainingsfrequenzliste")
                .then().statusCode(200).body("$", equalTo(List.of("Torball")));
        given().cookie("bsg_admin_session", kassa)
                .when().get("/api/reports/trainingsfrequenzliste/2026/1?sport=Torball")
                .then().statusCode(200)
                .body("title", equalTo("Torball"))
                .body("teams", equalTo(List.of("Torball Damen")))
                .body("dates", equalTo(List.of("2026-03-03")))
                .body("people[0].lastName", equalTo("Zach"))
                .body("people[0].attended", hasSize(0))
                .body("people[1].function", equalTo("Übungsleiter"))
                .body("people[1].attended", equalTo(List.of("2026-03-03")));
        given().cookie("bsg_admin_session", kassa)
                .when().get("/api/reports/trainingsfrequenzliste/2026/1/trainingsfrequenzliste.xlsx?sport=Torball")
                .then().statusCode(200)
                .header("Content-Disposition", containsString("Torball_H1-2026_Trainingsfrequenzliste.xlsx"));
        given().cookie("bsg_admin_session", kassa)
                .when().get("/api/reports/trainingsfrequenzliste/2026/3?sport=Torball")
                .then().statusCode(400);
        String coach = signIn("coach@example.org");
        given().cookie("bsg_admin_session", coach)
                .when().get("/api/reports/trainingsfrequenzliste/2026/1?sport=Torball")
                .then().statusCode(403);
    }
}
