package it.a11y.blindensport.webui.members;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** The fill-only import (formerly rootcli update-members): blank fields are filled, nothing is overwritten. */
class MemberFillUpdateTest {
    private static final Instant JOINED = Instant.parse("2020-01-01T00:00:00Z");

    private static MemberBulkInput input(String json) throws Exception {
        return new ObjectMapper().readValue(json, MemberBulkInput.class);
    }

    private static MemberRecord anna(String city, String email, MemberPrivate privateData) {
        return new MemberRecord("A1", "Anna", "Muster", "", "", city, "", email, "", "7", JOINED, "", "f", "", "",
                "player", false, privateData);
    }

    @Test
    void onlyBlankFieldsAreFilled() throws Exception {
        var existing = anna("Graz", "", MemberPrivate.EMPTY);

        var filled = MemberFillUpdate.fill(existing, input(
                "{\"firstName\":\"Anna\",\"lastName\":\"Muster\",\"city\":\"Wien\",\"email\":\" anna@example.org \","
                        + "\"memberNumber\":\"99\",\"svnr\":\"1234010180\"}"));

        assertEquals("Graz", filled.record().city(), "a set value stays");
        assertEquals("anna@example.org", filled.record().email(), "a blank value is filled, trimmed");
        assertEquals("7", filled.record().memberNumber());
        assertEquals("1234010180", filled.record().privateData().svnr());
        assertEquals(List.of("email", "svnr"), filled.fields());
    }

    @Test
    void blankInputValuesNeverClearAnything() throws Exception {
        var existing = anna("Graz", "anna@example.org", new MemberPrivate("1234010180", "AT61", null, null));

        var filled = MemberFillUpdate.fill(existing, input(
                "{\"firstName\":\"Anna\",\"lastName\":\"Muster\",\"city\":\"\",\"email\":\"  \",\"svnr\":\"\"}"));

        assertTrue(filled.fields().isEmpty());
        assertEquals(existing, filled.record());
    }

    @Test
    void gvscMembershipAndJoinDateAreNeverTouched() throws Exception {
        var existing = anna("Graz", "", MemberPrivate.EMPTY);

        var filled = MemberFillUpdate.fill(existing, input(
                "{\"firstName\":\"Anna\",\"lastName\":\"Muster\",\"memberOfGVSC\":true,\"joinedAt\":\"2025-05-05\"}"));

        assertEquals(false, filled.record().memberOfGVSC());
        assertEquals(JOINED, filled.record().joinedAt());
    }

    @Test
    void protectedDatesAreFilledWhenBlank() throws Exception {
        var existing = anna("Graz", "", MemberPrivate.EMPTY);

        var filled = MemberFillUpdate.fill(existing, input(
                "{\"firstName\":\"Anna\",\"lastName\":\"Muster\",\"birthDate\":\"1980-01-01\"}"));

        assertEquals(List.of("birthDate"), filled.fields());
        assertTrue(filled.record().privateData().birthDate() != null);
    }

    @Test
    void anEmptyFileChangesNothing() {
        var result = MemberFillUpdate.run(List.of(), null, null);
        assertEquals(0, result.total());
    }
}
