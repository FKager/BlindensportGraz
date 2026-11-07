package it.a11y.blindensport.webui.club;

import com.fasterxml.jackson.databind.JsonNode;
import it.a11y.blindensport.webui.members.Dates;
import it.a11y.blindensport.webui.supabase.Postgrest;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

import static it.a11y.blindensport.webui.supabase.Postgrest.limit;
import static it.a11y.blindensport.webui.supabase.Postgrest.order;

/**
 * Vereinsfunktionen: one holder per function, one member may hold several.
 * They record a position and give no rights. Changes go through the
 * set_club_function RPC (club.manage), and a trigger writes the log.
 */
public final class ClubFunctions {
    /** In the order they're shown. */
    public static final Map<String, String> LABELS;

    static {
        Map<String, String> labels = new LinkedHashMap<>();
        labels.put("obmann", "Obmann");
        labels.put("obmann_stellvertreter", "Obmann Stellvertreter");
        labels.put("kassier", "Kassier");
        labels.put("schriftfuehrer", "Schriftführer");
        LABELS = Collections.unmodifiableMap(labels);
    }

    public record LogEntry(String function, String oldName, String newName, UUID changedBy, Instant changedAt) {
    }

    private final Postgrest db;

    public ClubFunctions(Postgrest db) {
        this.db = db;
    }

    /** Function key to the holder's lowercase member id; a vacant function is absent. */
    public Map<String, String> holders() {
        Map<String, String> holders = new HashMap<>();
        db.select("club_functions", "function_key,member_id").forEach(r ->
                holders.put(r.path("function_key").asText(), r.path("member_id").asText().toLowerCase(Locale.ROOT)));
        return holders;
    }

    /** @param memberId lowercase id, or null to leave the function vacant */
    public void set(String function, String memberId) {
        Map<String, Object> params = new HashMap<>();
        params.put("p_function", function);
        params.put("p_member", memberId);
        db.rpc("set_club_function", params);
    }

    public List<LogEntry> log(int rows) {
        List<LogEntry> entries = new ArrayList<>();
        db.select("club_function_log", "function_key,old_name,new_name,changed_by,changed_at",
                order("changed_at.desc"), limit(rows)).forEach(r -> entries.add(new LogEntry(
                r.path("function_key").asText(), text(r, "old_name"), text(r, "new_name"),
                r.hasNonNull("changed_by") ? UUID.fromString(r.get("changed_by").asText()) : null,
                Dates.parseTimestamp(r.path("changed_at").asText(null)).orElse(null))));
        return entries;
    }

    private static String text(JsonNode r, String key) {
        return r.hasNonNull(key) ? r.get(key).asText() : "";
    }
}
