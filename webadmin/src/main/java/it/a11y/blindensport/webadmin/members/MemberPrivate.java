package it.a11y.blindensport.webadmin.members;

import com.fasterxml.jackson.databind.JsonNode;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

/**
 * The protected part of a roster entry — SVNR, IBAN, birth date, last
 * medical examination — stored only in {@code public.member_private}.
 * Dates are instants at midnight UTC of the stored day.
 */
public record MemberPrivate(String svnr, String iban, Instant birthDate, Instant lastMedicalExamination) {
    public static final MemberPrivate EMPTY = new MemberPrivate("", "", null, null);

    public MemberPrivate {
        svnr = svnr == null ? "" : svnr;
        iban = iban == null ? "" : iban;
    }

    public boolean isEmpty() {
        return svnr.isEmpty() && iban.isEmpty() && birthDate == null && lastMedicalExamination == null;
    }

    /** Supabase row without {@code member_id}. Days as the club sees them (Europe/Vienna). */
    public Map<String, Object> row(UUID updatedBy) {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("svnr", svnr);
        row.put("iban", iban);
        row.put("birth_date", birthDate == null ? null : Dates.day(birthDate));
        row.put("last_medical_examination", lastMedicalExamination == null ? null : Dates.day(lastMedicalExamination));
        if (updatedBy != null) {
            row.put("updated_by", updatedBy.toString());
        }
        return row;
    }

    public static MemberPrivate fromRow(JsonNode row) {
        return new MemberPrivate(
                row.path("svnr").asText(""),
                row.path("iban").asText(""),
                row.hasNonNull("birth_date") ? Dates.fromDay(row.get("birth_date").asText()).orElse(null) : null,
                row.hasNonNull("last_medical_examination")
                        ? Dates.fromDay(row.get("last_medical_examination").asText()).orElse(null) : null);
    }
}
