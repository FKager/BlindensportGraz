package it.a11y.blindensport.webui.supabase;

import java.util.List;
import java.util.Map;
import java.util.function.Supplier;

/**
 * Supabase Storage ({@code storage/v1}) with one identity, like {@link Postgrest}:
 * as a signed-in user the bucket's policies on {@code storage.objects} apply.
 * Object paths are a single segment here ({@code <row id>.<ext>}).
 */
public final class Storage {
    private final SupabaseHttp http;
    private final String apiKey;
    private final Supplier<String> bearer;

    Storage(SupabaseHttp http, String apiKey, Supplier<String> bearer) {
        this.http = http;
        this.apiKey = apiKey;
        this.bearer = bearer;
    }

    /** Creates or replaces the object. */
    public void upload(String bucket, String path, byte[] content, String contentType) {
        check(http.sendBytes("POST", object(bucket, path), content, contentType,
                Map.of("x-upsert", "true", "Cache-Control", "no-cache"), apiKey, bearer.get()), "upload " + bucket);
    }

    public byte[] download(String bucket, String path) {
        return check(http.sendBytes("GET", object(bucket, path), null, null, Map.of(), apiKey, bearer.get()),
                "download " + bucket).body();
    }

    /** Removes the objects; missing ones are no error. */
    public void remove(String bucket, List<String> paths) {
        if (paths.isEmpty()) {
            return;
        }
        byte[] body = http.json().valueToTree(Map.of("prefixes", paths)).toString()
                .getBytes(java.nio.charset.StandardCharsets.UTF_8);
        check(http.sendBytes("DELETE", "storage/v1/object/" + SupabaseHttp.encodeSegment(bucket), body,
                "application/json", Map.of(), apiKey, bearer.get()), "remove " + bucket);
    }

    private static String object(String bucket, String path) {
        return "storage/v1/object/" + SupabaseHttp.encodeSegment(bucket) + "/" + SupabaseHttp.encodeSegment(path);
    }

    private SupabaseHttp.BytesResult check(SupabaseHttp.BytesResult result, String what) {
        if (!result.ok()) {
            http.check(result.asText(), what);
        }
        return result;
    }
}
