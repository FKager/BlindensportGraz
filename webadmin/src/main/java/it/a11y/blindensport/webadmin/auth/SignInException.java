package it.a11y.blindensport.webadmin.auth;

/** A refused sign-in, with the HTTP status the REST API answers and a German message. */
public class SignInException extends RuntimeException {
    private final int status;

    public SignInException(int status, String message) {
        super(message);
        this.status = status;
    }

    public int status() {
        return status;
    }
}
