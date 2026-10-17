package it.a11y.blindensport.webadmin.ui;

import com.vaadin.flow.component.html.H1;
import com.vaadin.flow.component.html.ListItem;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.html.UnorderedList;
import com.vaadin.flow.component.orderedlayout.VerticalLayout;
import com.vaadin.flow.router.BeforeEnterEvent;
import com.vaadin.flow.router.BeforeEnterObserver;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.router.RouterLink;
import it.a11y.blindensport.webadmin.auth.AdminSessions;
import jakarta.inject.Inject;

/** Start page: the areas this admin may open, as a plain link list. */
@Route(value = "", layout = MainLayout.class)
@PageTitle("Übersicht – Blindensport Graz")
public class StartView extends VerticalLayout implements BeforeEnterObserver {
    private final AdminSessions sessions;
    private final UnorderedList links = new UnorderedList();

    @Inject
    public StartView(AdminSessions sessions) {
        this.sessions = sessions;
        add(new H1("Übersicht"), new Paragraph("Bereiche, die Sie mit Ihrer Rolle bearbeiten können:"), links);
    }

    @Override
    public void beforeEnter(BeforeEnterEvent event) {
        links.removeAll();
        UiSession.current(sessions).ifPresent(session -> MainLayout.ENTRIES.stream()
                .filter(entry -> entry.view() != StartView.class && MainLayout.allowed(session, entry.view()))
                .forEach(entry -> links.add(new ListItem(new RouterLink(entry.label(), entry.view())))));
    }
}
