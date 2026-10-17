package it.a11y.blindensport.webadmin.ui;

import com.vaadin.flow.component.Key;
import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.button.ButtonVariant;
import com.vaadin.flow.component.html.H1;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.orderedlayout.VerticalLayout;
import com.vaadin.flow.component.textfield.EmailField;
import com.vaadin.flow.component.textfield.PasswordField;
import com.vaadin.flow.router.BeforeEnterEvent;
import com.vaadin.flow.router.BeforeEnterObserver;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.server.VaadinRequest;
import it.a11y.blindensport.webadmin.auth.AdminSessions;
import it.a11y.blindensport.webadmin.auth.SignInException;
import jakarta.inject.Inject;

/**
 * Sign-in with the own Blindensport Graz account (same as in the app). Own
 * form instead of Vaadin's LoginForm so the shared limiter and the German
 * messages apply, and the error is announced to screen readers.
 */
@Route("login")
@PageTitle("Anmelden – Blindensport Graz")
public class LoginView extends VerticalLayout implements BeforeEnterObserver {
    private final AdminSessions sessions;
    private final EmailField email = new EmailField("E-Mail");
    private final PasswordField password = new PasswordField("Passwort");
    private final Paragraph status = new Paragraph();

    @Inject
    public LoginView(AdminSessions sessions) {
        this.sessions = sessions;
        setMaxWidth("26rem");
        getStyle().set("margin", "2rem auto");

        email.setWidthFull();
        email.setRequiredIndicatorVisible(true);
        email.setAutocomplete(com.vaadin.flow.component.textfield.Autocomplete.USERNAME);
        password.setWidthFull();
        password.setRequiredIndicatorVisible(true);
        password.setAutocomplete(com.vaadin.flow.component.textfield.Autocomplete.CURRENT_PASSWORD);

        Button signIn = new Button("Anmelden", e -> signIn());
        signIn.addThemeVariants(ButtonVariant.LUMO_PRIMARY);
        signIn.addClickShortcut(Key.ENTER);

        // role=alert: the result of a sign-in attempt is read out immediately.
        status.getElement().setAttribute("role", "alert");
        status.getStyle().set("color", "var(--lumo-error-text-color)");

        add(new H1("Blindensport Graz – Verwaltung"),
                new Paragraph("Mit dem eigenen Blindensport-Graz-Konto anmelden (gleiche Anmeldung wie in der App). "
                        + "Zugriff haben Trainer:innen, Admins und Root."),
                email, password, signIn, status);
    }

    @Override
    public void beforeEnter(BeforeEnterEvent event) {
        if (UiSession.current(sessions).isPresent()) {
            event.forwardTo(StartView.class);
            return;
        }
        if (event.getLocation().getQueryParameters().getParameters().containsKey("abgemeldet")) {
            status.setText("Abgemeldet.");
        }
        email.focus();
    }

    private void signIn() {
        VaadinRequest request = VaadinRequest.getCurrent();
        String client = AdminSessions.clientKey(request.getHeader("X-Forwarded-For"), request.getRemoteAddr());
        status.setText("Anmelden …");
        try {
            String token = sessions.signIn(email.getValue(), password.getValue(), client);
            UiSession.signedIn(token);
            getUI().ifPresent(ui -> ui.navigate(StartView.class));
        } catch (SignInException e) {
            status.setText(e.getMessage());
            password.clear();
            password.focus();
        } catch (RuntimeException e) {
            status.setText("Anmelden fehlgeschlagen: Die Datenbank ist gerade nicht erreichbar.");
            password.clear();
            password.focus();
        }
    }
}
