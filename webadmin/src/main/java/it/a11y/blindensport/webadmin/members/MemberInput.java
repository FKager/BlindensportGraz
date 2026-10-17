package it.a11y.blindensport.webadmin.members;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

import java.time.Instant;
import java.util.Set;

/**
 * Body of POST/PUT /api/members (and what the Vaadin form produces): the
 * {@link MemberRecord} fields minus {@code id}; null = not sent.
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public record MemberInput(
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
        Instant birthDate,
        String sportId,
        String svnr,
        String iban,
        Instant lastMedicalExamination,
        String defaultFunction,
        Boolean memberOfGVSC) {

    public static final Set<String> CLEARABLE_DATES = Set.of("birthDate", "lastMedicalExamination");

    /** True if the body sets any protected field (an empty string counts — it clears the value). */
    public boolean carriesPrivateData() {
        return svnr != null || iban != null || birthDate != null || lastMedicalExamination != null;
    }

    /** "firstName and lastName are required." unless both are non-blank. */
    public void validate() {
        if (firstName == null || firstName.isBlank() || lastName == null || lastName.isBlank()) {
            throw new IllegalArgumentException("firstName and lastName are required.");
        }
    }

    /** A new entry (POST). */
    public MemberRecord toNewRecord(String id) {
        return new MemberRecord(
                id, firstName.trim(), lastName.trim(),
                or(street, ""), or(zip, ""), or(city, ""), or(country, ""), or(email, ""), or(phone, ""),
                or(memberNumber, ""), joinedAt != null ? joinedAt : Instant.now(), or(notes, ""),
                or(gender, ""), or(title, ""), or(sportId, ""), or(defaultFunction, ""),
                memberOfGVSC == null || memberOfGVSC,
                new MemberPrivate(or(svnr, ""), or(iban, ""), birthDate, lastMedicalExamination));
    }

    /**
     * The stored entry updated with this input (PUT) — exactly the Swift
     * server's rules: address/contact/number/notes are replaced ("" when not
     * sent); gender, title, sportId, defaultFunction, memberOfGVSC, joinedAt
     * and the protected fields keep their stored value when not sent; an
     * explicit JSON null ({@code clearedDates}) clears birthDate /
     * lastMedicalExamination.
     */
    public MemberRecord applyTo(MemberRecord existing, Set<String> clearedDates) {
        MemberPrivate stored = existing.privateData();
        return new MemberRecord(
                existing.id(), firstName.trim(), lastName.trim(),
                or(street, ""), or(zip, ""), or(city, ""), or(country, ""), or(email, ""), or(phone, ""),
                or(memberNumber, ""), joinedAt != null ? joinedAt : existing.joinedAt(), or(notes, ""),
                or(gender, existing.gender()), or(title, existing.title()), or(sportId, existing.sportId()),
                or(defaultFunction, existing.defaultFunction()),
                memberOfGVSC != null ? memberOfGVSC : existing.memberOfGVSC(),
                new MemberPrivate(
                        or(svnr, stored.svnr()),
                        or(iban, stored.iban()),
                        clearedDates.contains("birthDate") ? null
                                : birthDate != null ? birthDate : stored.birthDate(),
                        clearedDates.contains("lastMedicalExamination") ? null
                                : lastMedicalExamination != null ? lastMedicalExamination
                                : stored.lastMedicalExamination()));
    }

    private static String or(String value, String fallback) {
        return value != null ? value : fallback;
    }
}
