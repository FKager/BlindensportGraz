package it.a11y.blindensport.bsg;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;

/** The web UI's REST API (/api), as the token's owner. */
public final class Api {
    /** The server refused or failed: exit code 1 with its German reason. */
    public static final class Failure extends RuntimeException {
        private final int status;

        public Failure(int status, String message) {
            super(message);
            this.status = status;
        }

        public int status() {
            return status;
        }
    }

    private static final ObjectMapper JSON = new ObjectMapper();

    private final Config config;
    private final HttpClient http;

    public Api(Config config) {
        this.config = config;
        this.http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
    }

    public JsonNode get(String path) {
        return send(HttpRequest.newBuilder(uri(path)).GET());
    }

    public JsonNode put(String path, Object body) {
        return send(HttpRequest.newBuilder(uri(path)).PUT(json(body)).header("Content-Type", "application/json"));
    }

    public JsonNode post(String path, String jsonBody) {
        return send(HttpRequest.newBuilder(uri(path))
                .POST(HttpRequest.BodyPublishers.ofString(jsonBody, StandardCharsets.UTF_8))
                .header("Content-Type", "application/json"));
    }

    private URI uri(String path) {
        return URI.create(config.baseUrl() + path);
    }

    private static HttpRequest.BodyPublisher json(Object body) {
        try {
            return HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(body), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new IllegalArgumentException(e);
        }
    }

    private JsonNode send(HttpRequest.Builder request) {
        request.header("Authorization", "Bearer " + config.token())
                .header("Accept", "application/json")
                .header("User-Agent", "bsg/1.0")
                .timeout(Duration.ofSeconds(60));
        HttpResponse<String> response;
        try {
            response = http.send(request.build(), HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        } catch (IOException e) {
            throw new Failure(0, "Server nicht erreichbar (" + config.baseUrl() + "): " + e.getMessage());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new Failure(0, "Abgebrochen.");
        }
        JsonNode body = parse(response.body());
        if (response.statusCode() >= 200 && response.statusCode() < 300) {
            return body;
        }
        String reason = body.path("reason").asText("");
        throw new Failure(response.statusCode(), switch (response.statusCode()) {
            case 401 -> "Das Token ist ungültig, abgelaufen oder widerrufen. Bitte ein neues erstellen."
                    + (reason.isEmpty() ? "" : " (" + reason + ")");
            case 403 -> reason.isEmpty() ? "Keine Berechtigung." : reason;
            default -> reason.isEmpty() ? "Fehler " + response.statusCode() + " vom Server." : reason;
        });
    }

    private static JsonNode parse(String body) {
        if (body == null || body.isBlank()) {
            return JSON.nullNode();
        }
        try {
            return JSON.readTree(body);
        } catch (IOException e) {
            return JSON.createObjectNode().put("reason", body.length() > 200 ? body.substring(0, 200) : body);
        }
    }

    static ObjectMapper json() {
        return JSON;
    }
}
