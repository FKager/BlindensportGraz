package it.a11y.blindensport.webadmin.ui;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.button.ButtonVariant;
import com.vaadin.flow.component.grid.Grid;
import com.vaadin.flow.component.grid.GridVariant;
import com.vaadin.flow.component.html.Anchor;
import com.vaadin.flow.component.dialog.Dialog;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.html.Pre;
import com.vaadin.flow.component.orderedlayout.FlexComponent;
import com.vaadin.flow.component.orderedlayout.HorizontalLayout;
import com.vaadin.flow.component.textfield.TextField;
import com.vaadin.flow.component.upload.Upload;
import com.vaadin.flow.data.value.ValueChangeMode;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.server.streams.DownloadHandler;
import com.vaadin.flow.server.streams.DownloadResponse;
import com.vaadin.flow.server.streams.UploadHandler;
import it.a11y.blindensport.webadmin.auth.AdminSession;
import it.a11y.blindensport.webadmin.auth.AdminSessions;
import it.a11y.blindensport.webadmin.auth.Permission;
import it.a11y.blindensport.webadmin.members.MemberBulkImport;
import it.a11y.blindensport.webadmin.members.MemberBulkInput;
import it.a11y.blindensport.webadmin.members.MemberJson;
import it.a11y.blindensport.webadmin.members.MemberRecord;
import it.a11y.blindensport.webadmin.members.MemberStore;
import jakarta.inject.Inject;

import java.io.ByteArrayInputStream;
import java.time.LocalDate;
import java.util.List;
import java.util.Locale;
import java.util.stream.Collectors;
import java.util.stream.Stream;

/** The club roster: search, create, edit, delete, JSON import and export. */
@Route(value = "mitglieder", layout = MainLayout.class)
@PageTitle("Mitglieder – Blindensport Graz")
@RequiresPermission(Permission.MEMBERS_MANAGE)
public class MembersView extends AdminView {
    private final ObjectMapper json;
    private final Grid<MemberRecord> grid = new Grid<>();
    private final TextField search = new TextField();
    private final Paragraph count = new Paragraph();
    private final Pre importResult = new Pre();
    private List<MemberRecord> members = List.of();
    private byte[] uploaded;

    @Inject
    public MembersView(AdminSessions sessions, ObjectMapper json) {
        super(sessions, "Mitglieder");
        this.json = json;
        setSizeFull();

        search.setLabel("Suchen");
        search.setPlaceholder("Name, E-Mail, Ort, Mitgl.-Nr. …");
        search.setClearButtonVisible(true);
        search.setValueChangeMode(ValueChangeMode.LAZY);
        search.addValueChangeListener(e -> applyFilter());
        search.setWidth("20rem");

        Button add = new Button("Neues Mitglied", e -> openDialog(null));
        add.addThemeVariants(ButtonVariant.LUMO_PRIMARY);
        Button reload = new Button("Neu laden", e -> attempt("Laden", this::refresh));
        Anchor export = new Anchor(DownloadHandler.fromInputStream(event -> exportJson()), "Als JSON exportieren");
        export.getElement().setAttribute("download", true);

        Button importButton = new Button("JSON importieren …", e -> openImport());
        HorizontalLayout toolbar = new HorizontalLayout(search, add, reload, importButton, export);
        toolbar.setDefaultVerticalComponentAlignment(FlexComponent.Alignment.BASELINE);
        toolbar.setWrap(true);

        count.getElement().setAttribute("role", "status");

        grid.addColumn(m -> m.lastName() + ", " + m.firstName()).setHeader("Name").setSortable(true)
                .setComparator(m -> (m.lastName() + " " + m.firstName()).toLowerCase(Locale.ROOT))
                .setAutoWidth(true).setRowHeader(true);
        grid.addColumn(m -> join(", ", m.street(), join(" ", m.zip(), m.city()))).setHeader("Adresse").setFlexGrow(1);
        grid.addColumn(m -> join(" · ", m.email(), m.phone())).setHeader("Kontakt").setFlexGrow(1);
        grid.addColumn(MemberRecord::memberNumber).setHeader("Mitgl.-Nr.").setSortable(true).setAutoWidth(true)
                .setFlexGrow(0);
        grid.addComponentColumn(this::actions).setHeader("Aktionen").setAutoWidth(true).setFlexGrow(0)
                .setFrozenToEnd(true);
        grid.addThemeVariants(GridVariant.LUMO_ROW_STRIPES);
        grid.setEmptyStateText("Keine Mitglieder gefunden.");
        grid.addItemDoubleClickListener(e -> openDialog(e.getItem()));
        grid.setSizeFull();
        grid.getElement().setAttribute("aria-label", "Mitglieder");

        add(toolbar, count, grid);
        setFlexGrow(1, grid);
    }

    @Override
    protected void refresh() {
        AdminSession admin = session();
        members = new MemberStore(admin.db()).all(admin.can(Permission.MEMBERS_PRIVATE_READ));
        applyFilter();
    }

    private void applyFilter() {
        String q = search.getValue().trim().toLowerCase(Locale.ROOT);
        List<MemberRecord> shown = q.isEmpty() ? members : members.stream()
                .filter(m -> Stream.of(m.firstName(), m.lastName(), m.email(), m.phone(), m.city(), m.street(),
                                m.memberNumber())
                        .anyMatch(f -> f.toLowerCase(Locale.ROOT).contains(q)))
                .toList();
        grid.setItems(shown);
        count.setText(shown.size() == members.size()
                ? members.size() + " Mitglieder"
                : shown.size() + " von " + members.size() + " Mitgliedern");
    }

    private HorizontalLayout actions(MemberRecord member) {
        Button edit = GermanUi.label(new Button("Bearbeiten", e -> openDialog(member)), member.fullName() + " bearbeiten");
        Button delete = GermanUi.label(new Button("Löschen", e -> confirmDelete(member)), member.fullName() + " löschen");
        edit.addThemeVariants(ButtonVariant.LUMO_SMALL);
        delete.addThemeVariants(ButtonVariant.LUMO_SMALL, ButtonVariant.LUMO_ERROR);
        return new HorizontalLayout(edit, delete);
    }

    private void openDialog(MemberRecord member) {
        AdminSession admin = session();
        MemberDialog[] holder = new MemberDialog[1];
        holder[0] = new MemberDialog(member, admin.can(Permission.MEMBERS_PRIVATE_READ),
                admin.can(Permission.MEMBERS_PRIVATE_WRITE), (record, writePrivate) -> {
            boolean saved = attempt("Speichern",
                    () -> new MemberStore(session().db()).save(record, writePrivate, session().userId()));
            if (saved) {
                holder[0].close();
                Announcer.success(member == null ? record.fullName() + " angelegt." : record.fullName() + " gespeichert.");
                attempt("Laden", this::refresh);
            }
        });
        holder[0].open();
    }

    private void confirmDelete(MemberRecord member) {
        GermanUi.confirm(member.fullName() + " löschen?",
                "Der Eintrag wird mit Kontakt- und geschützten Daten gelöscht. Das kann nicht rückgängig gemacht werden.",
                "Löschen", () -> {
                    if (attempt("Löschen", () -> new MemberStore(session().db()).delete(member.id()))) {
                        Announcer.success(member.fullName() + " gelöscht.");
                        attempt("Laden", this::refresh);
                    }
                });
    }

    private DownloadResponse exportJson() throws java.io.IOException {
        AdminSession admin = UiSession.current(sessions).orElse(null);
        if (admin == null || !admin.can(Permission.MEMBERS_MANAGE)) {
            return DownloadResponse.error(403);
        }
        List<MemberRecord> all = new MemberStore(admin.db()).all(admin.can(Permission.MEMBERS_PRIVATE_READ));
        byte[] bytes = json.copy().enable(SerializationFeature.INDENT_OUTPUT)
                .writeValueAsBytes(all.stream().map(MemberJson::toMap).toList());
        return new DownloadResponse(new ByteArrayInputStream(bytes),
                "grazer-vsc-mitglieder-" + LocalDate.now() + ".json", "application/json", bytes.length);
    }

    private void openImport() {
        Dialog dialog = new Dialog();
        dialog.setHeaderTitle("Mitglieder-Import (JSON)");
        dialog.setWidth("min(40rem, 100vw)");
        importResult.setText("");
        Upload upload = new Upload(UploadHandler.inMemory((metadata, bytes) -> uploaded = bytes));
        upload.setAcceptedFileTypes("application/json", ".json");
        upload.setMaxFiles(1);
        upload.setI18n(GermanUi.uploadI18n("JSON-Datei auswählen …", "JSON-Datei hierher ziehen"));
        upload.addSucceededListener(e -> {
            importUploaded();
            upload.clearFileList();
        });
        importResult.getElement().setAttribute("role", "status");
        importResult.getStyle().set("white-space", "pre-wrap").set("font-size", "var(--lumo-font-size-s)");
        dialog.add(new Paragraph("Eine JSON-Datei mit einem Array von Mitgliedern (gleiches Format wie der Export "
                        + "der App bzw. dieser Seite). Einträge mit vorhandener id werden aktualisiert, neue angelegt; "
                        + "fehlerhafte Zeilen (fehlender Vor-/Nachname) werden übersprungen, nicht die ganze Datei. "
                        + "Geschützte Felder (svnr, iban, birthDate, lastMedicalExamination) brauchen die "
                        + "Berechtigung zum Ändern geschützter Daten."),
                upload, importResult);
        dialog.getFooter().add(new Button("Schließen", e -> dialog.close()));
        dialog.open();
    }

    private void importUploaded() {
        byte[] bytes = uploaded;
        uploaded = null;
        if (bytes == null) {
            return;
        }
        List<MemberBulkInput> inputs;
        try {
            inputs = json.readValue(bytes, new TypeReference<>() {
            });
        } catch (java.io.IOException e) {
            importResult.setText("Die Datei ist kein JSON-Array von Mitgliedern.");
            Announcer.error("Import fehlgeschlagen: Die Datei ist kein JSON-Array von Mitgliedern.");
            return;
        }
        AdminSession admin = session();
        if (inputs.stream().anyMatch(i -> !i.privateData().isEmpty()) && !admin.can(Permission.MEMBERS_PRIVATE_WRITE)) {
            Announcer.error("Import abgebrochen: Die Datei enthält geschützte Felder, zum Ändern fehlt die Berechtigung.");
            return;
        }
        MemberBulkImport.Result result = attempt("Import",
                () -> MemberBulkImport.run(inputs, new MemberStore(admin.db()), admin.userId()));
        if (result == null) {
            return;
        }
        importResult.setText(result.succeeded() + " importiert, " + result.failed() + " fehlgeschlagen (von "
                + result.total() + ").\n" + String.join("\n", result.messages()));
        if (result.failed() == 0) {
            Announcer.success(result.succeeded() + " Mitglieder importiert.");
        } else {
            Announcer.error(result.failed() + " von " + result.total() + " Einträgen konnten nicht importiert werden.");
        }
        attempt("Laden", this::refresh);
    }

    private static String join(String separator, String... parts) {
        return Stream.of(parts).filter(p -> p != null && !p.isBlank()).collect(Collectors.joining(separator));
    }
}
