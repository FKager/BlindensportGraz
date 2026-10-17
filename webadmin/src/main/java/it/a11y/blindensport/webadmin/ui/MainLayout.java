package it.a11y.blindensport.webadmin.ui;

import com.vaadin.flow.component.applayout.AppLayout;
import com.vaadin.flow.component.applayout.DrawerToggle;
import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.button.ButtonVariant;
import com.vaadin.flow.component.html.Span;
import com.vaadin.flow.component.orderedlayout.FlexComponent;
import com.vaadin.flow.component.orderedlayout.HorizontalLayout;
import com.vaadin.flow.component.sidenav.SideNav;
import com.vaadin.flow.component.sidenav.SideNavItem;
import com.vaadin.flow.router.AfterNavigationEvent;
import com.vaadin.flow.router.AfterNavigationObserver;
import com.vaadin.flow.router.RouterLayout;
import it.a11y.blindensport.webadmin.auth.AdminSession;
import it.a11y.blindensport.webadmin.auth.AdminSessions;
import jakarta.inject.Inject;

import java.util.Arrays;
import java.util.List;

/**
 * Frame of every signed-in page: title, who is signed in, sign-out, and
 * the navigation — only the pages the admin's permissions open.
 */
public class MainLayout extends AppLayout implements RouterLayout, AfterNavigationObserver {
    /** Navigation entries in menu order. Views are added here as they are built. */
    public record NavEntry(String label, Class<? extends com.vaadin.flow.component.Component> view) {
    }

    static final List<NavEntry> ENTRIES = List.of(
            new NavEntry("Übersicht", StartView.class),
            new NavEntry("Mitglieder", MembersView.class),
            new NavEntry("Änderungsanträge", ChangeRequestsView.class),
            new NavEntry("App-Konten", AccountsView.class),
            new NavEntry("Rollen-Protokoll", RoleLogView.class));

    private final AdminSessions sessions;
    private final SideNav nav = new SideNav();
    private final Span who = new Span();

    @Inject
    public MainLayout(AdminSessions sessions) {
        this.sessions = sessions;
        setPrimarySection(Section.DRAWER);

        Span title = new Span("Blindensport Graz – Verwaltung");
        title.getStyle().set("font-weight", "600");
        Button signOut = new Button("Abmelden", e -> {
            UiSession.signOut(sessions);
            getUI().ifPresent(ui -> ui.navigate(LoginView.class, com.vaadin.flow.router.QueryParameters.of("abgemeldet", "1")));
        });
        signOut.addThemeVariants(ButtonVariant.LUMO_TERTIARY);

        HorizontalLayout header = new HorizontalLayout(new DrawerToggle(), title, who, signOut);
        header.setDefaultVerticalComponentAlignment(FlexComponent.Alignment.CENTER);
        header.setFlexGrow(1, title);
        header.setWidthFull();
        header.getStyle().set("padding-right", "var(--lumo-space-m)");
        addToNavbar(header);

        nav.setLabel("Bereiche");
        addToDrawer(nav);
    }

    @Override
    public void afterNavigation(AfterNavigationEvent event) {
        AdminSession session = UiSession.current(sessions).orElse(null);
        if (session == null) {
            return;
        }
        who.setText("Angemeldet als " + session.email() + " (" + session.roleName() + ")");
        nav.removeAll();
        for (NavEntry entry : ENTRIES) {
            if (allowed(session, entry.view())) {
                nav.addItem(new SideNavItem(entry.label(), entry.view()));
            }
        }
    }

    static boolean allowed(AdminSession session, Class<?> view) {
        RequiresPermission required = view.getAnnotation(RequiresPermission.class);
        return required == null || Arrays.stream(required.value()).anyMatch(session::can);
    }
}
