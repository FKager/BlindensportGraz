package it.a11y.blindensport.webui.club;

import com.fasterxml.jackson.databind.JsonNode;
import it.a11y.blindensport.webui.members.Dates;
import it.a11y.blindensport.webui.supabase.Postgrest;
import org.jboss.logging.Logger;

import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import static it.a11y.blindensport.webui.supabase.Postgrest.eq;
import static it.a11y.blindensport.webui.supabase.Postgrest.order;

/**
 * A tournament's documents (invitation, schedule, results …): rows of
 * {@code tournament_invitations} with the file in the private bucket
 * {@code tournament-invitations} under {@code <row id>.<ext>} — the same
 * layout the app syncs. RLS: approved accounts read, events.manage writes.
 */
public final class TournamentDocuments {
    private static final Logger LOG = Logger.getLogger(TournamentDocuments.class);
    public static final String TABLE = "tournament_invitations";
    public static final String BUCKET = "tournament-invitations";
    /** The bucket's limit. */
    public static final int MAX_BYTES = 15 * 1024 * 1024;
    private static final String COLUMNS = "id,tournament_id,storage_path,file_name,content_type,uploaded_by,uploaded_at";

    /** Extension → content type; also the allow-list (same as the bucket and the app). */
    static final Map<String, String> TYPES = new LinkedHashMap<>();

    static {
        TYPES.put("pdf", "application/pdf");
        TYPES.put("docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document");
        TYPES.put("doc", "application/msword");
        TYPES.put("xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
        TYPES.put("xls", "application/vnd.ms-excel");
        TYPES.put("txt", "text/plain");
        TYPES.put("jpg", "image/jpeg");
        TYPES.put("jpeg", "image/jpeg");
        TYPES.put("png", "image/png");
        TYPES.put("heic", "image/heic");
        TYPES.put("heif", "image/heif");
    }

    public record Document(String id, String tournamentId, String storagePath, String fileName,
                           String contentType, String uploadedBy, Instant uploadedAt) {
    }

    private final Postgrest db;
    private final UUID user;

    public TournamentDocuments(Postgrest db, UUID user) {
        this.db = db;
        this.user = user;
    }

    /** Accepted extensions, for file pickers: ".pdf", ".docx", … */
    public static List<String> acceptedExtensions() {
        return TYPES.keySet().stream().map(e -> "." + e).toList();
    }

    public static List<String> acceptedTypes() {
        return TYPES.values().stream().distinct().toList();
    }

    /** Lowercase extension without the dot, or "". */
    public static String extension(String fileName) {
        int dot = fileName.lastIndexOf('.');
        return dot < 0 || dot == fileName.length() - 1 ? "" : fileName.substring(dot + 1).toLowerCase(Locale.ROOT);
    }

    /** The content type of an allowed file name; throws with a German message otherwise. */
    public static String contentType(String fileName) {
        String type = TYPES.get(extension(fileName));
        if (type == null) {
            throw new IllegalArgumentException("Dateityp von „" + fileName
                    + "“ wird nicht unterstützt (PDF, Word, Excel, Text oder Bild).");
        }
        return type;
    }

    /** A tournament's documents, oldest first (the app's order). */
    public List<Document> list(String tournamentId) {
        return rows(db.select(TABLE, COLUMNS, eq("tournament_id", tournamentId.toLowerCase(Locale.ROOT)),
                order("uploaded_at.asc")));
    }

    /** Document counts by tournament id. */
    public Map<String, Integer> counts() {
        Map<String, Integer> counts = new LinkedHashMap<>();
        for (JsonNode r : db.select(TABLE, "tournament_id")) {
            String id = r.path("tournament_id").asText("").toLowerCase(Locale.ROOT);
            if (!id.isEmpty()) {
                counts.merge(id, 1, Integer::sum);
            }
        }
        return counts;
    }

    public Optional<Document> get(String id) {
        List<Document> rows = rows(db.select(TABLE, COLUMNS, eq("id", id.toLowerCase(Locale.ROOT))));
        return rows.isEmpty() ? Optional.empty() : Optional.of(rows.get(0));
    }

    /** A tournament's files by name, oldest first; a repeated name gets "_2", "_3" … */
    public LinkedHashMap<String, byte[]> files(String tournamentId) {
        LinkedHashMap<String, byte[]> files = new LinkedHashMap<>();
        for (Document document : list(tournamentId)) {
            it.a11y.blindensport.webui.xlsx.XlsxPatch.addUnique(files, document.fileName(), content(document));
        }
        return files;
    }

    public byte[] content(Document document) {
        return db.storage().download(BUCKET, document.storagePath());
    }

    /** Uploads the file, then its row (the app pushes in the same order). */
    public Document add(String tournamentId, String fileName, byte[] content) {
        String name = cleanName(fileName);
        String type = contentType(name);
        if (content.length == 0) {
            throw new IllegalArgumentException("„" + name + "“ ist leer.");
        }
        if (content.length > MAX_BYTES) {
            throw new IllegalArgumentException("„" + name + "“ ist größer als 15 MB.");
        }
        String id = UUID.randomUUID().toString();
        String path = id + "." + extension(name);
        Instant now = Instant.now();
        db.storage().upload(BUCKET, path, content, type);
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("id", id);
        row.put("tournament_id", tournamentId.toLowerCase(Locale.ROOT));
        row.put("storage_path", path);
        row.put("file_name", name);
        row.put("content_type", type);
        row.put("uploaded_by", user.toString().toUpperCase(Locale.ROOT));
        row.put("uploaded_at", Dates.formatTimestamp(now));
        row.put("updated_by", user.toString());
        try {
            db.insert(TABLE, row);
        } catch (RuntimeException e) {
            try {
                db.storage().remove(BUCKET, List.of(path));
            } catch (RuntimeException cleanup) {
                // The row failed already; an orphaned file is harmless, but worth knowing about.
                LOG.warnf("Orphaned file %s/%s left after a failed upload: %s", BUCKET, path, cleanup.getMessage());
            }
            throw e;
        }
        return new Document(id, tournamentId.toLowerCase(Locale.ROOT), path, name, type,
                user.toString().toUpperCase(Locale.ROOT), now);
    }

    /** Deletes the row (logged, so the apps drop it too), then the file. */
    public boolean delete(Document document) {
        if (db.delete(TABLE, eq("id", document.id())) == 0) {
            return false;
        }
        db.storage().remove(BUCKET, List.of(document.storagePath()));
        return true;
    }

    /** Removes the files of documents whose rows are already gone (a deleted tournament cascades). */
    public void removeFiles(List<Document> documents) {
        try {
            db.storage().remove(BUCKET, documents.stream().map(Document::storagePath).toList());
        } catch (RuntimeException e) {
            // The tournament is deleted; leftover files are harmless, but worth knowing about.
            LOG.warnf("%d file(s) of a deleted tournament left in %s: %s", documents.size(), BUCKET, e.getMessage());
        }
    }

    /** The bare file name ("/" and "\" become "-"), never empty. */
    static String cleanName(String raw) {
        String name = raw == null ? "" : raw.replace('\\', '/');
        name = name.substring(name.lastIndexOf('/') + 1).strip();
        if (name.isEmpty() || name.startsWith(".")) {
            throw new IllegalArgumentException("Bitte einen Dateinamen mit Endung angeben, z. B. Einladung.pdf.");
        }
        return name;
    }

    private static List<Document> rows(Iterable<JsonNode> rows) {
        List<Document> documents = new ArrayList<>();
        for (JsonNode r : rows) {
            documents.add(new Document(r.path("id").asText("").toLowerCase(Locale.ROOT),
                    r.path("tournament_id").asText("").toLowerCase(Locale.ROOT),
                    r.path("storage_path").asText(""), r.path("file_name").asText(""),
                    r.path("content_type").asText(""), r.path("uploaded_by").asText(""),
                    Dates.parseTimestamp(r.path("uploaded_at").asText("")).orElse(null)));
        }
        return documents;
    }
}
