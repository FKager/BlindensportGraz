package it.a11y.blindensport.webadmin.ui;

import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.button.ButtonVariant;
import com.vaadin.flow.component.checkbox.Checkbox;
import com.vaadin.flow.component.html.H2;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.markdown.Markdown;
import com.vaadin.flow.component.textfield.TextArea;
import com.vaadin.flow.data.value.ValueChangeMode;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import it.a11y.blindensport.webadmin.auth.AdminSession;
import it.a11y.blindensport.webadmin.auth.AdminSessions;
import it.a11y.blindensport.webadmin.auth.Permission;
import it.a11y.blindensport.webadmin.club.ClubModels.WelcomeContent;
import it.a11y.blindensport.webadmin.club.ClubStore;
import jakarta.inject.Inject;

/** The welcome text the app shows at startup, also before signing in (club.manage). */
@Route(value = "willkommen", layout = MainLayout.class)
@PageTitle("Willkommensbildschirm – Blindensport Graz")
@RequiresPermission(Permission.CLUB_MANAGE)
public class WelcomeView extends AdminView {
    private final TextArea markdown = new TextArea("Text (Markdown)");
    private final Checkbox enabled = new Checkbox("Beim Start der App anzeigen");
    private final Markdown preview = new Markdown();
    private String id;

    @Inject
    public WelcomeView(AdminSessions sessions) {
        super(sessions, "Willkommensbildschirm");
        markdown.setWidthFull();
        markdown.setMinRows(8);
        markdown.setHelperText("**fett**, *kursiv*, # Überschrift, - Aufzählung, [Link](https://…)");
        markdown.setValueChangeMode(ValueChangeMode.LAZY);
        markdown.addValueChangeListener(e -> preview.setContent(e.getValue()));
        Button save = new Button("Speichern", e -> save());
        save.addThemeVariants(ButtonVariant.LUMO_PRIMARY);
        preview.getStyle().set("border", "1px solid var(--lumo-contrast-20pct)").set("border-radius", "var(--lumo-border-radius-m)")
                .set("padding", "var(--lumo-space-m)").set("width", "100%");
        add(new Paragraph("Wird allen beim Start der App angezeigt – auch vor dem Anmelden. Keine persönlichen Daten eintragen."),
                markdown, enabled, save, new H2("Vorschau"), preview);
    }

    @Override
    protected void refresh() {
        AdminSession admin = session();
        var current = new ClubStore(admin.db(), admin.userId()).welcome();
        id = current.map(WelcomeContent::id).orElse(null);
        markdown.setValue(current.map(WelcomeContent::markdown).orElse(""));
        enabled.setValue(current.map(WelcomeContent::enabled).orElse(false));
        preview.setContent(markdown.getValue());
    }

    private void save() {
        AdminSession admin = session();
        WelcomeContent content = new WelcomeContent(id == null ? ClubStore.newId() : id, markdown.getValue(),
                enabled.getValue());
        if (attempt("Speichern", () -> new ClubStore(admin.db(), admin.userId()).saveWelcome(content))) {
            id = content.id();
            Announcer.success(content.enabled() ? "Willkommenstext gespeichert und eingeschaltet."
                    : "Willkommenstext gespeichert (ausgeschaltet).");
        }
    }
}
