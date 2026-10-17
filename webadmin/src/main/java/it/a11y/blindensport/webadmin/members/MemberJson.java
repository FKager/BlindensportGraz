package it.a11y.blindensport.webadmin.members;

import java.util.LinkedHashMap;
import java.util.Map;

/** The JSON form of a roster entry, shared by the REST API and the UI's JSON export. */
public final class MemberJson {
    private MemberJson() {
    }

    /** The JSON shape of {@code ClubMemberRecord}: dates ISO 8601, nil dates omitted. */
    public static Map<String, Object> toMap(MemberRecord r) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", r.id());
        m.put("firstName", r.firstName());
        m.put("lastName", r.lastName());
        m.put("street", r.street());
        m.put("zip", r.zip());
        m.put("city", r.city());
        m.put("country", r.country());
        m.put("email", r.email());
        m.put("phone", r.phone());
        m.put("memberNumber", r.memberNumber());
        m.put("joinedAt", Dates.formatApi(r.joinedAt()));
        m.put("notes", r.notes());
        m.put("gender", r.gender());
        m.put("title", r.title());
        if (r.privateData().birthDate() != null) {
            m.put("birthDate", Dates.formatApi(r.privateData().birthDate()));
        }
        m.put("sportId", r.sportId());
        m.put("svnr", r.privateData().svnr());
        m.put("iban", r.privateData().iban());
        if (r.privateData().lastMedicalExamination() != null) {
            m.put("lastMedicalExamination", Dates.formatApi(r.privateData().lastMedicalExamination()));
        }
        m.put("defaultFunction", r.defaultFunction());
        m.put("memberOfGVSC", r.memberOfGVSC());
        return m;
    }
}
