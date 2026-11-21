package it.a11y.blindensport.webui.mcp;

import io.quarkiverse.mcp.server.Tool;
import io.quarkiverse.mcp.server.ToolArg;
import it.a11y.blindensport.webui.auth.Permission;
import it.a11y.blindensport.webui.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webui.prae.PraeForm;
import it.a11y.blindensport.webui.prae.PraeService;
import it.a11y.blindensport.webui.reports.ReportService;
import it.a11y.blindensport.webui.reports.Reports;
import it.a11y.blindensport.webui.xlsx.XlsxPatch;
import jakarta.inject.Inject;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

import static it.a11y.blindensport.webui.mcp.McpToolSupport.*;

/**
 * MCP tools for PRAE forms and a tournament's Sammelabrechnung (files as one-time links). The rules of every MCP tool (see {@link McpToolSupport}): it
 * runs as the signed-in person, so RLS and their role decide; protected
 * member fields never appear in a result and can't be written.
 */
public class ReportTools {
    @Inject
    McpToolRunner runner;

    @Inject
    McpFiles files;

    @Inject
    McpConfig config;

    // --------------------------------------------------------------- PRAE

    @Tool(description = "Show which PRAE forms there would be, with amounts per day and legal-cap warnings, without creating files. "
            + "Pass event_id for a tournament or a training (a training's form covers all sessions of that title in the month), "
            + "or month and year for all trainings of a month.",
            annotations = @Tool.Annotations(title = "Preview PRAE", readOnlyHint = true, destructiveHint = false, idempotentHint = true))
    String preview_prae(
            @ToolArg(description = "Tournament or training id", required = false) String event_id,
            @ToolArg(description = "Month, 1 to 12", required = false) Integer month,
            @ToolArg(description = "Year", required = false) Integer year,
            @ToolArg(description = "Only this person's member id", required = false) String member_id) {
        return runner.run("preview_prae", user -> {
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("forms", forms(user, event_id, month, year, member_id, false).stream().map(McpToolSupport::formRow).toList());
            return result;
        });
    }

    @Tool(description = "Create the official PRAE forms and Darstellung as a zip of Excel files, for the same choices as preview_prae. "
            + "The result has summaries and a one-time download_url, valid for 10 minutes. "
            + "The files contain social security numbers and IBANs: save them with `curl -o <file> <download_url>` "
            + "and leave them closed. Don't read their contents, and give the path to the user.",
            annotations = @Tool.Annotations(title = "Create PRAE forms", readOnlyHint = false, destructiveHint = false, idempotentHint = false))
    String create_prae_forms(
            @ToolArg(description = "Tournament or training id", required = false) String event_id,
            @ToolArg(description = "Month, 1 to 12", required = false) Integer month,
            @ToolArg(description = "Year", required = false) Integer year,
            @ToolArg(description = "Only this person's member id", required = false) String member_id) {
        return runner.run("create_prae_forms", user -> {
            requirePermission(user, Permission.MEMBERS_PRIVATE_READ);
            List<PraeForm> forms = forms(user, event_id, month, year, member_id, true);
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("forms", forms.stream().map(McpToolSupport::formRow).toList());
            if (forms.isEmpty()) {
                result.put("message", "Keine Einsätze mit PRAE-Betrag gefunden.");
                return result;
            }
            String token = files.put("PRAE.zip", "application/zip", PraeService.zip(forms));
            result.put("download_url", config.publicUrl() + "/mcp-files/" + token);
            result.put("expires_in_minutes", McpFiles.LIFETIME.toMinutes());
            return result;
        });
    }

    @Tool(description = "All of a tournament's paperwork as one zip (the Sammelabrechnung): the uploaded documents "
            + "(invitation, schedule …), KostZ, TeilnehmerInnenliste Sportler and Helfer, and the PRAE forms with "
            + "Darstellung. Everything is included unless switched off. Returns the file names, the KostZ total and a "
            + "one-time download_url, valid for 10 minutes. Needs club.manage; PRAE also needs members.private.read and "
            + "is left out without it unless prae=true is asked for. If PRAE is included the zip contains social "
            + "security numbers and IBANs: save it with `curl -o <file> <download_url>`, don't read its contents, and "
            + "give the path to the user.",
            annotations = @Tool.Annotations(title = "Create tournament reports", readOnlyHint = false, destructiveHint = false, idempotentHint = false))
    String create_tournament_reports(
            @ToolArg(description = "Tournament id from list_events") String tournament_id,
            @ToolArg(description = "Uploaded documents (invitation …); default true", required = false) Boolean documents,
            @ToolArg(description = "KostZ form; default true", required = false) Boolean kostz,
            @ToolArg(description = "TeilnehmerInnenliste of the players; default true", required = false) Boolean teilnehmer_sportler,
            @ToolArg(description = "TeilnehmerInnenliste of coaches and assistants; default true", required = false) Boolean teilnehmer_helfer,
            @ToolArg(description = "PRAE forms with Darstellung; default: included when the account may read protected data", required = false) Boolean prae,
            @ToolArg(description = "PRAE only for this person's member id", required = false) String prae_member_id) {
        return runner.run("create_tournament_reports", user -> {
            requirePermission(user, Permission.CLUB_MANAGE);
            boolean mayReadPrivate = user.can(Permission.MEMBERS_PRIVATE_READ);
            boolean withPrae = prae == null ? mayReadPrivate : prae;
            if (withPrae) {
                requirePermission(user, Permission.MEMBERS_PRIVATE_READ);
            }
            ClubEvent tournament = tournament(user.club(), tournament_id);
            ReportService service = new ReportService(user.club(), user.roster());
            Reports.Tournament report = service.tournament(tournament.id(), withPrae);
            Set<String> praePeople = Set.of();
            if (withPrae) {
                String wanted = prae_member_id == null ? null : id(prae_member_id, "prae_member_id");
                praePeople = new HashSet<>();
                for (PraeForm form : report.prae()) {
                    PraeForm.Person person = form.person();
                    boolean match = wanted == null || wanted.equals(person.id()) || (person.member() != null
                            && wanted.equals(person.member().id().toLowerCase(Locale.ROOT)));
                    if (match) {
                        praePeople.add(person.id());
                    }
                }
            }
            Reports.Selection selection = new Reports.Selection(kostz == null || kostz, praePeople,
                    teilnehmer_sportler == null || teilnehmer_sportler, teilnehmer_helfer == null || teilnehmer_helfer,
                    false, documents == null || documents);
            if (selection.isEmpty(true)) {
                throw new IllegalArgumentException("Bitte mindestens einen Teil auswählen.");
            }
            LinkedHashMap<String, byte[]> bundle = service.sammelabrechnung(report, selection);
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("tournament", tournament.title());
            result.put("files", List.copyOf(bundle.keySet()));
            if (selection.kostZ()) {
                result.put("kostz_total", report.kostZ().total());
            }
            if (withPrae) {
                result.put("prae_people", report.prae().stream().filter(selection::includes)
                        .map(f -> f.person().displayName()).distinct().toList());
            } else if (prae == null && !report.prae().isEmpty()) {
                result.put("prae_note", "PRAE-Formulare fehlen: dieses Konto darf geschützte Daten (SVNR, IBAN) nicht lesen.");
            }
            if (bundle.isEmpty()) {
                result.put("message", "Für diese Auswahl gibt es keine Dateien.");
                return result;
            }
            String token = files.put("Sammelabrechnung_" + report.label() + ".zip", "application/zip",
                    XlsxPatch.zip(bundle));
            result.put("download_url", config.publicUrl() + "/mcp-files/" + token);
            result.put("expires_in_minutes", McpFiles.LIFETIME.toMinutes());
            return result;
        });
    }

}
