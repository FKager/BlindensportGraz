package it.a11y.blindensport.webadmin.ui;

import com.vaadin.flow.router.BeforeEnterEvent;
import com.vaadin.flow.server.ServiceInitEvent;
import it.a11y.blindensport.webadmin.auth.AdminSession;
import it.a11y.blindensport.webadmin.auth.AdminSessions;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.inject.Inject;

import java.util.Arrays;
import java.util.Optional;

/**
 * Every navigation: no valid session → sign-in page; a view marked
 * {@link RequiresPermission} without that permission → start page. This
 * only decides what is shown — Supabase RLS still enforces every read and
 * write, since the UI acts as the signed-in admin.
 */
@ApplicationScoped
public class AccessGuard {
    @Inject
    AdminSessions sessions;

    /** Fired by Vaadin's Quarkus extension as a CDI event when the service starts. */
    void serviceInit(@Observes ServiceInitEvent event) {
        event.getSource().addUIInitListener(init -> {
            var ui = init.getUI();
            ui.setLocale(java.util.Locale.GERMAN);
            ui.getElement().executeJs("document.documentElement.lang = 'de'");
            ui.addBeforeEnterListener(this::check);
        });
    }

    private void check(BeforeEnterEvent event) {
        Class<?> target = event.getNavigationTarget();
        if (target == LoginView.class) {
            return;
        }
        Optional<AdminSession> session = UiSession.current(sessions);
        if (session.isEmpty()) {
            event.forwardTo(LoginView.class);
            return;
        }
        RequiresPermission required = target.getAnnotation(RequiresPermission.class);
        if (required != null && Arrays.stream(required.value()).noneMatch(session.get()::can)) {
            Announcer.error("Keine Berechtigung für diese Seite.");
            event.forwardTo(StartView.class);
        }
    }
}
