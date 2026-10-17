package it.a11y.blindensport.webadmin.ui;

import it.a11y.blindensport.webadmin.members.ChangeRequestStore;
import it.a11y.blindensport.webadmin.members.MemberPrivate;
import it.a11y.blindensport.webadmin.members.MemberRecord;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;

class ChangeRequestDiffTest {
    private final MemberRecord member = new MemberRecord("ID", "Anna", "Muster", "Gasse 1", "8010", "Graz", "",
            "", "", "", Instant.now(), "", "f", "", "", "", true,
            new MemberPrivate("1234", "", Instant.parse("1990-05-03T00:00:00Z"), null));

    private ChangeRequestStore.ChangeRequest request(String city) {
        Map<String, String> fields = new LinkedHashMap<>();
        fields.put("first_name", "Anna");
        fields.put("last_name", "Muster");
        fields.put("gender", "f");
        fields.put("street", "Gasse 1");
        fields.put("zip", "8010");
        fields.put("city", city);
        return new ChangeRequestStore.ChangeRequest("r", "ID", "", Instant.now(), "pending", "", null, fields);
    }

    @Test
    void listsOnlyChangedFieldsSpokenAsFromTo() {
        assertEquals(List.of("Ort: von Graz zu Wien"), ChangeRequestsView.diffs(member, request("Wien"), null));
        assertEquals(List.of(), ChangeRequestsView.diffs(member, request("Graz"), null));
    }

    @Test
    void includesTheProtectedProposalWhenLoaded() {
        var proposal = new MemberPrivate("1234", "AT00", null, null);
        assertEquals(List.of("IBAN: von – zu AT00", "Geburtsdatum: von 03.05.1990 zu –"),
                ChangeRequestsView.diffs(member, request("Graz"), proposal));
    }
}
