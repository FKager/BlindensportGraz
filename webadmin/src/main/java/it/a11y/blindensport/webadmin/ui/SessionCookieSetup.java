package it.a11y.blindensport.webadmin.ui;

import jakarta.servlet.ServletContextEvent;
import jakarta.servlet.ServletContextListener;
import jakarta.servlet.annotation.WebListener;
import org.eclipse.microprofile.config.ConfigProvider;

/**
 * Vaadin's HTTP session cookie (JSESSIONID): HttpOnly, and Secure unless
 * SESSION_COOKIE_SECURE=false (local plain-http testing). SameSite=Strict
 * comes from quarkus.http.same-site-cookie in application.properties.
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
