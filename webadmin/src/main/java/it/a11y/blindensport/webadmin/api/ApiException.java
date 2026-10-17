package it.a11y.blindensport.webadmin.api;

/** An API error answered as {@code {"error": true, "reason": "..."}} — the shape Vapor's Abort produced. */
public class ApiException extends RuntimeException {
    private final int status;

    public ApiException(int status, String reason) {
        super(reason);
        this.status = status;
    }

    public int status() {
        return status;
    }

    public static ApiException notFound(String id) {
        return new ApiException(404, "No member with id " + id + ".");
    }

    public static ApiException forbidden(String permission) {
        return new ApiException(403, "Keine Berechtigung (" + permission + ").");
    }
}
