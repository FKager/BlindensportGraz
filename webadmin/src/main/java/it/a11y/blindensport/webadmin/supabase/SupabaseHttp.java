package it.a11y.blindensport.webadmin.supabase;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * Raw HTTP to one Supabase project (GoTrue under {@code auth/v1}, PostgREST
 * under {@code rest/v1}). Blocking on purpose: Vaadin and the REST resources
 * run on worker threads.
 */
public final class SupabaseHttp {
    /** One query item, e.g. {@code ("id", "eq.<uuid>")} — PostgREST filters keep their order. */
    public record Param(String name, String value) {
    }

    public record Result(int status, String body) {
        public boolean ok() {
            return status >= 200 && status < 300;
        }
    }

    private static final HttpClient CLIENT = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .build();

    private final URI baseURL;
    private final ObjectMapper json;

    public SupabaseHttp(String baseURL, ObjectMapper json) {
        this.baseURL = URI.create(baseURL.endsWith("/") ? baseURL : baseURL + "/");
        this.json = json;
    }

    public ObjectMapper json() {
        return json;
    }

    /**
     * @param apiKey  sent as {@code apikey}
     * @param bearer  {@code Authorization: Bearer …} (user JWT or legacy JWT service key), or null
     */
    public Result send(String method, String path, List<Param> query, Object body,
                       Map<String, String> headers, String apiKey, String bearer) {
        String url = baseURL.resolve(path).toString();
        if (query != null && !query.isEmpty()) {
            url += "?" + query.stream()
                    .map(p -> encode(p.name()) + "=" + encode(p.value()))
                    .collect(Collectors.joining("&"));
        }
        HttpRequest.Builder request = HttpRequest.newBuilder(URI.create(url))
                .timeout(Duration.ofSeconds(30))
                .header("apikey", apiKey)
                .header("Accept", "application/json");
        if (bearer != null) {
            request.header("Authorization", "Bearer " + bearer);
        }
        headers.forEach(request::header);
        if (body != null) {
            request.header("Content-Type", "application/json");
            request.method(method, HttpRequest.BodyPublishers.ofString(write(body)));
        } else {
            request.method(method, HttpRequest.BodyPublishers.noBody());
        }
        try {
            HttpResponse<String> response = CLIENT.send(request.build(),
                    HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            return new Result(response.statusCode(), response.body());
        } catch (IOException e) {
            throw new UncheckedIOException("Supabase nicht erreichbar: " + e.getMessage(), e);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Supabase request interrupted", e);
        }
    }

    /** Throws {@link SupabaseException} unless 2xx. */
    public Result check(Result result, String what) {
        if (!result.ok()) {
            throw new SupabaseException(what, result.status(), result.body(), tryParse(result.body()));
        }
        return result;
    }

    public JsonNode parse(String body) {
        try {
            return json.readTree(body == null || body.isBlank() ? "null" : body);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("Supabase answered with invalid JSON", e);
        }
    }

    private JsonNode tryParse(String body) {
        try {
            return body == null || body.isBlank() ? null : json.readTree(body);
        } catch (JsonProcessingException e) {
            return null;
        }
    }

    private String write(Object body) {
        try {
            return json.writeValueAsString(body);
        } catch (JsonProcessingException e) {
            throw new IllegalArgumentException("Cannot encode request body", e);
        }
    }

    private static String encode(String s) {
        return URLEncoder.encode(s, StandardCharsets.UTF_8).replace("+", "%20");
    }
}
