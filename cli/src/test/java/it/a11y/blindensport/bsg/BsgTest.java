package it.a11y.blindensport.bsg;

import com.github.tomakehurst.wiremock.WireMockServer;
import com.github.tomakehurst.wiremock.core.WireMockConfiguration;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import picocli.CommandLine;

import java.io.IOException;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.PosixFilePermissions;
import java.util.Map;

import static com.github.tomakehurst.wiremock.client.WireMock.aResponse;
import static com.github.tomakehurst.wiremock.client.WireMock.equalTo;
import static com.github.tomakehurst.wiremock.client.WireMock.equalToJson;
import static com.github.tomakehurst.wiremock.client.WireMock.get;
import static com.github.tomakehurst.wiremock.client.WireMock.getRequestedFor;
import static com.github.tomakehurst.wiremock.client.WireMock.okJson;
import static com.github.tomakehurst.wiremock.client.WireMock.post;
import static com.github.tomakehurst.wiremock.client.WireMock.postRequestedFor;
import static com.github.tomakehurst.wiremock.client.WireMock.put;
import static com.github.tomakehurst.wiremock.client.WireMock.putRequestedFor;
import static com.github.tomakehurst.wiremock.client.WireMock.urlEqualTo;
import static com.github.tomakehurst.wiremock.client.WireMock.urlPathEqualTo;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** bsg against a mocked web UI: what it sends, what it prints, and its exit codes. */
class BsgTest {
    private static final String TOKEN = "bsg_mcp_0123456789abcdef";

    private WireMockServer server;
    @TempDir
    Path home;

    private final StringWriter out = new StringWriter();
    private final StringWriter err = new StringWriter();

    @BeforeEach
    void start() {
        server = new WireMockServer(WireMockConfiguration.options().dynamicPort());
        server.start();
    }

    @AfterEach
    void stop() {
        server.stop();
    }

    private int run(Map<String, String> env, String... args) {
        CommandLine cli = Bsg.commandLine(env, home);
        cli.setOut(new PrintWriter(out, true));
        cli.setErr(new PrintWriter(err, true));
        return cli.execute(args);
    }

    private int run(String... args) {
        return run(Map.of("BSG_TOKEN", TOKEN, "BSG_URL", "http://localhost:" + server.port()), args);
    }

    @Test
    void whoamiSendsTheTokenAndPrintsTheAccount() {
        server.stubFor(get("/api/session").willReturn(okJson(
                "{\"email\":\"root@example.org\",\"role\":\"root\",\"permissions\":[\"roles.assign\",\"users.approve\"]}")));

        assertEquals(0, run("whoami"));

        server.verify(getRequestedFor(urlEqualTo("/api/session")).withHeader("Authorization", equalTo("Bearer " + TOKEN)));
        assertTrue(out.toString().contains("Angemeldet als root@example.org, Rolle root."), out.toString());
        assertTrue(out.toString().contains("roles.assign, users.approve"), out.toString());
    }

    @Test
    void accountsAreListedOnePerLine() {
        server.stubFor(get("/api/accounts").willReturn(okJson("[{\"id\":\"a\",\"email\":\"anna@example.org\","
                + "\"firstName\":\"Anna\",\"lastName\":\"Muster\",\"role\":\"member\",\"approved\":true,\"blocked\":false},"
                + "{\"id\":\"b\",\"email\":\"neu@example.org\",\"firstName\":\"\",\"lastName\":\"\",\"role\":null,"
                + "\"approved\":false,\"blocked\":true}]")));

        assertEquals(0, run("accounts", "list"));

        String text = out.toString();
        assertTrue(text.contains("Anna Muster <anna@example.org>: Rolle member, freigegeben"), text);
        assertTrue(text.contains("neu@example.org <neu@example.org>: keine Rolle, nicht freigegeben, gesperrt"), text);
        assertTrue(text.contains("2 Konten."), text);
    }

    @Test
    void setRoleSendsTheRoleForTheEncodedAccount() {
        server.stubFor(put("/api/accounts/anna%40example.org/role").willReturn(okJson("{\"id\":\"a\","
                + "\"email\":\"anna@example.org\",\"firstName\":\"Anna\",\"lastName\":\"Muster\",\"role\":\"coach\","
                + "\"approved\":true,\"blocked\":false}")));

        assertEquals(0, run("accounts", "set-role", "anna@example.org", "Coach"));

        server.verify(putRequestedFor(urlEqualTo("/api/accounts/anna%40example.org/role"))
                .withRequestBody(equalToJson("{\"role\":\"coach\"}")));
        assertTrue(out.toString().contains("Geändert: Anna Muster <anna@example.org>: Rolle coach"), out.toString());
    }

    @Test
    void noneMakesTheAccountPending() {
        server.stubFor(put(urlPathEqualTo("/api/accounts/a/role")).willReturn(okJson("{\"email\":\"x\",\"role\":null}")));

        assertEquals(0, run("accounts", "set-role", "a", "none"));

        server.verify(putRequestedFor(urlEqualTo("/api/accounts/a/role")).withRequestBody(equalToJson("{\"role\":null}")));
    }

    @Test
    void anUnknownRoleIsAUsageProblem() {
        assertEquals(2, run("accounts", "set-role", "a", "kaiser"));
        assertTrue(err.toString().contains("Unbekannte Rolle"), err.toString());
        assertEquals(0, server.getAllServeEvents().size());
    }

    @Test
    void theServersReasonIsShownWhenItRefuses() {
        server.stubFor(put(urlPathEqualTo("/api/accounts/a/role")).willReturn(aResponse().withStatus(403)
                .withHeader("Content-Type", "application/json")
                .withBody("{\"error\":true,\"reason\":\"Keine Berechtigung (roles.assign).\"}")));

        assertEquals(1, run("accounts", "set-role", "a", "coach"));
        assertTrue(err.toString().contains("Keine Berechtigung (roles.assign)."), err.toString());
    }

    @Test
    void anInvalidTokenAsksForANewOne() {
        server.stubFor(get("/api/session").willReturn(aResponse().withStatus(401)
                .withHeader("Content-Type", "application/json").withBody("{\"reason\":\"Token ungültig\"}")));

        assertEquals(1, run("whoami"));
        assertTrue(err.toString().contains("Bitte ein neues erstellen"), err.toString());
    }

    @Test
    void importFillSendsTheFileWithModeFill() throws IOException {
        Path file = home.resolve("roster.json");
        Files.writeString(file, "[{\"firstName\":\"Anna\",\"lastName\":\"Muster\",\"city\":\"Graz\"}]");
        server.stubFor(post(urlPathEqualTo("/api/members/import")).willReturn(okJson(
                "{\"succeeded\":1,\"failed\":0,\"total\":1,\"messages\":[\"Filled Anna Muster (A1): city\"]}")));

        assertEquals(0, run("members", "import", file.toString(), "--fill"));

        server.verify(postRequestedFor(urlEqualTo("/api/members/import?mode=fill"))
                .withRequestBody(equalToJson("[{\"firstName\":\"Anna\",\"lastName\":\"Muster\",\"city\":\"Graz\"}]")));
        assertTrue(out.toString().contains("Filled Anna Muster (A1): city"), out.toString());
        assertTrue(out.toString().contains("Fertig: 1 übernommen, 0 fehlgeschlagen, von 1."), out.toString());
    }

    @Test
    void anImportWithFailedRowsEndsWithExitCode1() throws IOException {
        Path file = home.resolve("roster.json");
        Files.writeString(file, "[{\"firstName\":\"\",\"lastName\":\"\"}]");
        server.stubFor(post(urlPathEqualTo("/api/members/import")).willReturn(okJson(
                "{\"succeeded\":0,\"failed\":1,\"total\":1,\"messages\":[\"Skipped an entry\"]}")));

        assertEquals(1, run("members", "import", file.toString()));
        server.verify(postRequestedFor(urlEqualTo("/api/members/import?mode=replace")));
    }

    @Test
    void aFileThatIsNoListIsRefusedBeforeSending() throws IOException {
        Path file = home.resolve("roster.json");
        Files.writeString(file, "{\"firstName\":\"Anna\"}");

        assertEquals(2, run("members", "import", file.toString()));
        assertEquals(0, server.getAllServeEvents().size());
    }

    @Test
    void jsonPrintsTheServersAnswer() {
        server.stubFor(get("/api/accounts").willReturn(okJson("[{\"email\":\"anna@example.org\"}]")));

        assertEquals(0, run("accounts", "list", "--json"));
        assertTrue(out.toString().contains("\"email\" : \"anna@example.org\""), out.toString());
    }

    // ------------------------------------------------------------ configuration

    @Test
    void withoutATokenItSaysWhereToPutOne() {
        assertEquals(2, run(Map.of(), "whoami"));
        assertTrue(err.toString().contains("Kein Token gefunden"), err.toString());
    }

    /** Unix only: Windows has no such permission bits (a user's profile folder is private there). */
    @Test
    void theTokenFileMustBePrivate() throws IOException {
        org.junit.jupiter.api.Assumptions.assumeTrue(
                java.nio.file.FileSystems.getDefault().supportedFileAttributeViews().contains("posix"));
        Path file = home.resolve(".config/blindensport/token");
        Files.createDirectories(file.getParent());
        Files.writeString(file, TOKEN + "\n");
        Files.setPosixFilePermissions(file, PosixFilePermissions.fromString("rw-r--r--"));

        assertEquals(2, run(Map.of("BSG_URL", "http://localhost:" + server.port()), "whoami"));
        assertTrue(err.toString().contains("chmod 600"), err.toString());

        Files.setPosixFilePermissions(file, PosixFilePermissions.fromString("rw-------"));
        server.stubFor(get("/api/session").willReturn(okJson("{\"email\":\"r@example.org\",\"role\":\"root\",\"permissions\":[]}")));
        assertEquals(0, run(Map.of("BSG_URL", "http://localhost:" + server.port()), "whoami"));
    }

    @Test
    void aSupabaseOrOtherTokenIsRefused() {
        assertEquals(2, run(Map.of("BSG_TOKEN", "eyJhbGciOi.x.y"), "whoami"));
        assertTrue(err.toString().contains("kein persönliches Token"), err.toString());
    }

    @Test
    void plainHttpOnlyForLocalhost() {
        assertEquals(2, run(Map.of("BSG_TOKEN", TOKEN), "--url", "http://bs.a11y.it", "whoami"));
        assertTrue(err.toString().contains("https://"), err.toString());
    }

    @Test
    void theUrlOptionWinsOverTheEnvironment() {
        server.stubFor(get("/api/session").willReturn(okJson("{\"email\":\"r@example.org\",\"role\":\"root\",\"permissions\":[]}")));

        assertEquals(0, run(Map.of("BSG_TOKEN", TOKEN, "BSG_URL", "https://elsewhere.invalid"),
                "whoami", "--url", "http://localhost:" + server.port()));
    }

    /** On Windows (no POSIX permissions) a token file is simply read. */
    @Test
    void aTokenFileIsReadWherePermissionsCantBeChecked() throws IOException {
        Path file = home.resolve(".config/blindensport/token");
        Files.createDirectories(file.getParent());
        Files.writeString(file, TOKEN + "\r\n");
        if (java.nio.file.FileSystems.getDefault().supportedFileAttributeViews().contains("posix")) {
            Files.setPosixFilePermissions(file, PosixFilePermissions.fromString("rw-------"));
        }
        server.stubFor(get("/api/session").willReturn(okJson("{\"email\":\"r@example.org\",\"role\":\"root\",\"permissions\":[]}")));

        assertEquals(0, run(Map.of("BSG_URL", "http://localhost:" + server.port()), "whoami"));
        server.verify(getRequestedFor(urlEqualTo("/api/session")).withHeader("Authorization", equalTo("Bearer " + TOKEN)));
    }

    @Test
    void theMissingTokenHintFitsTheSystem() {
        Path file = Path.of("token");
        String unix = Config.missingTokenMessage(file, true);
        String windows = Config.missingTokenMessage(file, false);

        assertTrue(unix.contains("chmod 600"), unix);
        assertTrue(!windows.contains("chmod"), windows);
        assertTrue(windows.contains("Benutzerordner"), windows);
        assertTrue(windows.contains("Persönliche Tokens"), windows);
    }
}
