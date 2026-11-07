package it.a11y.blindensport.webui.ui;

import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.button.ButtonVariant;
import com.vaadin.flow.component.html.H1;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.orderedlayout.VerticalLayout;
import com.vaadin.flow.router.BeforeEnterEvent;
import com.vaadin.flow.router.BeforeEnterObserver;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.router.RouterLink;
import it.a11y.blindensport.webui.supabase.Supabase;
import jakarta.inject.Inject;

import java.util.regex.Pattern;

/**
 * Where the confirmation email of a web registration leads. Confirming takes a
 * click: mail scanners open links by themselves, and the link works only once.
 */
@Route("konto-bestaetigen")
@PageTitle("Konto bestätigen – Blindensport Graz")
public class ConfirmEmailView extends VerticalLayout implements BeforeEnterObserver {
    private static final Pattern TOKEN = Pattern.compile("[A-Za-z0-9_-]{1,128}");

    private final Supabase supabase;
    private final Paragraph status = new Paragraph();
    private final Button confirm = new Button("Konto bestätigen", e -> confirm());
    private String tokenHash;

    @Inject
    public ConfirmEmailView(Supabase supabase) {
        this.supabase = supabase;
        setMaxWidth("26rem");
        getStyle().set("margin", "2rem auto");
        confirm.addThemeVariants(ButtonVariant.LUMO_PRIMARY);
        status.getElement().setAttribute("role", "alert");
        add(new H1("Konto bestätigen"), confirm, status, new RouterLink("Anmelden", LoginView.class),
                new RouterLink("Zur Übersicht", PublicHomeView.class));
    }

    @Override
    public void beforeEnter(BeforeEnterEvent event) {
        tokenHash = event.getLocation().getQueryParameters().getSingleParameter("token_hash").orElse("");
        if (!TOKEN.matcher(tokenHash).matches()) {
            confirm.setVisible(false);
            status.setText("Dieser Link ist ungültig.");
        }
    }

    private void confirm() {
        boolean done;
        try {
            done = supabase.auth().confirmEmail(tokenHash);
        } catch (RuntimeException e) {
            status.setText("Das hat gerade nicht geklappt. Bitte versuche es später noch einmal.");
            return;
        }
        confirm.setVisible(false);
        status.setText(done ? "Dein Konto ist bestätigt. Du kannst dich jetzt anmelden."
                : "Dieser Link ist ungültig oder abgelaufen. Vielleicht ist dein Konto schon bestätigt: Versuche, dich anzumelden.");
    }
}
