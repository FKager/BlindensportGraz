package it.a11y.blindensport.webui.auth;

/** The admin's session ended: timed out, signed out, or Supabase no longer accepts it. */
public class SessionExpiredException extends RuntimeException {
    public SessionExpiredException() {
        super("Bitte erneut anmelden – die Sitzung ist abgelaufen.");
    }
}
