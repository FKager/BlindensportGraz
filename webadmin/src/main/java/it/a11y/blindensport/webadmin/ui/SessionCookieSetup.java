package it.a11y.blindensport.webadmin.ui;

import jakarta.servlet.ServletContextEvent;
import jakarta.servlet.ServletContextListener;
import jakarta.servlet.annotation.WebListener;
import org.eclipse.microprofile.config.ConfigProvider;

/**
 * Vaadin's HTTP session cookie (JSESSIONID): HttpOnly, and Secure unless
 * SESSION_COOKIE_SECURE=false (local plain-http testing). SameSite is NOT
 * applied — Quarkus' Undertow ignores both this attribute and
 * quarkus.http.same-site-cookie for JSESSIONID (checked on nuc 2026-10-17).
 * Vaadin's own per-UI CSRF token protects UI requests; the REST API's
 * bsg_admin_session cookie is SameSite=Strict.
 */
@WebListener
public class SessionCookieSetup implements ServletContextListener {
    @Override
    public void contextInitialized(ServletContextEvent event) {
        boolean secure = ConfigProvider.getConfig()
                .getOptionalValue("webadmin.session-cookie-secure", Boolean.class).orElse(true);
        var cookie = event.getServletContext().getSessionCookieConfig();
        cookie.setHttpOnly(true);
        cookie.setSecure(secure);
    }
}
