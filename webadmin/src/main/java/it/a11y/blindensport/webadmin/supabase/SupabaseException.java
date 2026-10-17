package it.a11y.blindensport.webadmin.supabase;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * A Supabase call answered with a non-2xx status. {@link #code()} is the
 * Postgres SQLSTATE PostgREST reports (e.g. 42501 = not allowed by RLS or an
 * RPC's permission check), {@link #dbMessage()} the raw message. Show
 * {@link DbErrorMessages#german(SupabaseException)} to people, never the raw body.
 */
public class SupabaseException extends RuntimeException {
    private final int status;
    private final String code;
    private final String dbMessage;

    public SupabaseException(String what, int status, String body, JsonNode json) {
        super("Supabase " + what + " failed (" + status + "): " + body);
        this.status = status;
        this.code = json != null && json.hasNonNull("code") ? json.get("code").asText() : "";
        String message = "";
        if (json != null) {
            for (String key : new String[] {"message", "msg", "error_description", "error"}) {
                if (json.hasNonNull(key) && json.get(key).isTextual()) {
                    message = json.get(key).asText();
                    break;
                }
            }
        }
        this.dbMessage = message;
    }

    public int status() {
        return status;
    }

    public String code() {
        return code;
    }

    public String dbMessage() {
        return dbMessage;
    }

    /** RLS refused the row or an RPC said "not allowed". */
    public boolean isPermissionDenied() {
        return "42501".equals(code) || status == 403;
    }

    /** The access token is no longer accepted (expired, revoked, user deleted). */
    public boolean isUnauthenticated() {
        return status == 401;
    }
}
