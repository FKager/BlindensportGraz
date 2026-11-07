package it.a11y.blindensport.webui.ui;

import com.vaadin.flow.component.Key;
import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.button.ButtonVariant;
import com.vaadin.flow.component.html.H1;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.orderedlayout.VerticalLayout;
import com.vaadin.flow.component.textfield.EmailField;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.router.RouterLink;
import com.vaadin.flow.server.VaadinRequest;
import it.a11y.blindensport.webui.auth.AdminSessions;
import it.a11y.blindensport.webui.auth.SignInException;
import jakarta.inject.Inject;

/** Requests a reset link by email; it leads to {@link ResetPasswordView}. */
@Route("passwort-vergessen")
@PageTitle("Passwort vergessen – Blindensport Graz")
public class ForgotPasswordView extends VerticalLayout {
    private final AdminSessions sessions;
    private final EmailField email = new EmailField("E-Mail");
    private final Button send = new Button("Link schicken", e -> send());
    private final Paragraph status = new Paragraph();

    @Inject
    public ForgotPasswordView(AdminSessions sessions) {
        this.sessions = sessions;
        setMaxWidth("26rem");
        getStyle().set("margin", "2rem auto");
        email.setWidthFull();
        email.setRequiredIndicatorVisible(true);
        email.setAutocomplete(com.vaadin.flow.component.textfield.Autocomplete.USERNAME);
        send.addThemeVariants(ButtonVariant.LUMO_PRIMARY);
        send.addClickShortcut(Key.ENTER);
        status.getElement().setAttribute("role", "alert");
        add(new H1("Passwort vergessen"), new Paragraph("Gib deine E-Mail-Adresse ein. Wir schicken dir einen Link für ein neues Passwort."),
                email, send, status, new RouterLink("Anmelden", LoginView.class));
    }

    private void send() {
        if (email.getValue().isBlank() || email.isInvalid()) {
            status.setText("Bitte eine gültige E-Mail-Adresse angeben.");
            return;
        }
        VaadinRequest request = VaadinRequest.getCurrent();
        String client = AdminSessions.clientKey(request.getHeader("X-Forwarded-For"), request.getRemoteAddr());
        try {
            sessions.requestPasswordReset(email.getValue(), client);
            email.setVisible(false);
            send.setVisible(false);
            // The same answer whether the address has an account or not.
            status.setText("Wenn es zu dieser Adresse ein Konto gibt, ist jetzt eine E-Mail unterwegs.");
        } catch (SignInException e) {
            status.setText(e.getMessage());
        } catch (RuntimeException e) {
            status.setText("Das hat gerade nicht geklappt. Bitte versuche es später noch einmal.");
        }
    }
}
