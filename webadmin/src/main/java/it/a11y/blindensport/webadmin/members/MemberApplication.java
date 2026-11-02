package it.a11y.blindensport.webadmin.members;

import com.fasterxml.jackson.databind.JsonNode;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * The GVSC Beitrittserklärung fields stored with the contact data
 * ({@code member_contacts}): membership type ("active" / "supporting" / ""),
 * citizenship, mobile number and the legal guardian of a minor. Kept apart
 * from {@link MemberRecord} and written with a partial update, so older
 * code paths that save a record never touch these columns.
 * {@code appliedAt} is read-only: the app's send-membership-application
 * function sets {@code members.gvsc_applied_at}.
 */
public record MemberApplication(
        String membershipType,
        String citizenship,
        String mobile,
        String guardianFirstName,
        String guardianLastName,
        String guardianStreet,
        String guardianZip,
        String guardianCity,
        String guardianPhone,
        String guardianMobile,
        String guardianEmail,
        Instant appliedAt) {

    public static final MemberApplication EMPTY =
            new MemberApplication("", "", "", "", "", "", "", "", "", "", "", null);

    /** Column → German label, in form order (also the change-request columns). */
    public static final Map<String, String> LABELS = labels();

    static final String COLUMNS = "id," + String.join(",", LABELS.keySet());

    private static Map<String, String> labels() {
        Map<String, String> m = new LinkedHashMap<>();
        m.put("membership_type", "Mitgliedsart");
        m.put("citizenship", "Staatsbürgerschaft");
        m.put("mobile", "Mobilnummer");
        m.put("guardian_first_name", "Vertreter:in Vorname");
        m.put("guardian_last_name", "Vertreter:in Nachname");
        m.put("guardian_street", "Vertreter:in Straße");
        m.put("guardian_zip", "Vertreter:in PLZ");
        m.put("guardian_city", "Vertreter:in Wohnort");
        m.put("guardian_phone", "Vertreter:in Telefon");
        m.put("guardian_mobile", "Vertreter:in Mobilnummer");
        m.put("guardian_email", "Vertreter:in E-Mail");
        return m;
    }

    public MemberApplication {
        membershipType = orEmpty(membershipType);
        citizenship = orEmpty(citizenship);
        mobile = orEmpty(mobile);
        guardianFirstName = orEmpty(guardianFirstName);
        guardianLastName = orEmpty(guardianLastName);
        guardianStreet = orEmpty(guardianStreet);
        guardianZip = orEmpty(guardianZip);
        guardianCity = orEmpty(guardianCity);
        guardianPhone = orEmpty(guardianPhone);
        guardianMobile = orEmpty(guardianMobile);
        guardianEmail = orEmpty(guardianEmail);
    }

    /** Column → value, without {@code id} and the read-only applied date. */
    public Map<String, String> columns() {
        Map<String, String> row = new LinkedHashMap<>();
        row.put("membership_type", membershipType);
        row.put("citizenship", citizenship);
        row.put("mobile", mobile);
        row.put("guardian_first_name", guardianFirstName);
        row.put("guardian_last_name", guardianLastName);
        row.put("guardian_street", guardianStreet);
        row.put("guardian_zip", guardianZip);
        row.put("guardian_city", guardianCity);
        row.put("guardian_phone", guardianPhone);
        row.put("guardian_mobile", guardianMobile);
        row.put("guardian_email", guardianEmail);
        return row;
    }

    /** From a {@code member_contacts} row (missing node → empty) and the entry's applied date. */
    public static MemberApplication fromRow(JsonNode row, Instant appliedAt) {
        return new MemberApplication(
                row.path("membership_type").asText(""),
                row.path("citizenship").asText(""),
                row.path("mobile").asText(""),
                row.path("guardian_first_name").asText(""),
                row.path("guardian_last_name").asText(""),
                row.path("guardian_street").asText(""),
                row.path("guardian_zip").asText(""),
                row.path("guardian_city").asText(""),
                row.path("guardian_phone").asText(""),
                row.path("guardian_mobile").asText(""),
                row.path("guardian_email").asText(""),
                appliedAt);
    }

    /** "aktiv" / "fördernd" / "" for display. */
    public static String membershipTypeLabel(String type) {
        return switch (type) {
            case "active" -> "aktiv";
            case "supporting" -> "fördernd";
            default -> "";
        };
    }

    private static String orEmpty(String value) {
        return value == null ? "" : value;
    }
}
