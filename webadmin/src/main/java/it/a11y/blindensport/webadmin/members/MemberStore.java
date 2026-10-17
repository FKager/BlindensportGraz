package it.a11y.blindensport.webadmin.members;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.MissingNode;
import it.a11y.blindensport.webadmin.supabase.Postgrest;

import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import static it.a11y.blindensport.webadmin.supabase.Postgrest.eq;

/**
 * The club roster in Supabase, read and written as the signed-in admin (RLS:
 * members.manage for contacts, members.private.* for member_private).
 * Port of RootCLI's {@code MemberStore}/{@code MemberPrivateStore}.
 *
 * No transaction spans the three tables. A save writes {@code members} first
 * (the row the others reference), so a failure part-way leaves at most a name
 * without contact data, and every write is an idempotent upsert.
 */
public final class MemberStore {
    static final String MEMBER_COLUMNS =
            "id,first_name,last_name,member_number,sport_id,default_function,member_of_gvsc,joined_at";
    static final String CONTACT_COLUMNS = "id,street,zip,city,country,email,phone,notes,gender,title";
    static final String PRIVATE_COLUMNS = "member_id,svnr,iban,birth_date,last_medical_examination";

    private static final Comparator<MemberRecord> BY_NAME =
            Comparator.comparing(MemberRecord::lastName).thenComparing(MemberRecord::firstName);

    private final Postgrest db;

    public MemberStore(Postgrest db) {
        this.db = db;
    }

    /** Every roster entry, sorted by last then first name. Protected fields empty unless {@code includePrivate}. */
    public List<MemberRecord> all(boolean includePrivate) {
        Map<String, JsonNode> contacts = new HashMap<>();
        db.select("member_contacts", CONTACT_COLUMNS)
                .forEach(row -> contacts.putIfAbsent(row.path("id").asText().toLowerCase(Locale.ROOT), row));
        Map<String, MemberPrivate> privateData = includePrivate ? allPrivate() : Map.of();
        return streamRows(db.select("members", MEMBER_COLUMNS))
                .filter(row -> row.hasNonNull("id"))
                .map(row -> {
                    String id = row.get("id").asText().toLowerCase(Locale.ROOT);
                    return MemberRecord.fromRows(row, contacts.getOrDefault(id, MissingNode.getInstance()))
                            .withPrivateData(privateData.getOrDefault(id, MemberPrivate.EMPTY));
                })
                .sorted(BY_NAME)
                .toList();
    }

    public Optional<MemberRecord> get(String id, boolean includePrivate) {
        Optional<String> key = key(id);
        if (key.isEmpty()) {
            return Optional.empty();
        }
        var members = db.select("members", MEMBER_COLUMNS, eq("id", key.get()));
        if (members.isEmpty()) {
            return Optional.empty();
        }
        var contacts = db.select("member_contacts", CONTACT_COLUMNS, eq("id", key.get()));
        MemberRecord record = MemberRecord.fromRows(members.get(0),
                contacts.isEmpty() ? MissingNode.getInstance() : contacts.get(0));
        if (includePrivate) {
            record = record.withPrivateData(getPrivate(key.get()).orElse(MemberPrivate.EMPTY));
        }
        return Optional.of(record);
    }

    public Optional<MemberPrivate> getPrivate(String memberId) {
        return key(memberId).flatMap(key -> {
            var rows = db.select("member_private", PRIVATE_COLUMNS, eq("member_id", key));
            return rows.isEmpty() ? Optional.empty() : Optional.of(MemberPrivate.fromRow(rows.get(0)));
        });
    }

    /**
     * Insert or overwrite the entry. The protected row is written only with
     * {@code writePrivate} (otherwise left as stored); {@code updatedBy} is the admin.
     */
    public void save(MemberRecord record, boolean writePrivate, UUID updatedBy) {
        String key = key(record.id()).orElseThrow(
                () -> new IllegalArgumentException("Member id '" + record.id() + "' is not a UUID."));
        Map<String, Object> member = record.memberRow();
        Map<String, Object> contact = record.contactRow();
        member.put("id", key);
        contact.put("id", key);
        if (updatedBy != null) {
            member.put("updated_by", updatedBy.toString());
            contact.put("updated_by", updatedBy.toString());
        }
        db.upsert("members", List.of(member), "id");
        db.upsert("member_contacts", List.of(contact), "id");
        if (writePrivate) {
            Map<String, Object> row = record.privateData().row(updatedBy);
            row.put("member_id", key);
            db.upsert("member_private", List.of(row), "member_id");
        }
    }

    /**
     * Removes the entry; contacts cascade, the protected row is deleted
     * explicitly (member_private predates the members table).
     */
    public void delete(String id) {
        Optional<String> key = key(id);
        if (key.isEmpty()) {
            return;
        }
        db.delete("members", eq("id", key.get()));
        db.delete("member_private", eq("member_id", key.get()));
    }

    private Map<String, MemberPrivate> allPrivate() {
        Map<String, MemberPrivate> result = new HashMap<>();
        db.select("member_private", PRIVATE_COLUMNS).forEach(row -> result.putIfAbsent(
                row.path("member_id").asText().toLowerCase(Locale.ROOT), MemberPrivate.fromRow(row)));
        return result;
    }

    /** Lowercase UUID string for PostgREST filters, or empty if {@code id} is not a UUID. */
    public static Optional<String> key(String id) {
        // UUID.fromString alone also accepts short forms like "1-2-3-4-5".
        if (id == null || !UUID_PATTERN.matcher(id).matches()) {
            return Optional.empty();
        }
        return Optional.of(UUID.fromString(id).toString());
    }

    private static final java.util.regex.Pattern UUID_PATTERN = java.util.regex.Pattern.compile(
            "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}");

    private static java.util.stream.Stream<JsonNode> streamRows(Iterable<JsonNode> rows) {
        return java.util.stream.StreamSupport.stream(rows.spliterator(), false);
    }
}
