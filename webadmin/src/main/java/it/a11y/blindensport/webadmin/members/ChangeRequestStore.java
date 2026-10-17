package it.a11y.blindensport.webadmin.members;

import com.fasterxml.jackson.databind.JsonNode;
import it.a11y.blindensport.webadmin.supabase.Postgrest;

import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import static it.a11y.blindensport.webadmin.supabase.Postgrest.eq;
import static it.a11y.blindensport.webadmin.supabase.Postgrest.order;

/**
 * Members' proposed changes to their own roster entry
 * ({@code member_change_requests}; protected fields separately in
 * {@code member_private_requests}). Reviewing needs members.manage, the
 * protected part members.private.write — RLS and the RPC check both.
 */
public final class ChangeRequestStore {
    public static final String PENDING = "pending";
    public static final String APPROVED = "approved";
    public static final String REJECTED = "rejected";

    /** One request; the fields are the full proposed values, not a diff. */
    public record ChangeRequest(String id, String memberId, String requestedBy, Instant requestedAt, String status,
                                String reviewedBy, Instant reviewedAt, Map<String, String> fields) {
        public boolean isPending() {
            return PENDING.equals(status);
        }
    }

    /** Proposed value columns, in the order the app shows them, with German labels. */
    public static final Map<String, String> FIELD_LABELS = labels();

    private final Postgrest db;

    public ChangeRequestStore(Postgrest db) {
        this.db = db;
    }

    private static Map<String, String> labels() {
        Map<String, String> m = new LinkedHashMap<>();
        m.put("first_name", "Vorname");
        m.put("last_name", "Nachname");
        m.put("title", "Titel");
        m.put("gender", "Geschlecht");
        m.put("street", "Straße");
        m.put("zip", "PLZ");
        m.put("city", "Ort");
        m.put("country", "Land");
        m.put("email", "E-Mail");
        m.put("phone", "Telefon");
        m.put("sport_id", "Sport-ID");
        return m;
    }

    /** Newest first. */
    public List<ChangeRequest> all() {
        List<ChangeRequest> result = new ArrayList<>();
        for (JsonNode row : db.select("member_change_requests", "*", order("requested_at.desc"))) {
            Map<String, String> fields = new LinkedHashMap<>();
            FIELD_LABELS.keySet().forEach(k -> fields.put(k, row.path(k).asText("")));
            result.add(new ChangeRequest(
                    row.path("id").asText(),
                    row.path("member_id").asText().toUpperCase(Locale.ROOT),
                    row.path("requested_by").asText(""),
                    Dates.parseTimestamp(row.path("requested_at").asText(null)).orElse(null),
                    row.path("status").asText(PENDING),
                    row.path("reviewed_by").asText(""),
                    Dates.parseTimestamp(row.path("reviewed_at").asText(null)).orElse(null),
                    fields));
        }
        return result;
    }

    /** The proposed protected fields, if the member sent any (visible with members.private.write). */
    public Optional<MemberPrivate> privateProposal(String memberId) {
        Optional<String> key = MemberStore.key(memberId);
        if (key.isEmpty()) {
            return Optional.empty();
        }
        var rows = db.select("member_private_requests", "svnr,iban,birth_date,last_medical_examination",
                eq("member_id", key.get()));
        return rows.isEmpty() ? Optional.empty() : Optional.of(MemberPrivate.fromRow(rows.get(0)));
    }

    /**
     * Applies the proposed fields to the entry, then (with {@code applyPrivate})
     * the protected proposal via {@code apply_member_private_request}, and
     * marks the request approved. Unlike the app, a missing protected
     * proposal never clears stored SVNR/IBAN/dates.
     */
    public void approve(ChangeRequest request, boolean applyPrivate, UUID reviewer) {
        String key = MemberStore.key(request.memberId())
                .orElseThrow(() -> new IllegalArgumentException("Ungültige Mitglieds-ID."));
        Map<String, String> f = request.fields();
        Map<String, Object> member = new LinkedHashMap<>();
        member.put("first_name", f.get("first_name"));
        member.put("last_name", f.get("last_name"));
        member.put("sport_id", f.get("sport_id"));
        member.put("updated_by", reviewer.toString());
        Map<String, Object> contact = new LinkedHashMap<>();
        for (String k : List.of("title", "gender", "street", "zip", "city", "country", "email", "phone")) {
            contact.put(k, f.get(k));
        }
        contact.put("updated_by", reviewer.toString());
        if (db.update("members", member, eq("id", key)) == 0) {
            throw new IllegalArgumentException("Das zugehörige Mitglied gibt es nicht mehr.");
        }
        contact.put("id", key);
        db.upsert("member_contacts", List.of(contact), "id");
        if (applyPrivate) {
            db.rpc("apply_member_private_request", Map.of("p_member_id", key));
        }
        markReviewed(request, APPROVED, reviewer);
    }

    /** Marks the request rejected and drops a protected proposal (with members.private.write). */
    public void reject(ChangeRequest request, boolean dropPrivate, UUID reviewer) {
        markReviewed(request, REJECTED, reviewer);
        if (dropPrivate) {
            MemberStore.key(request.memberId()).ifPresent(key -> db.delete("member_private_requests", eq("member_id", key)));
        }
    }

    private void markReviewed(ChangeRequest request, String status, UUID reviewer) {
        Map<String, Object> values = new LinkedHashMap<>();
        values.put("status", status);
        // The app stores reviewer ids as UUID.uuidString (uppercase).
        values.put("reviewed_by", reviewer.toString().toUpperCase(Locale.ROOT));
        values.put("reviewed_at", Dates.formatTimestamp(Instant.now()));
        values.put("updated_by", reviewer.toString());
        if (db.update("member_change_requests", values, eq("id", request.id())) == 0) {
            throw new IllegalArgumentException("Der Antrag wurde inzwischen entfernt.");
        }
    }
}
