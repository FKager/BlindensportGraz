package it.a11y.blindensport.webui.ui;

import com.vaadin.flow.component.Key;
import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.button.ButtonVariant;
import com.vaadin.flow.component.html.H1;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.orderedlayout.VerticalLayout;
import com.vaadin.flow.component.textfield.PasswordField;
import com.vaadin.flow.router.BeforeEnterEvent;
import com.vaadin.flow.router.BeforeEnterObserver;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.router.RouterLink;
import it.a11y.blindensport.webui.supabase.GoTrue;
import it.a11y.blindensport.webui.supabase.Supabase;
import jakarta.inject.Inject;

import java.util.regex.Pattern;

/**
 * Where the reset email of a web request leads. The link works only once and
 * is used up on the button's click, not on opening the page, since mail scanners
 * open links by themselves. The session it gives stays here until the password
 * is set, so a password Supabase refuses can be corrected without a new link.
 */
@Route("passwort-neu")
@PageTitle("Neues Passwort – Blindensport Graz")
public class ResetPasswordView extends VerticalLayout implements BeforeEnterObserver {
    private static final Pattern TOKEN = Pattern.compile("[A-Za-z0-9_-]{1,128}");

    private final Supabase supabase;
    private final PasswordField password = new PasswordField("Neues Passwort");
    private final PasswordField repeat = new PasswordField("Passwort wiederholen");
    private final Button save = new Button("Passwort speichern", e -> save());
    private final Paragraph status = new Paragraph();
    private String tokenHash;
    private String accessToken;

    @Inject
    public ResetPasswordView(Supabase supabase) {
        this.supabase = supabase;
        setMaxWidth("26rem");
        getStyle().set("margin", "2rem auto");
        password.setWidthFull();
        repeat.setWidthFull();
        password.setRequiredIndicatorVisible(true);
        repeat.setRequiredIndicatorVisible(true);
        password.setHelperText("Mindestens 10 Zeichen, mit Buchstaben und Ziffern");
        password.setAutocomplete(com.vaadin.flow.component.textfield.Autocomplete.NEW_PASSWORD);
        repeat.setAutocomplete(com.vaadin.flow.component.textfield.Autocomplete.NEW_PASSWORD);
        save.addThemeVariants(ButtonVariant.LUMO_PRIMARY);
        save.addClickShortcut(Key.ENTER);
        status.getElement().setAttribute("role", "alert");
        add(new H1("Neues Passwort"), password, repeat, save, status, new RouterLink("Anmelden", LoginView.class));
    }

    @Override
    public void beforeEnter(BeforeEnterEvent event) {
        tokenHash = event.getLocation().getQueryParameters().getSingleParameter("token_hash").orElse("");
        if (!TOKEN.matcher(tokenHash).matches()) {
            finish("Dieser Link ist ungültig.");
        }
    }

    private void save() {
        if (!RegisterView.strongEnough(password.getValue())) {
            status.setText("Das Passwort braucht mindestens 10 Zeichen, mit Buchstaben und Ziffern.");
            return;
        }
        if (!password.getValue().equals(repeat.getValue())) {
            status.setText("Die Passwörter stimmen nicht überein.");
            return;
        }
        try {
            if (accessToken == null) {
                accessToken = supabase.auth().recoverySession(tokenHash).orElse(null);
                if (accessToken == null) {
                    finish("Dieser Link ist ungültig oder abgelaufen. Bitte fordere einen neuen an.");
                    return;
                }
            }
            GoTrue.PasswordChange result = supabase.auth().changePassword(accessToken, password.getValue());
            if (result == GoTrue.PasswordChange.DONE) {
                supabase.auth().signOut(accessToken);
                accessToken = null;
                finish("Dein Passwort ist geändert. Du kannst dich jetzt anmelden.");
            } else if (result == GoTrue.PasswordChange.SAME_PASSWORD) {
                status.setText("Das ist dein bisheriges Passwort. Bitte wähle ein anderes.");
            } else {
                status.setText("Dieses Passwort wurde abgelehnt. Bitte wähle ein anderes.");
            }
        } catch (RuntimeException e) {
            status.setText("Das hat gerade nicht geklappt. Bitte versuche es später noch einmal.");
        }
    }

    private void finish(String message) {
        password.setVisible(false);
        repeat.setVisible(false);
        save.setVisible(false);
        status.setText(message);
    }
}
