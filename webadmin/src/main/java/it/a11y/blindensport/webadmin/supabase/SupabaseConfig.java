package it.a11y.blindensport.webadmin.supabase;

import io.smallrye.config.ConfigMapping;

import java.util.Optional;

/** {@code supabase.*} in application.properties (SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_KEY). */
@ConfigMapping(prefix = "supabase")
public interface SupabaseConfig {

    /** e.g. https://&lt;ref&gt;.supabase.co */
    String url();

    /** Anon / publishable key: sent as {@code apikey} on every user request. */
    String anonKey();

    /** Service-role / secret key. Only the calendar feed uses it; it bypasses RLS. */
    Optional<String> serviceKey();
}
