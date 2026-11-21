package it.a11y.blindensport.webui.mcp;

import io.quarkiverse.mcp.server.Tool;
import io.quarkiverse.mcp.server.ToolArg;
import it.a11y.blindensport.webui.auth.Permission;
import it.a11y.blindensport.webui.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webui.club.ClubStore;
import it.a11y.blindensport.webui.club.DocumentText;
import it.a11y.blindensport.webui.club.TournamentDocuments;
import it.a11y.blindensport.webui.members.Dates;
import jakarta.inject.Inject;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static it.a11y.blindensport.webui.mcp.McpToolSupport.*;

/**
 * MCP tools for tournament documents (invitation, schedule, results …). The rules of every MCP tool (see {@link McpToolSupport}): it
 * runs as the signed-in person, so RLS and their role decide; protected
 * member fields never appear in a result and can't be written.
 */
public class TournamentDocumentTools {
    @Inject
    McpToolRunner runner;

    @Inject
    McpFiles files;

    @Inject
    McpConfig config;

    // ------------------------------------------------ tournament documents

    @Tool(description = "List a tournament's documents (invitation, schedule, results …): id, file name, type, upload date. "
            + "Every approved account may read them.",
            annotations = @Tool.Annotations(title = "List tournament documents", readOnlyHint = true, destructiveHint = false, idempotentHint = true))
    String list_tournament_documents(@ToolArg(description = "Tournament id from list_events") String tournament_id) {
        return runner.run("list_tournament_documents", user -> {
            ClubEvent tournament = tournament(user.club(), tournament_id);
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("tournament", tournament.title());
            result.put("documents", documents(user).list(tournament.id()).stream().map(McpToolSupport::documentRow).toList());
            return result;
        });
    }

    @Tool(description = "One tournament document: its text (PDF, Word .docx and .txt; cut off after "
            + DocumentText.MAX_CHARS + " characters) and a one-time download link, valid 10 minutes, for the file itself.",
            annotations = @Tool.Annotations(title = "Get tournament document", readOnlyHint = true, destructiveHint = false, idempotentHint = false))
    String get_tournament_document(@ToolArg(description = "Document id from list_tournament_documents") String document_id) {
        return runner.run("get_tournament_document", user -> {
            TournamentDocuments store = documents(user);
            TournamentDocuments.Document document = document(store, document_id);
            byte[] content = store.content(document);
            Map<String, Object> result = documentRow(document);
            result.put("size_bytes", content.length);
            DocumentText.of(document.fileName(), content).ifPresentOrElse(text -> result.put("text", text),
                    () -> result.put("text_note", "Für diesen Dateityp gibt es keinen Text; bitte den Link verwenden."));
            String token = files.put(document.fileName(),
                    document.contentType().isBlank() ? "application/octet-stream" : document.contentType(), content);
            result.put("download_url", config.publicUrl() + "/mcp-files/" + token);
            result.put("expires_in_minutes", McpFiles.LIFETIME.toMinutes());
            return result;
        });
    }

    @Tool(description = "Add a document to a tournament (invitation, schedule, results …). PDF, Word (.docx/.doc), "
            + "Excel (.xlsx/.xls), .txt or image (.jpg/.png/.heic), at most 15 MB. Every approved account will see it "
            + "in the app. Needs events.manage.",
            annotations = @Tool.Annotations(title = "Upload tournament document", readOnlyHint = false, destructiveHint = false, idempotentHint = false))
    String upload_tournament_document(
            @ToolArg(description = "Tournament id from list_events") String tournament_id,
            @ToolArg(description = "File name with extension, e.g. Einladung.pdf") String file_name,
            @ToolArg(description = "The file's content, base64-encoded") String content_base64) {
        return runner.run("upload_tournament_document", user -> {
            requirePermission(user, Permission.EVENTS_MANAGE);
            ClubEvent tournament = tournament(user.club(), tournament_id);
            byte[] content;
            try {
                content = java.util.Base64.getMimeDecoder().decode(required(content_base64, "content_base64"));
            } catch (IllegalArgumentException e) {
                throw new IllegalArgumentException("content_base64 ist kein gültiges Base64.");
            }
            TournamentDocuments.Document added = documents(user).add(tournament.id(), required(file_name, "file_name"), content);
            Map<String, Object> result = documentRow(added);
            result.put("tournament", tournament.title());
            result.put("size_bytes", content.length);
            return result;
        });
    }

    @Tool(description = "Delete one tournament document for everyone (also in the app). Cannot be undone; confirm with "
            + "the user first. Needs events.manage.",
            annotations = @Tool.Annotations(title = "Delete tournament document", readOnlyHint = false, destructiveHint = true, idempotentHint = true))
    String delete_tournament_document(@ToolArg(description = "Document id from list_tournament_documents") String document_id) {
        return runner.run("delete_tournament_document", user -> {
            requirePermission(user, Permission.EVENTS_MANAGE);
            TournamentDocuments store = documents(user);
            TournamentDocuments.Document document = document(store, document_id);
            if (!store.delete(document)) {
                throw new IllegalArgumentException("Das Dokument konnte nicht gelöscht werden.");
            }
            return Map.of("deleted", document.fileName());
        });
    }
}
