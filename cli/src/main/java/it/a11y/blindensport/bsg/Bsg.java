package it.a11y.blindensport.bsg;

import com.fasterxml.jackson.databind.JsonNode;
import picocli.CommandLine;
import picocli.CommandLine.Command;
import picocli.CommandLine.Option;
import picocli.CommandLine.Parameters;
import picocli.CommandLine.ParentCommand;

import java.io.IOException;
import java.io.PrintWriter;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.Callable;

/**
 * bsg — Blindensport Graz on the command line. Works as the owner of a
 * personal token, through the web UI's REST API, so the same rules apply as
 * in the app and the web UI. Exit codes: 0 done, 1 refused or failed,
 * 2 setup or usage problem.
 */
@Command(name = "bsg", mixinStandardHelpOptions = true, version = "bsg 1.0.0",
        description = "Blindensport Graz: Konten, Rollen und Mitglieder über die Web-Oberfläche.",
        subcommands = {Bsg.WhoAmI.class, Bsg.Accounts.class, Bsg.Members.class},
        footer = {"", "Token: Umgebungsvariable BSG_TOKEN oder Datei .config/blindensport/token im Benutzerordner.",
                "Ein Token erstellen Sie in der Web-Oberfläche unter \"Persönliche Tokens\"."})
public final class Bsg implements Callable<Integer> {
    @Option(names = "--url", description = "Adresse; Standard: BSG_URL, sonst bs.a11y.it",
            scope = CommandLine.ScopeType.INHERIT)
    String url;

    @Option(names = "--json", description = "Die Antwort des Servers als JSON ausgeben.",
            scope = CommandLine.ScopeType.INHERIT)
    boolean json;

    @CommandLine.Spec
    CommandLine.Model.CommandSpec spec;

    private final Map<String, String> env;
    private final Path home;

    public Bsg(Map<String, String> env, Path home) {
        this.env = env;
        this.home = home;
    }

    public static void main(String[] args) {
        System.exit(commandLine(System.getenv(), Path.of(System.getProperty("user.home"))).execute(args));
    }

    /** The configured command line; tests run it with their own environment. */
    public static CommandLine commandLine(Map<String, String> env, Path home) {
        CommandLine cli = new CommandLine(new Bsg(env, home));
        cli.setExecutionExceptionHandler((e, line, parsed) -> {
            line.getErr().println("Fehler: " + e.getMessage());
            return e instanceof Config.Problem ? 2 : 1;
        });
        return cli;
    }

    @Override
    public Integer call() {
        spec.commandLine().usage(spec.commandLine().getOut());
        return 2;
    }

    Api api() {
        // --url (anywhere on the line) wins; else BSG_URL; else the default.
        return new Api(Config.resolve(url, env, home));
    }

    PrintWriter out() {
        return spec.commandLine().getOut();
    }

    void printJson(JsonNode node) {
        try {
            out().println(Api.json().writerWithDefaultPrettyPrinter().writeValueAsString(node));
        } catch (IOException e) {
            throw new IllegalStateException(e);
        }
    }

    static String encode(String segment) {
        return URLEncoder.encode(segment, StandardCharsets.UTF_8).replace("+", "%20");
    }

    // ------------------------------------------------------------------ whoami

    @Command(name = "whoami", mixinStandardHelpOptions = true, description = "Zeigt, wem das Token gehört und was das Konto darf.")
    static final class WhoAmI implements Callable<Integer> {
        @ParentCommand
        Bsg bsg;

        @Override
        public Integer call() {
            JsonNode session = bsg.api().get("/api/session");
            if (bsg.json) {
                bsg.printJson(session);
                return 0;
            }
            List<String> permissions = new ArrayList<>();
            session.path("permissions").forEach(p -> permissions.add(p.asText()));
            bsg.out().println("Angemeldet als " + session.path("email").asText() + ", Rolle "
                    + session.path("role").asText("keine") + ".");
            bsg.out().println("Berechtigungen: " + (permissions.isEmpty() ? "keine" : String.join(", ", permissions)) + ".");
            return 0;
        }
    }

    // ---------------------------------------------------------------- accounts

    @Command(name = "accounts", mixinStandardHelpOptions = true, description = "App-Konten anzeigen und Rollen ändern.",
            subcommands = {Accounts.ListAccounts.class, Accounts.SetRole.class})
    static final class Accounts implements Callable<Integer> {
        @ParentCommand
        Bsg bsg;

        @CommandLine.Spec
        CommandLine.Model.CommandSpec spec;

        @Override
        public Integer call() {
            spec.commandLine().usage(spec.commandLine().getOut());
            return 2;
        }

        static String describe(JsonNode a) {
            String name = (a.path("firstName").asText("") + " " + a.path("lastName").asText("")).trim();
            String role = a.path("role").isNull() || a.path("role").asText("").isEmpty()
                    ? "keine Rolle" : "Rolle " + a.path("role").asText();
            StringBuilder line = new StringBuilder(name.isEmpty() ? a.path("email").asText() : name)
                    .append(" <").append(a.path("email").asText()).append(">: ").append(role);
            line.append(a.path("approved").asBoolean() ? ", freigegeben" : ", nicht freigegeben");
            if (a.path("blocked").asBoolean()) {
                line.append(", gesperrt");
            }
            return line.toString();
        }

        @Command(name = "list", mixinStandardHelpOptions = true, description = "Alle App-Konten mit Rolle, Freigabe und Sperre.")
        static final class ListAccounts implements Callable<Integer> {
            @ParentCommand
            Accounts accounts;

            @Override
            public Integer call() {
                Bsg bsg = accounts.bsg;
                JsonNode all = bsg.api().get("/api/accounts");
                if (bsg.json) {
                    bsg.printJson(all);
                    return 0;
                }
                all.forEach(a -> bsg.out().println(describe(a)));
                bsg.out().println(all.size() == 1 ? "1 Konto." : all.size() + " Konten.");
                return 0;
            }
        }

        @Command(name = "set-role", mixinStandardHelpOptions = true, description = "Ändert die Rolle eines Kontos (braucht roles.assign).")
        static final class SetRole implements Callable<Integer> {
            @ParentCommand
            Accounts accounts;

            @Parameters(index = "0", paramLabel = "KONTO", description = "E-Mail-Adresse oder ID des Kontos.")
            String account;

            @Parameters(index = "1", paramLabel = "ROLLE", description = "member, coach, admin, root, oder none (wartet auf Freigabe).")
            String role;

            @Override
            public Integer call() {
                Bsg bsg = accounts.bsg;
                String wanted = role.trim().toLowerCase(Locale.ROOT);
                if (!List.of("member", "coach", "admin", "root", "none").contains(wanted)) {
                    throw new Config.Problem("Unbekannte Rolle \"" + role + "\": member, coach, admin, root oder none.");
                }
                Map<String, Object> body = new HashMap<>();
                body.put("role", "none".equals(wanted) ? null : wanted);
                JsonNode changed = bsg.api().put("/api/accounts/" + encode(account) + "/role", body);
                if (bsg.json) {
                    bsg.printJson(changed);
                    return 0;
                }
                bsg.out().println("Geändert: " + describe(changed));
                return 0;
            }
        }
    }

    // ----------------------------------------------------------------- members

    @Command(name = "members", mixinStandardHelpOptions = true, description = "Mitglieder der Vereinskartei.",
            subcommands = {Members.ListMembers.class, Members.Import.class})
    static final class Members implements Callable<Integer> {
        @ParentCommand
        Bsg bsg;

        @CommandLine.Spec
        CommandLine.Model.CommandSpec spec;

        @Override
        public Integer call() {
            spec.commandLine().usage(spec.commandLine().getOut());
            return 2;
        }

        /** Fields bsg never shows, even if a server sent them (a token gets them empty anyway). */
        static final List<String> PROTECTED = List.of("svnr", "iban", "birthDate", "lastMedicalExamination");

        @Command(name = "list", mixinStandardHelpOptions = true,
                description = "Mitglieder der Vereinskartei, nach Nachname; ohne geschützte Daten.")
        static final class ListMembers implements Callable<Integer> {
            @ParentCommand
            Members members;

            @Parameters(index = "0", arity = "0..1", paramLabel = "SUCHE",
                    description = "Teil von Name, E-Mail-Adresse oder Mitgliedsnummer.")
            String query;

            @Option(names = "--status", paramLabel = "STATUS", description = "Nur new, active oder delete.")
            String status;

            @Override
            public Integer call() {
                Bsg bsg = members.bsg;
                if (status != null && !List.of("new", "active", "delete").contains(status)) {
                    throw new Config.Problem("Unbekannter Status \"" + status + "\": new, active oder delete.");
                }
                JsonNode all = bsg.api().get("/api/members");
                String q = query == null ? "" : query.trim().toLowerCase(Locale.ROOT);
                var shown = Api.json().createArrayNode();
                for (JsonNode m : all) {
                    String haystack = (m.path("firstName").asText("") + " " + m.path("lastName").asText("") + " "
                            + m.path("email").asText("") + " " + m.path("memberNumber").asText("")).toLowerCase(Locale.ROOT);
                    if ((status == null || status.equals(m.path("status").asText()))
                            && (q.isEmpty() || haystack.contains(q))) {
                        var copy = m.deepCopy();
                        if (copy instanceof com.fasterxml.jackson.databind.node.ObjectNode object) {
                            object.remove(PROTECTED);
                        }
                        shown.add(copy);
                    }
                }
                if (bsg.json) {
                    bsg.printJson(shown);
                    return 0;
                }
                shown.forEach(m -> bsg.out().println(describe(m)));
                bsg.out().println(shown.size() == 1 ? "1 Mitglied." : shown.size() + " Mitglieder.");
                return 0;
            }

            static String describe(JsonNode m) {
                List<String> parts = new ArrayList<>();
                String name = (m.path("lastName").asText("") + " " + m.path("firstName").asText("")).trim();
                String number = m.path("memberNumber").asText("");
                parts.add(number.isEmpty() ? name : name + " (Nr. " + number + ")");
                parts.add(switch (m.path("status").asText("")) {
                    case "new" -> "neu";
                    case "active" -> "aktiv";
                    case "delete" -> "zum Löschen markiert";
                    default -> "Status unbekannt";
                });
                for (String field : List.of("city", "email")) {
                    String value = m.path(field).asText("");
                    if (!value.isEmpty()) {
                        parts.add(value);
                    }
                }
                String phone = m.path("phone").asText("");
                if (!phone.isEmpty()) {
                    parts.add("Tel. " + phone);
                }
                return String.join(", ", parts);
            }
        }

        @Command(name = "import", mixinStandardHelpOptions = true, description = {
                "Liest eine JSON-Liste von Mitgliedern (Form des App-Exports) ein.",
                "Ohne --fill werden passende Einträge (gleiche id) vollständig überschrieben.",
                "Mit --fill werden bei Einträgen mit gleichem Vor- und Nachnamen nur leere Felder ergänzt."})
        static final class Import implements Callable<Integer> {
            @ParentCommand
            Members members;

            @Parameters(index = "0", paramLabel = "DATEI", description = "JSON-Datei mit einer Liste von Mitgliedern.")
            Path file;

            @Option(names = "--fill", description = "Nur leere Felder ergänzen, nichts überschreiben.")
            boolean fill;

            @Override
            public Integer call() {
                Bsg bsg = members.bsg;
                String content;
                try {
                    content = Files.readString(file);
                } catch (IOException e) {
                    throw new Config.Problem("Die Datei " + file + " kann nicht gelesen werden: " + e.getMessage());
                }
                JsonNode list;
                try {
                    list = Api.json().readTree(content);
                } catch (IOException e) {
                    throw new Config.Problem("Die Datei " + file + " ist kein gültiges JSON: " + e.getMessage());
                }
                if (list == null || !list.isArray()) {
                    throw new Config.Problem("Die Datei " + file + " muss eine JSON-Liste von Mitgliedern enthalten.");
                }
                if (list.isEmpty()) {
                    bsg.out().println("Keine Mitglieder in " + file + ".");
                    return 0;
                }
                JsonNode result = bsg.api().post("/api/members/import?mode=" + (fill ? "fill" : "replace"), content);
                if (bsg.json) {
                    bsg.printJson(result);
                } else {
                    result.path("messages").forEach(m -> bsg.out().println(m.asText()));
                    bsg.out().println("Fertig: " + result.path("succeeded").asInt() + " übernommen, "
                            + result.path("failed").asInt() + " fehlgeschlagen, von " + result.path("total").asInt() + ".");
                }
                return result.path("failed").asInt() > 0 ? 1 : 0;
            }
        }
    }
}
