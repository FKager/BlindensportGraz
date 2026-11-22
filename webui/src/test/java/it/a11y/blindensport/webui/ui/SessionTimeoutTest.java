package it.a11y.blindensport.webui.ui;

import com.github.mvysny.kaributesting.v10.MockVaadin;
import com.vaadin.flow.server.VaadinSession;
import it.a11y.blindensport.webui.auth.AdminSessions;
import jakarta.servlet.ServletContext;
import jakarta.servlet.ServletContextEvent;
import jakarta.servlet.SessionCookieConfig;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Proxy;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.assertEquals;

/**
 * Sessions without a sign-in (every visit to the start page makes one) go
 * after 10 idle minutes; a signed-in session keeps its 30 minutes.
 */
class SessionTimeoutTest {
    @BeforeEach
    void setUp() {
        MockVaadin.setup();
    }

    @AfterEach
    void tearDown() {
        MockVaadin.tearDown();
    }

    @Test
    void newSessionsTimeOutAfterTenIdleMinutes() {
        AtomicInteger timeout = new AtomicInteger(-1);
        SessionCookieConfig cookies = (SessionCookieConfig) Proxy.newProxyInstance(getClass().getClassLoader(),
                new Class<?>[]{SessionCookieConfig.class}, (proxy, method, args) -> null);
        ServletContext context = (ServletContext) Proxy.newProxyInstance(getClass().getClassLoader(),
                new Class<?>[]{ServletContext.class}, (proxy, method, args) -> switch (method.getName()) {
                    case "getSessionCookieConfig" -> cookies;
                    case "setSessionTimeout" -> {
                        timeout.set((Integer) args[0]);
                        yield null;
                    }
                    default -> null;
                });

        new SessionCookieSetup().contextInitialized(new ServletContextEvent(context));

        assertEquals(10, timeout.get());
    }

    @Test
    void signingInKeepsTheSignInsIdleTimeAndSigningOutShortensItAgain() {
        VaadinSession vaadin = VaadinSession.getCurrent();

        UiSession.useSignedInTimeout(vaadin);
        assertEquals(AdminSessions.IDLE_TIMEOUT.toSeconds(), vaadin.getSession().getMaxInactiveInterval());

        UiSession.useAnonymousTimeout(vaadin);
        assertEquals(600, vaadin.getSession().getMaxInactiveInterval());
    }
}
