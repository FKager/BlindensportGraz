package it.a11y.blindensport.bsg;

import java.io.IOException;
import java.net.URI;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.PosixFilePermission;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/**
 * Where bsg talks to and as whom. The token comes from {@code BSG_TOKEN} or
 * the file {@code ~/.config/blindensport/token}, never from the command
 * line, where it would end up in the shell history and the process list.
 */
public record Config(URI baseUrl, String token) {
    public static final String DEFAULT_URL = "https://bs.a11y.it";
    static final String TOKEN_PREFIX = "bsg_mcp_";

    /** Thrown for a setup problem: exit code 2 with a German message. */
    public static final class Problem extends RuntimeException {
        public Problem(String message) {
            super(message);
        }
    }

    public static Config resolve(String urlOption, Map<String, String> env, Path home) {
        String url = urlOption != null ? urlOption : env.getOrDefault("BSG_URL", DEFAULT_URL);
        URI base;
        try {
            base = URI.create(url.endsWith("/") ? url.substring(0, url.length() - 1) : url);
        } catch (IllegalArgumentException e) {
            throw new Problem("Ungültige Adresse: " + url);
        }
        if (!"https".equals(base.getScheme()) && !isLocal(base)) {
            throw new Problem("Die Adresse muss mit https:// beginnen (http nur für localhost): " + url);
        }
        String token = Optional.ofNullable(env.get("BSG_TOKEN")).map(String::trim).filter(t -> !t.isEmpty())
                .orElseGet(() -> readTokenFile(home.resolve(".config/blindensport/token")));
        if (!token.startsWith(TOKEN_PREFIX)) {
            throw new Problem("Das ist kein persönliches Token (es beginnt mit " + TOKEN_PREFIX + "). "
                    + "Erstellen Sie eines in der Web-Oberfläche unter \"Persönliche Tokens\".");
        }
        return new Config(base, token);
    }

    private static boolean isLocal(URI uri) {
        return "http".equals(uri.getScheme())
                && ("localhost".equals(uri.getHost()) || "127.0.0.1".equals(uri.getHost()));
    }

    private static String readTokenFile(Path file) {
        if (!Files.isRegularFile(file)) {
            throw new Problem("Kein Token gefunden. Setzen Sie BSG_TOKEN oder legen Sie es in " + file
                    + " ab (nur für Sie lesbar: chmod 600). Ein Token erstellen Sie in der Web-Oberfläche "
                    + "unter \"Persönliche Tokens\".");
        }
        try {
            Set<PosixFilePermission> permissions = Files.getPosixFilePermissions(file);
            if (permissions.contains(PosixFilePermission.GROUP_READ)
                    || permissions.contains(PosixFilePermission.OTHERS_READ)) {
                throw new Problem("Die Token-Datei " + file + " ist für andere lesbar. Bitte: chmod 600 " + file);
            }
        } catch (UnsupportedOperationException ignored) {
            // not a POSIX file system (Windows): nothing to check
        } catch (IOException e) {
            throw new Problem("Die Token-Datei " + file + " kann nicht gelesen werden: " + e.getMessage());
        }
        try {
            return Files.readString(file).trim();
        } catch (IOException e) {
            throw new Problem("Die Token-Datei " + file + " kann nicht gelesen werden: " + e.getMessage());
        }
    }
}
