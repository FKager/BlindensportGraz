package it.a11y.blindensport.webui.ui;

import com.vaadin.flow.router.BeforeEnterEvent;
import com.vaadin.flow.server.ServiceInitEvent;
import it.a11y.blindensport.webui.auth.AdminSession;
import it.a11y.blindensport.webui.auth.AdminSessions;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.inject.Inject;

import java.util.Arrays;
import java.util.Optional;
import java.util.Set;

/**
 * Every navigation: no valid session → sign-in page, except the public pages;
 * an account without club access → the Übersicht; a view marked
 * {@link RequiresPermission} without that permission → start page. This
 * only decides what is shown — Supabase RLS still enforces every read and
 * write, since the UI acts as the signed-in admin.
 */
@ApplicationScoped
public class AccessGuard {
    private static final Set<Class<?>> PUBLIC =
            Set.of(LoginView.class, RegisterView.class, ConfirmEmailView.class, PublicHomeView.class,
                    ForgotPasswordView.class, ResetPasswordView.class);

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
        if (PUBLIC.contains(target)) {
            return;
        }
        Optional<AdminSession> session = UiSession.current(sessions);
        if (session.isEmpty()) {
            event.forwardTo(LoginView.class);
            return;
        }
        // Accounts without club access yet: the Übersicht and nothing else.
        if (!session.get().canUseWebUi()) {
            event.forwardTo(PublicHomeView.class);
            return;
        }
        RequiresPermission required = target.getAnnotation(RequiresPermission.class);
        if (required != null && Arrays.stream(required.value()).noneMatch(session.get()::can)) {
            Announcer.error("Keine Berechtigung für diese Seite.");
            event.forwardTo(StartView.class);
        }
    }
}
