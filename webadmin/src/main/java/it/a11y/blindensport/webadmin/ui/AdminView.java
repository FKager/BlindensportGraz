package it.a11y.blindensport.webadmin.ui;

import com.vaadin.flow.component.html.H1;
import com.vaadin.flow.component.orderedlayout.VerticalLayout;
import com.vaadin.flow.router.BeforeEnterEvent;
import com.vaadin.flow.router.BeforeEnterObserver;
import it.a11y.blindensport.webadmin.auth.AdminSession;
import it.a11y.blindensport.webadmin.auth.AdminSessions;
import it.a11y.blindensport.webadmin.auth.SessionExpiredException;

import java.util.function.Supplier;

/**
 * Base of the signed-in pages: a page heading (h1 — VoiceOver users jump
 * between headings), the current admin, and {@link #attempt} for actions,
 * which turns database refusals into announced German messages and an
 * ended session into the sign-in page.
 */
public abstract class AdminView extends VerticalLayout implements BeforeEnterObserver {
    protected final AdminSessions sessions;
    private AdminSession session;

    protected AdminView(AdminSessions sessions, String heading) {
        this.sessions = sessions;
        addClassName("view-content");
        add(new H1(heading));
    }

    @Override
    public void beforeEnter(BeforeEnterEvent event) {
        session = UiSession.current(sessions).orElse(null);
        if (session != null) {
            attempt("Laden", this::refresh);
        }
    }

    /** Reloads the page's data. Called on every navigation to the page. */
    protected abstract void refresh();

    protected AdminSession session() {
        AdminSession current = UiSession.current(sessions).orElse(null);
        if (current == null) {
            throw new SessionExpiredException();
        }
        session = current;
        return current;
    }

    protected boolean can(String permission) {
        return session != null && session.can(permission);
    }

    /** Runs an action; on failure announces "‹action› fehlgeschlagen: …". Returns false on failure. */
    protected boolean attempt(String action, Runnable work) {
        return attempt(action, () -> {
            work.run();
            return Boolean.TRUE;
        }) != null;
    }

    protected <T> T attempt(String action, Supplier<T> work) {
        try {
            return work.get();
        } catch (SessionExpiredException e) {
            UiSession.signOut(sessions);
            getUI().ifPresent(ui -> ui.navigate(LoginView.class));
            Announcer.error(e.getMessage());
            return null;
        } catch (RuntimeException e) {
            Announcer.failed(action, e);
            return null;
        }
    }
}
