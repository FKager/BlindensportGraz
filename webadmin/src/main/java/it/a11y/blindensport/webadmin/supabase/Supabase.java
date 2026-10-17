package it.a11y.blindensport.webadmin.supabase;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

import java.util.function.Supplier;

/** Entry point to the club's Supabase project: auth, user-scoped and service-role PostgREST. */
@ApplicationScoped
public class Supabase {
    private final SupabaseConfig config;
    private final SupabaseHttp http;
    private final GoTrue goTrue;

    @Inject
    public Supabase(SupabaseConfig config, ObjectMapper json) {
        this.config = config;
        this.http = new SupabaseHttp(config.url(), json);
        this.goTrue = new GoTrue(http, config.anonKey());
    }

    public GoTrue auth() {
        return goTrue;
    }

    /** PostgREST as a signed-in user: RLS and the RPCs' own checks apply. */
    public Postgrest asUser(Supplier<String> accessToken) {
        return new Postgrest(http, config.anonKey(), accessToken);
    }

    /**
     * PostgREST as service role — bypasses RLS. Only for the calendar feed,
     * which authenticates by its own per-user token and has no user session.
     */
    public Postgrest asService() {
        String key = config.serviceKey().filter(k -> !k.isBlank())
                .orElseThrow(() -> new IllegalStateException("SUPABASE_SERVICE_KEY is not set"));
        // Legacy service_role keys are JWTs and also go in Authorization;
        // new sb_secret_ keys must only be sent as apikey.
        String bearer = key.startsWith("eyJ") ? key : null;
        return new Postgrest(http, key, () -> bearer);
    }
}
