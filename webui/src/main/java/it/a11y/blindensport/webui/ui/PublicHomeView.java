package it.a11y.blindensport.webui.ui;

import com.vaadin.flow.component.UI;
import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.html.H1;
import com.vaadin.flow.component.html.H2;
import com.vaadin.flow.component.html.H3;
import com.vaadin.flow.component.html.ListItem;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.html.UnorderedList;
import com.vaadin.flow.component.orderedlayout.HorizontalLayout;
import com.vaadin.flow.component.orderedlayout.VerticalLayout;
import com.vaadin.flow.router.BeforeEnterEvent;
import com.vaadin.flow.router.BeforeEnterObserver;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.router.RouterLink;
import it.a11y.blindensport.webui.auth.AdminSession;
import it.a11y.blindensport.webui.auth.AdminSessions;
import it.a11y.blindensport.webui.club.PublicSchedule;
import it.a11y.blindensport.webui.members.Dates;
import it.a11y.blindensport.webui.supabase.Supabase;
import jakarta.inject.Inject;

import java.time.LocalDate;
import java.util.List;

/**
 * The start page without an account, and for accounts without club access yet:
 * upcoming trainings and tournaments with name, day and location, like the
 * app's Übersicht. Coaches, admins and root go on to the administration.
 */
@Route("")
@PageTitle("Übersicht – Blindensport Graz")
public class PublicHomeView extends VerticalLayout implements BeforeEnterObserver {
    private final AdminSessions sessions;
    private final Supabase supabase;
    private final HorizontalLayout actions = new HorizontalLayout();
    private final VerticalLayout schedule = new VerticalLayout();

    @Inject
    public PublicHomeView(AdminSessions sessions, Supabase supabase) {
        this.sessions = sessions;
        this.supabase = supabase;
        setMaxWidth("44rem");
        getStyle().set("margin", "2rem auto");
        schedule.setPadding(false);
        add(new H1("Blindensport Graz"), actions, schedule);
    }

    @Override
    public void beforeEnter(BeforeEnterEvent event) {
        AdminSession session = UiSession.current(sessions).orElse(null);
        if (session != null && session.canUseWebUi()) {
            event.forwardTo(StartView.class);
            return;
        }
        actions.removeAll();
        if (session == null) {
            actions.add(new RouterLink("Anmelden", LoginView.class), new RouterLink("Registrieren", RegisterView.class));
        } else {
            actions.add(new Paragraph("Angemeldet als " + session.email() + ". Den vollen Zugang schaltet ein Admin des Vereins frei."),
                    new Button("Abmelden", e -> {
                        UiSession.signOut(sessions);
                        UI.getCurrent().getPage().reload();
                    }));
        }
        showSchedule();
    }

    private void showSchedule() {
        schedule.removeAll();
        schedule.add(new H2("Kommende Termine"));
        List<PublicSchedule.Entry> entries;
        try {
            entries = PublicSchedule.upcoming(supabase.asAnon(), LocalDate.now(Dates.CLUB_ZONE));
        } catch (RuntimeException e) {
            schedule.add(new Paragraph("Die Termine können gerade nicht geladen werden. Bitte versuche es später noch einmal."));
            return;
        }
        if (entries.isEmpty()) {
            schedule.add(new Paragraph("Noch nichts geplant. Sobald etwas ansteht, siehst du es hier."));
        }
        section("Trainings", "training", entries);
        section("Turniere", "tournament", entries);
    }

    private void section(String heading, String kind, List<PublicSchedule.Entry> entries) {
        List<PublicSchedule.Entry> ofKind = entries.stream().filter(e -> kind.equals(e.kind())).toList();
        if (ofKind.isEmpty()) {
            return;
        }
        UnorderedList list = new UnorderedList();
        ofKind.forEach(e -> list.add(new ListItem(line(e))));
        schedule.add(new H3(heading), list);
    }

    /** One line, so a screen reader gets it in one go: "Torball, 14.11.2026, Sporthalle". */
    static String line(PublicSchedule.Entry e) {
        String days = e.firstDay().equals(e.lastDay()) ? GermanUi.DAY.format(e.firstDay())
                : GermanUi.DAY.format(e.firstDay()) + " bis " + GermanUi.DAY.format(e.lastDay());
        return e.title() + ", " + days + (e.location().isBlank() ? "" : ", " + e.location());
    }
}
