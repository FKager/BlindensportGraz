package it.a11y.blindensport.webadmin.ui;

import com.vaadin.flow.component.UI;
import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.button.ButtonVariant;
import com.vaadin.flow.component.html.H1;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.html.Span;
import com.vaadin.flow.component.orderedlayout.VerticalLayout;
import com.vaadin.flow.router.BeforeEnterEvent;
import com.vaadin.flow.router.BeforeEnterObserver;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import it.a11y.blindensport.webadmin.auth.AdminSession;
import it.a11y.blindensport.webadmin.auth.AdminSessions;
import it.a11y.blindensport.webadmin.supabase.GoTrue;
import it.a11y.blindensport.webadmin.supabase.Supabase;
import it.a11y.blindensport.webadmin.supabase.SupabaseException;
import jakarta.inject.Inject;

import java.net.URI;
import java.util.regex.Pattern;

/**
 * Supabase's OAuth server sends an MCP client's sign-in here
 * ({@code auth.oauth_server.authorization_url_path}). The person, signed in
 * with their normal account (AccessGuard → LoginView and back), decides whether
 * this client may act for them. Any MCP client can register itself, so its name
 * proves nothing: the page also shows where the sign-in returns to.
 */
@Route("oauth/consent")
@PageTitle("Zugriff erlauben – Blindensport Graz")
public class OAuthConsentView extends VerticalLayout implements BeforeEnterObserver {
    private static final Pattern AUTHORIZATION_ID = Pattern.compile("[A-Za-z0-9_-]{1,128}");

    private final AdminSessions sessions;
    private final Supabase supabase;
    private final Paragraph status = new Paragraph();
    private String authorizationId;

    @Inject
    public OAuthConsentView(AdminSessions sessions, Supabase supabase) {
        this.sessions = sessions;
        this.supabase = supabase;
        setMaxWidth("36rem");
        getStyle().set("margin", "2rem auto");
        status.getElement().setAttribute("role", "alert");
        add(new H1("Zugriff erlauben"));
    }

    @Override
    public void beforeEnter(BeforeEnterEvent event) {
        authorizationId = event.getLocation().getQueryParameters().getSingleParameter("authorization_id").orElse("");
        AdminSession admin = UiSession.current(sessions).orElse(null);
        if (admin == null) {
            return;
        }
        if (!AUTHORIZATION_ID.matcher(authorizationId).matches()) {
            showProblem();
            return;
        }
        try {
            GoTrue.Authorization request = supabase.auth().oauthAuthorization(admin.accessToken(), authorizationId);
            if (request.redirectUrl() != null) {
                UI.getCurrent().getPage().setLocation(request.redirectUrl());
                return;
            }
            showRequest(admin, request);
        } catch (SupabaseException e) {
            showProblem();
        }
    }

    private void showRequest(AdminSession admin, GoTrue.Authorization request) {
        String client = request.clientName().isBlank() ? "Ein unbenanntes Programm" : request.clientName();
        Button allow = new Button("Zugriff erlauben", e -> decide(true));
        allow.addThemeVariants(ButtonVariant.LUMO_PRIMARY);
        Button deny = new Button("Ablehnen", e -> decide(false));
        add(new Paragraph(client + " möchte als " + admin.email() + " (" + admin.roleName() + ") auf Blindensport Graz zugreifen."),
                new Paragraph(new Span("Die Anmeldung kehrt zurück zu: "), new Span(host(request.redirectUri()))),
                new Paragraph("Das Programm darf alles, was dieses Konto darf: Mitglieder, Teams, Trainings und "
                        + "Turniere ansehen und bearbeiten sowie PRAE-Formulare erstellen. Geschützte Daten wie SVNR "
                        + "und IBAN bekommt es nicht zu sehen, und es kann nichts löschen."),
                new Paragraph("Bitte nur erlauben, wenn du diese Anmeldung gerade selbst gestartet hast."),
                allow, deny, status);
        allow.focus();
    }

    private void decide(boolean approve) {
        AdminSession admin = UiSession.current(sessions).orElse(null);
        if (admin == null) {
            showProblem();
            return;
        }
        try {
            String target = supabase.auth().oauthConsent(admin.accessToken(), authorizationId, approve);
            UI.getCurrent().getPage().setLocation(target);
        } catch (SupabaseException e) {
            showProblem();
        }
    }

    private void showProblem() {
        status.setText("Diese Anfrage ist ungültig oder abgelaufen. Bitte die Anmeldung im Programm neu starten.");
        add(status);
    }

    /** The redirect's host, or the whole URI if it has none. */
    private static String host(String redirectUri) {
        try {
            String host = URI.create(redirectUri).getHost();
            return host == null ? redirectUri : host;
        } catch (IllegalArgumentException e) {
            return redirectUri;
        }
    }
}
