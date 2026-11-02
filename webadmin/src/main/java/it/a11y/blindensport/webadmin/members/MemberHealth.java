package it.a11y.blindensport.webadmin.members;

import com.fasterxml.jackson.databind.JsonNode;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

/**
 * Protected GVSC Beitrittserklärung data in {@code member_private}:
 * disability details and the two consents (null = not answered). Same
 * permissions as SVNR/IBAN; written with a merge upsert of only these
 * columns, so {@link MemberPrivate} saves and these never overwrite each other.
 */
public record MemberHealth(
        String disabilityType,
        String disabilityClass,
        String disabilityCause,
        Boolean consentDataTransfer,
        Boolean consentPhotos) {

    public static final MemberHealth EMPTY = new MemberHealth("", "", "", null, null);

    static final String COLUMNS =
            "member_id,disability_type,disability_class,disability_cause,consent_data_transfer,consent_photos";

    public MemberHealth {
        disabilityType = disabilityType == null ? "" : disabilityType;
        disabilityClass = disabilityClass == null ? "" : disabilityClass;
        disabilityCause = disabilityCause == null ? "" : disabilityCause;
    }

    /** Supabase row without {@code member_id}; consents as explicit nulls. */
    public Map<String, Object> row(UUID updatedBy) {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("disability_type", disabilityType);
        row.put("disability_class", disabilityClass);
        row.put("disability_cause", disabilityCause);
        row.put("consent_data_transfer", consentDataTransfer);
        row.put("consent_photos", consentPhotos);
        if (updatedBy != null) {
            row.put("updated_by", updatedBy.toString());
        }
        return row;
    }

    public static MemberHealth fromRow(JsonNode row) {
        return new MemberHealth(
                row.path("disability_type").asText(""),
                row.path("disability_class").asText(""),
                row.path("disability_cause").asText(""),
                row.hasNonNull("consent_data_transfer") ? row.get("consent_data_transfer").asBoolean() : null,
                row.hasNonNull("consent_photos") ? row.get("consent_photos").asBoolean() : null);
    }

    /** "Ja" / "Nein" / "" for display. */
    public static String consentLabel(Boolean consent) {
        return consent == null ? "" : consent ? "Ja" : "Nein";
    }
}
