package it.a11y.blindensport.webadmin.api;

import com.github.tomakehurst.wiremock.WireMockServer;
import io.quarkus.test.common.QuarkusTestResourceLifecycleManager;

import java.util.Map;

import static com.github.tomakehurst.wiremock.core.WireMockConfiguration.options;

/** A WireMock stand-in for the Supabase project (GoTrue + PostgREST) during @QuarkusTest. */
public class SupabaseMock implements QuarkusTestResourceLifecycleManager {
    static WireMockServer server;

    @Override
    public Map<String, String> start() {
        server = new WireMockServer(options().dynamicPort());
        server.start();
        return Map.of("supabase.url", server.baseUrl());
    }

    @Override
    public void stop() {
        if (server != null) {
            server.stop();
        }
    }
}
