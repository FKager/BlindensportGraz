package it.a11y.blindensport.webui.ui;

import com.vaadin.flow.server.VaadinRequest;
import com.vaadin.flow.server.VaadinService;
import com.vaadin.flow.server.VaadinSession;
import it.a11y.blindensport.webui.auth.AdminSession;
import it.a11y.blindensport.webui.auth.AdminSessions;

import java.util.Optional;

/**
 * The Vaadin side of a sign-in: the {@link AdminSessions} token lives in the
 * VaadinSession, so UI and REST share timeouts, role rechecks and sign-out.
 */
public final class UiSession {
    private static final String TOKEN = UiSession.class.getName() + ".token";
    /** Idle minutes until a session without a sign-in goes (bots, visitors of the start page). */
    public static final int ANONYMOUS_TIMEOUT_MINUTES = 10;

    private UiSession() {
    }

    public static Optional<AdminSession> current(AdminSessions sessions) {
        VaadinSession vaadin = VaadinSession.getCurrent();
        if (vaadin == null) {
            return Optional.empty();
        }
        Object token = vaadin.getAttribute(TOKEN);
        Optional<AdminSession> session = sessions.get(token instanceof String s ? s : null);
        if (session.isEmpty() && token != null) {
            vaadin.setAttribute(TOKEN, null);
        }
        return session;
    }

    public static void signedIn(String token) {
        // New HTTP session id on sign-in (session fixation); Vaadin carries its state over.
        VaadinService.reinitializeSession(VaadinRequest.getCurrent());
        VaadinSession.getCurrent().setAttribute(TOKEN, token);
        useSignedInTimeout(VaadinSession.getCurrent());
    }

    /** A signed-in session stays as long as its sign-in may idle (AdminSessions). */
    static void useSignedInTimeout(VaadinSession vaadin) {
        vaadin.getSession().setMaxInactiveInterval((int) AdminSessions.IDLE_TIMEOUT.toSeconds());
    }

    static void useAnonymousTimeout(VaadinSession vaadin) {
        vaadin.getSession().setMaxInactiveInterval(ANONYMOUS_TIMEOUT_MINUTES * 60);
    }

    public static void signOut(AdminSessions sessions) {
        VaadinSession vaadin = VaadinSession.getCurrent();
        if (vaadin == null) {
            return;
        }
        Object token = vaadin.getAttribute(TOKEN);
        sessions.remove(token instanceof String s ? s : null);
        vaadin.setAttribute(TOKEN, null);
        useAnonymousTimeout(vaadin);
    }
}
