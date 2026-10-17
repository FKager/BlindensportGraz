package it.a11y.blindensport.webadmin.ui;

import com.vaadin.flow.component.notification.Notification;
import com.vaadin.flow.component.notification.NotificationVariant;
import it.a11y.blindensport.webadmin.supabase.DbErrorMessages;
import it.a11y.blindensport.webadmin.supabase.SupabaseException;

/**
 * Status messages. Vaadin notifications live in an ARIA live region, so
 * VoiceOver reads them out; errors use the assertive politeness and stay
 * longer (many club admins use a screen reader).
 */
public final class Announcer {
    private Announcer() {
    }

    public static void success(String message) {
        Notification n = Notification.show(message, 4000, Notification.Position.BOTTOM_START);
        n.addThemeVariants(NotificationVariant.LUMO_SUCCESS);
    }

    public static void error(String message) {
        Notification n = new Notification(message, 10000, Notification.Position.BOTTOM_START);
        n.setAssertive(true);
        n.addThemeVariants(NotificationVariant.LUMO_ERROR);
        n.open();
    }

    /** German text for a failed action: database refusals translated, anything else generic. */
    public static void failed(String action, RuntimeException e) {
        if (e instanceof SupabaseException se) {
            error(action + " fehlgeschlagen: " + DbErrorMessages.german(se));
        } else if (e instanceof java.io.UncheckedIOException) {
            error(action + " fehlgeschlagen: Die Datenbank ist gerade nicht erreichbar.");
        } else if (e instanceof IllegalArgumentException) {
            error(action + " fehlgeschlagen: " + e.getMessage());
        } else {
            error(action + " fehlgeschlagen.");
        }
    }
}
