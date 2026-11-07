package it.a11y.blindensport.webui.ui;

import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.button.ButtonVariant;
import com.vaadin.flow.component.grid.Grid;
import com.vaadin.flow.component.html.H2;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.textfield.PasswordField;
import com.vaadin.flow.component.textfield.TextField;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import it.a11y.blindensport.webui.auth.AdminSessions;
import it.a11y.blindensport.webui.auth.SignInException;
import it.a11y.blindensport.webui.mcp.McpTokens;
import jakarta.inject.Inject;

import java.time.Instant;
import java.time.ZoneId;
import java.util.List;

/** The signed-in person's tokens for AI programs (MCP): create, see when they were used, revoke. */
@Route(value = "mcp-tokens", layout = MainLayout.class)
@PageTitle("KI-Zugang – Blindensport Graz")
public class McpTokensView extends AdminView {
    private final McpTokens tokens;
    private final Grid<McpTokens.Info> grid = new Grid<>();
    private final TextField label = new TextField("Name des Tokens, z. B. Laptop");
    private final PasswordField password = new PasswordField("Passwort zur Bestätigung");
    private final TextField issued = new TextField("Neues Token, wird nur jetzt angezeigt");

    @Inject
    public McpTokensView(AdminSessions sessions, McpTokens tokens) {
        super(sessions, "KI-Zugang");
        this.tokens = tokens;
        add(new Paragraph("Mit einem Token kann ein KI-Programm wie Claude Code in Ihrem Namen arbeiten: alles, was Ihr "
                + "Konto darf, außer geschützte Daten sehen und Einträge löschen. Behandeln Sie es wie ein Passwort. "
                + "Es gilt 90 Tage."));
        label.setWidth("24rem");
        password.setWidth("24rem");
        issued.setWidthFull();
        issued.setReadOnly(true);
        issued.setVisible(false);
        Button create = new Button("Token erstellen", e -> create());
        create.addThemeVariants(ButtonVariant.LUMO_PRIMARY);
        grid.addColumn(McpTokens.Info::label).setHeader("Name").setRowHeader(true).setAutoWidth(true);
        grid.addColumn(t -> day(t.lastUsed())).setHeader("Zuletzt benutzt").setAutoWidth(true);
        grid.addColumn(t -> day(t.expires())).setHeader("Gültig bis").setAutoWidth(true);
        grid.addComponentColumn(t -> GermanUi.label(new Button("Widerrufen", e -> revoke(t)), t.label() + " widerrufen"))
                .setHeader("Aktionen").setAutoWidth(true);
        grid.setEmptyStateText("Noch keine Tokens.");
        grid.setAllRowsVisible(true);
        grid.getElement().setAttribute("aria-label", "Meine Tokens");
        add(new H2("Neues Token"), label, password, create, issued, new H2("Meine Tokens"), grid);
    }

    @Override
    protected void refresh() {
        List<McpTokens.Info> mine = tokens.list(session().db());
        grid.setItems(mine);
    }

    private void create() {
        var request = com.vaadin.flow.server.VaadinRequest.getCurrent();
        String client = AdminSessions.clientKey(request.getHeader("X-Forwarded-For"), request.getRemoteAddr());
        try {
            var session = sessions.confirmPassword(session(), password.getValue(), client);
            McpTokens.Issued token = tokens.create(session().db(), session, label.getValue());
            issued.setValue(token.token());
            issued.setVisible(true);
            issued.focus();
            label.clear();
            password.clear();
            Announcer.success("Token erstellt. Bitte jetzt kopieren.");
            refresh();
        } catch (SignInException | IllegalArgumentException e) {
            password.clear();
            Announcer.error(e.getMessage());
        } catch (RuntimeException e) {
            Announcer.failed("Token erstellen", e);
        }
    }

    private void revoke(McpTokens.Info token) {
        GermanUi.confirm(token.label() + " widerrufen?", "Programme mit diesem Token verlieren den Zugriff.", "Widerrufen", () -> {
            if (attempt("Widerrufen", () -> tokens.revoke(session().db(), token.id()))) {
                Announcer.success(token.label() + " widerrufen.");
                attempt("Laden", this::refresh);
            }
        });
    }

    private static String day(Instant instant) {
        return instant == null ? "–" : GermanUi.DAY.format(instant.atZone(ZoneId.of("Europe/Vienna")));
    }
}
