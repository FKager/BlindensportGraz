package it.a11y.blindensport.webui.ui;

import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.button.ButtonVariant;
import com.vaadin.flow.component.dialog.Dialog;
import com.vaadin.flow.component.html.Anchor;
import com.vaadin.flow.component.html.H3;
import com.vaadin.flow.component.html.ListItem;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.html.Span;
import com.vaadin.flow.component.html.UnorderedList;
import com.vaadin.flow.component.upload.Upload;
import com.vaadin.flow.server.streams.DownloadHandler;
import com.vaadin.flow.server.streams.DownloadResponse;
import com.vaadin.flow.server.streams.UploadHandler;
import it.a11y.blindensport.webui.auth.AdminSession;
import it.a11y.blindensport.webui.auth.AdminSessions;
import it.a11y.blindensport.webui.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webui.club.TournamentDocuments;
import it.a11y.blindensport.webui.club.TournamentDocuments.Document;

import java.io.ByteArrayInputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Queue;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.function.Supplier;

import static it.a11y.blindensport.webui.members.Dates.CLUB_ZONE;

/**
 * A tournament's documents (invitation, schedule, results …): download,
 * add several at once, delete. The same documents the app shows under
 * "Dokumente"; every approved account can read them there.
 */
class TournamentDocumentsDialog extends Dialog {
    private final ClubEvent tournament;
    private final AdminSessions sessions;
    private final Supplier<TournamentDocuments> store;
    private final AdminView owner;
    private final Runnable onChange;
    private final UnorderedList list = new UnorderedList();
    private final Paragraph empty = new Paragraph("Noch keine Dokumente.");
    private final H3 heading = new H3();
    private final Queue<Map.Entry<String, byte[]>> received = new ConcurrentLinkedQueue<>();

    TournamentDocumentsDialog(ClubEvent tournament, AdminSessions sessions, Supplier<TournamentDocuments> store,
                              AdminView owner, Runnable onChange) {
        this.tournament = tournament;
        this.sessions = sessions;
        this.store = store;
        this.owner = owner;
        this.onChange = onChange;
        setHeaderTitle("Dokumente: " + tournament.title());
        setWidth("min(44rem, 100vw)");

        Upload upload = new Upload(UploadHandler.inMemory(
                (metadata, bytes) -> received.add(Map.entry(metadata.fileName(), bytes))));
        List<String> accepted = new ArrayList<>(TournamentDocuments.acceptedTypes());
        accepted.addAll(TournamentDocuments.acceptedExtensions());
        upload.setAcceptedFileTypes(accepted.toArray(String[]::new));
        upload.setMaxFileSize(TournamentDocuments.MAX_BYTES);
        upload.setI18n(GermanUi.uploadI18n("Dokumente auswählen …", "Dokumente hierher ziehen"));
        upload.addFileRejectedListener(e -> Announcer.error(e.getFileName() + ": " + e.getErrorMessage()));
        upload.addAllFinishedListener(e -> {
            storeReceived();
            upload.clearFileList();
        });

        heading.getStyle().set("font-size", "var(--lumo-font-size-m)").set("margin", "0");
        add(heading, empty, list,
                new Paragraph("Hinzufügen: PDF, Word, Excel, Text oder Bild, bis 15 MB je Datei, auch mehrere auf "
                        + "einmal. Alle freigeschalteten Mitglieder sehen die Dokumente in der App."),
                upload);
        getFooter().add(new Button("Schließen", e -> close()));
        show();
    }

    private void show() {
        List<Document> documents = owner.attempt("Dokumente laden", () -> store.get().list(tournament.id()));
        list.removeAll();
        if (documents == null) {
            return;
        }
        heading.setText(documents.size() == 1 ? "1 Dokument" : documents.size() + " Dokumente");
        empty.setVisible(documents.isEmpty());
        for (Document document : documents) {
            list.add(item(document));
        }
    }

    private ListItem item(Document document) {
        Anchor download = new Anchor(DownloadHandler.fromInputStream(event -> {
            AdminSession admin = UiSession.current(sessions).orElse(null);
            if (admin == null) {
                return DownloadResponse.error(403);
            }
            byte[] content = new TournamentDocuments(admin.db(), admin.userId()).content(document);
            return new DownloadResponse(new ByteArrayInputStream(content), document.fileName(),
                    document.contentType().isBlank() ? "application/octet-stream" : document.contentType(),
                    content.length);
        }), document.fileName());
        download.getElement().setAttribute("download", true);
        GermanUi.label(download, document.fileName() + " herunterladen");
        Span when = new Span(document.uploadedAt() == null ? ""
                : " (hochgeladen am " + GermanUi.DAY.format(document.uploadedAt().atZone(CLUB_ZONE)) + ")");
        Button delete = GermanUi.label(new Button("Löschen", e -> confirmDelete(document)),
                document.fileName() + " löschen");
        delete.addThemeVariants(ButtonVariant.LUMO_ERROR, ButtonVariant.LUMO_SMALL, ButtonVariant.LUMO_TERTIARY);
        return new ListItem(download, when, delete);
    }

    private void confirmDelete(Document document) {
        GermanUi.confirm(document.fileName() + " löschen?",
                "Das Dokument wird für alle entfernt, auch in der App.", "Löschen", () -> {
                    Boolean deleted = owner.attempt("Löschen", () -> store.get().delete(document));
                    if (Boolean.TRUE.equals(deleted)) {
                        Announcer.success(document.fileName() + " gelöscht.");
                    } else if (deleted != null) {
                        Announcer.error(document.fileName() + " konnte nicht gelöscht werden (keine Berechtigung?).");
                    }
                    show();
                    onChange.run();
                });
    }

    private void storeReceived() {
        List<String> added = new ArrayList<>();
        Map.Entry<String, byte[]> file;
        while ((file = received.poll()) != null) {
            Map.Entry<String, byte[]> next = file;
            if (owner.attempt("Hochladen von " + next.getKey(),
                    () -> store.get().add(tournament.id(), next.getKey(), next.getValue())) != null) {
                added.add(next.getKey());
            }
        }
        if (!added.isEmpty()) {
            Announcer.success(added.size() == 1 ? added.get(0) + " hinzugefügt."
                    : added.size() + " Dokumente hinzugefügt: " + String.join(", ", added) + ".");
            show();
            onChange.run();
        }
    }
}
