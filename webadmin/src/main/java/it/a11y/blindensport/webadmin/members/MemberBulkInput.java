package it.a11y.blindensport.webadmin.members;

import com.fasterxml.jackson.annotation.JsonAlias;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonInclude;

/**
 * Loose, per-row-tolerant import row — the same JSON shape as the app's
 * export, {@code RootCLI/members.example.json} and {@code rootcli import-members}.
 * Every field is optional so one bad row never sinks the whole array; {@code plz}
 * is accepted as an alias for {@code zip} (the club's source rosters use both).
 */
@JsonIgnoreProperties(ignoreUnknown = true)
@JsonInclude(JsonInclude.Include.NON_NULL)
public record MemberBulkInput(
        String id,
        String firstName,
        String lastName,
        String street,
        @JsonAlias("plz") String zip,
        String city,
        String country,
        String email,
        String phone,
        String memberNumber,
        String joinedAt,
        String notes,
        String gender,
        String title,
        String birthDate,
        String sportId,
        String svnr,
        String iban,
        String lastMedicalExamination,
        String defaultFunction,
        Boolean memberOfGVSC) {

    /** The protected fields of the row, parsed like the rest of it. */
    public MemberPrivate privateData() {
        return new MemberPrivate(
                svnr == null ? "" : svnr.trim(),
                iban == null ? "" : iban.trim(),
                Dates.parseFlexible(birthDate).orElse(null),
                Dates.parseFlexible(lastMedicalExamination).orElse(null));
    }
}
