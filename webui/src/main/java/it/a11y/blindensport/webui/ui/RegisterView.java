package it.a11y.blindensport.webui.ui;

import com.vaadin.flow.component.Key;
import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.button.ButtonVariant;
import com.vaadin.flow.component.html.H1;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.orderedlayout.VerticalLayout;
import com.vaadin.flow.component.textfield.EmailField;
import com.vaadin.flow.component.textfield.PasswordField;
import com.vaadin.flow.component.textfield.TextField;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.router.RouterLink;
import com.vaadin.flow.server.VaadinRequest;
import it.a11y.blindensport.webui.auth.AdminSessions;
import it.a11y.blindensport.webui.auth.SignInException;
import jakarta.inject.Inject;

/**
 * Creates an account, as the app's RegisterView does. It starts without a role,
 * so it sees the Übersicht until an admin approves it under App-Konten. The
 * email's link leads to {@link ConfirmEmailView}.
 */
@Route("registrieren")
@PageTitle("Registrieren – Blindensport Graz")
public class RegisterView extends VerticalLayout {
    private final AdminSessions sessions;
    private final TextField firstName = new TextField("Vorname");
    private final TextField lastName = new TextField("Nachname");
    private final EmailField email = new EmailField("E-Mail");
    private final PasswordField password = new PasswordField("Passwort");
    private final PasswordField repeat = new PasswordField("Passwort wiederholen");
    private final Paragraph status = new Paragraph();
    private final VerticalLayout form = new VerticalLayout();

    @Inject
    public RegisterView(AdminSessions sessions) {
        this.sessions = sessions;
        setMaxWidth("26rem");
        getStyle().set("margin", "2rem auto");
        firstName.setAutocomplete(com.vaadin.flow.component.textfield.Autocomplete.GIVEN_NAME);
        lastName.setAutocomplete(com.vaadin.flow.component.textfield.Autocomplete.FAMILY_NAME);
        email.setAutocomplete(com.vaadin.flow.component.textfield.Autocomplete.USERNAME);
        password.setAutocomplete(com.vaadin.flow.component.textfield.Autocomplete.NEW_PASSWORD);
        repeat.setAutocomplete(com.vaadin.flow.component.textfield.Autocomplete.NEW_PASSWORD);
        password.setHelperText("Mindestens 10 Zeichen, mit Buchstaben und Ziffern");
        firstName.setWidthFull();
        lastName.setWidthFull();
        email.setWidthFull();
        password.setWidthFull();
        repeat.setWidthFull();
        firstName.setRequiredIndicatorVisible(true);
        lastName.setRequiredIndicatorVisible(true);
        email.setRequiredIndicatorVisible(true);
        password.setRequiredIndicatorVisible(true);
        repeat.setRequiredIndicatorVisible(true);

        Button create = new Button("Konto erstellen", e -> register());
        create.addThemeVariants(ButtonVariant.LUMO_PRIMARY);
        create.addClickShortcut(Key.ENTER);
        // role=alert: the outcome is read out immediately.
        status.getElement().setAttribute("role", "alert");
        form.setPadding(false);
        form.add(firstName, lastName, email, password, repeat, create);
        add(new H1("Neues Konto"), form, status, new RouterLink("Zur Übersicht", PublicHomeView.class),
                new RouterLink("Ich habe schon ein Konto", LoginView.class));
    }

    private void register() {
        String problem = problem();
        if (problem != null) {
            status.setText(problem);
            return;
        }
        VaadinRequest request = VaadinRequest.getCurrent();
        String client = AdminSessions.clientKey(request.getHeader("X-Forwarded-For"), request.getRemoteAddr());
        try {
            sessions.register(email.getValue(), password.getValue(), firstName.getValue().trim(), lastName.getValue().trim(), client);
            form.setVisible(false);
            // Supabase answers the same for an address it already knows, so this can't reveal who has an account.
            status.setText("Fast geschafft! Wir haben dir eine E-Mail an " + email.getValue().trim() + " geschickt. "
                    + "Öffne den Link darin, um dein Konto zu bestätigen. Keine E-Mail bekommen? Dann hast du vielleicht "
                    + "schon ein Konto: Melde dich damit an.");
        } catch (SignInException e) {
            status.setText(e.getMessage());
        } catch (RuntimeException e) {
            status.setText("Das Konto konnte gerade nicht erstellt werden. Bitte versuche es später noch einmal.");
        }
    }

    private String problem() {
        if (firstName.getValue().isBlank() || lastName.getValue().isBlank()) {
            return "Bitte Vor- und Nachnamen angeben.";
        }
        if (email.getValue().isBlank() || email.isInvalid()) {
            return "Bitte eine gültige E-Mail-Adresse angeben.";
        }
        if (!strongEnough(password.getValue())) {
            return "Das Passwort braucht mindestens 10 Zeichen, mit Buchstaben und Ziffern.";
        }
        return password.getValue().equals(repeat.getValue()) ? null : "Die Passwörter stimmen nicht überein.";
    }

    /** As the app's Validation.passwordMeetsMinimumStrength. */
    static boolean strongEnough(String password) {
        return password.length() >= 10 && password.chars().anyMatch(Character::isLetter)
                && password.chars().anyMatch(Character::isDigit);
    }
}
