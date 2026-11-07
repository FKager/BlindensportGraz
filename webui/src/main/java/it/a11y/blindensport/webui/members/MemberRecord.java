package it.a11y.blindensport.webui.members;

import com.fasterxml.jackson.databind.JsonNode;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;

/**
 * One roster entry as the API and the UI see it — the same shape as
 * {@code ClubSchema.ClubMemberRecord} (Shared/ClubSchema). Stored across
 * {@code members} (names, readable by approved accounts), {@code member_contacts}
 * (address/contact) and {@code member_private} (protected fields).
 * {@code id} is the uppercase UUID string the app uses.
 */
public record MemberRecord(
        String id,
        String firstName,
        String lastName,
        String street,
        String zip,
        String city,
        String country,
        String email,
        String phone,
        String memberNumber,
        Instant joinedAt,
        String notes,
        String gender,
        String title,
        String sportId,
        String defaultFunction,
        boolean memberOfGVSC,
        MemberPrivate privateData,
        // null = leave the stored status alone (a new row gets the database default, 'new').
        String status) {

    public MemberRecord {
        privateData = privateData == null ? MemberPrivate.EMPTY : privateData;
        joinedAt = joinedAt == null ? Instant.now() : joinedAt;
    }

    public MemberRecord(String id, String firstName, String lastName, String street, String zip, String city,
                        String country, String email, String phone, String memberNumber, Instant joinedAt,
                        String notes, String gender, String title, String sportId, String defaultFunction,
                        boolean memberOfGVSC, MemberPrivate privateData) {
        this(id, firstName, lastName, street, zip, city, country, email, phone, memberNumber, joinedAt, notes, gender,
                title, sportId, defaultFunction, memberOfGVSC, privateData, null);
    }

    public MemberRecord withPrivateData(MemberPrivate data) {
        return new MemberRecord(id, firstName, lastName, street, zip, city, country, email, phone, memberNumber,
                joinedAt, notes, gender, title, sportId, defaultFunction, memberOfGVSC, data, status);
    }

    public String fullName() {
        return (firstName + " " + lastName).trim();
    }

    /** From a {@code members} row and its {@code member_contacts} row (missing node if none). */
    public static MemberRecord fromRows(JsonNode member, JsonNode contact) {
        return new MemberRecord(
                member.path("id").asText("").toUpperCase(Locale.ROOT),
                member.path("first_name").asText(""),
                member.path("last_name").asText(""),
                contact.path("street").asText(""),
                contact.path("zip").asText(""),
                contact.path("city").asText(""),
                contact.path("country").asText(""),
                contact.path("email").asText(""),
                contact.path("phone").asText(""),
                member.path("member_number").asText(""),
                Dates.parseTimestamp(member.path("joined_at").asText(null)).orElse(Instant.now()),
                contact.path("notes").asText(""),
                contact.path("gender").asText(""),
                contact.path("title").asText(""),
                member.path("sport_id").asText(""),
                member.path("default_function").asText(""),
                member.path("member_of_gvsc").asBoolean(true),
                MemberPrivate.EMPTY,
                member.path("status").asText(null));
    }

    public Map<String, Object> memberRow() {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("first_name", firstName);
        row.put("last_name", lastName);
        row.put("member_number", memberNumber);
        row.put("sport_id", sportId);
        row.put("default_function", defaultFunction);
        row.put("member_of_gvsc", memberOfGVSC);
        row.put("joined_at", Dates.formatTimestamp(joinedAt));
        if (status != null) {
            row.put("status", status);
        }
        return row;
    }

    public Map<String, Object> contactRow() {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("street", street);
        row.put("zip", zip);
        row.put("city", city);
        row.put("country", country);
        row.put("email", email);
        row.put("phone", phone);
        row.put("notes", notes);
        row.put("gender", gender);
        row.put("title", title);
        return row;
    }
}
