package it.a11y.blindensport.webadmin.mcp;

import jakarta.enterprise.context.ApplicationScoped;

import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.HexFormat;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * PRAE forms waiting to be fetched. They hold SVNR and IBAN, so they stay out
 * of the MCP response, which would put them in front of the AI: the tool
 * returns a link instead. A file lives in memory only, can be fetched once and
 * expires after {@link #LIFETIME}.
 */
@ApplicationScoped
public class McpFiles {
    public static final Duration LIFETIME = Duration.ofMinutes(10);
    private static final SecureRandom RANDOM = new SecureRandom();

    public record File(String name, String contentType, byte[] content, Instant expires) {
    }

    private final Map<String, File> files = new ConcurrentHashMap<>();

    /** @return the token of the link */
    public String put(String name, String contentType, byte[] content) {
        Instant now = Instant.now();
        files.values().removeIf(f -> !f.expires().isAfter(now));
        byte[] bytes = new byte[32];
        RANDOM.nextBytes(bytes);
        String token = HexFormat.of().formatHex(bytes);
        files.put(token, new File(name, contentType, content, now.plus(LIFETIME)));
        return token;
    }

    /** The file, removed from the store; empty if unknown, already fetched or expired. */
    public Optional<File> take(String token) {
        File file = token == null ? null : files.remove(token);
        return file == null || !file.expires().isAfter(Instant.now()) ? Optional.empty() : Optional.of(file);
    }
}
