package it.a11y.blindensport.webadmin.supabase;

import java.util.Map;

/**
 * German texts for the errors the database raises (supabase/migrations:
 * {@code raise exception '...'} in the RPCs, plus RLS refusals and unique
 * constraints). Unknown messages fall back to a generic text — raw Postgres
 * messages are never shown.
 */
public final class DbErrorMessages {
    private static final Map<String, String> RAISED = Map.ofEntries(
            Map.entry("not signed in", "Nicht angemeldet. Bitte erneut anmelden."),
            Map.entry("not allowed", "Keine Berechtigung für diese Aktion."),
            Map.entry("unknown user", "Dieses Konto gibt es nicht (mehr)."),
            Map.entry("cannot change your own role", "Die eigene Rolle kann nicht geändert werden."),
            Map.entry("cannot block your own account", "Das eigene Konto kann nicht gesperrt werden."),
            Map.entry("not allowed on your own account", "Beim eigenen Konto nicht möglich."),
            Map.entry("use Konto löschen for your own account",
                    "Das eigene Konto bitte in der App unter „Konto löschen“ entfernen."),
            Map.entry("cannot remove the last root account", "Das letzte Root-Konto kann nicht entfernt werden."),
            Map.entry("demote the root account first", "Root-Konten zuerst auf eine andere Rolle zurückstufen."),
            Map.entry("no pending request", "Es liegt keine offene Anfrage vor."));

    private DbErrorMessages() {
    }

    public static String german(SupabaseException e) {
        String raised = RAISED.get(e.dbMessage());
        if (raised != null) {
            return raised;
        }
        if (e.isPermissionDenied()) {
            return "Keine Berechtigung für diese Aktion.";
        }
        if ("23505".equals(e.code())) {
            return "Ein Eintrag mit diesem Wert existiert bereits.";
        }
        if ("23503".equals(e.code())) {
            return "Der Eintrag wird noch verwendet oder verweist auf etwas, das es nicht gibt.";
        }
        if (e.isUnauthenticated()) {
            return "Die Sitzung ist abgelaufen. Bitte erneut anmelden.";
        }
        return "Die Datenbank hat die Anfrage abgelehnt (Fehler " + e.status() + ").";
    }
}
