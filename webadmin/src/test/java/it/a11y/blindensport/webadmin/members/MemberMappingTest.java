package it.a11y.blindensport.webadmin.members;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.MissingNode;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** Ports of RootCLI's MemberStoreTests / MemberPrivateTests (row mapping, no network). */
class MemberMappingTest {
    private static final ObjectMapper JSON = new ObjectMapper();
    private final Instant birth = Dates.parseFlexible("1990-05-03").orElseThrow();

    private static JsonNode node(String json) throws Exception {
        return JSON.readTree(json);
    }

    @Test
    void recordSplitsIntoMemberAndContactRowsWithoutProtectedFields() {
        var record = new MemberRecord(UUID.randomUUID().toString(), "Anna", "Muster", "Gasse 1", "", "", "",
                "anna@example.org", "", "42", Instant.ofEpochSecond(1_700_000_000), "", "", "", "torball",
                "Spielerin", false, new MemberPrivate("1234", "AT00", birth, null));
        var member = record.memberRow();
        var contact = record.contactRow();
        assertEquals("Anna", member.get("first_name"));
        assertEquals("42", member.get("member_number"));
        assertEquals(false, member.get("member_of_gvsc"));
        assertEquals("Gasse 1", contact.get("street"));
        assertEquals("anna@example.org", contact.get("email"));
        Set<String> columns = new HashSet<>(member.keySet());
        columns.addAll(contact.keySet());
        assertTrue(columns.stream().noneMatch(Set.of("svnr", "iban", "birth_date", "last_medical_examination")::contains),
                "protected fields go only to member_private");
    }

    @Test
    void rowsMapBackWithUppercaseIdAndFractionalTimestamp() throws Exception {
        UUID id = UUID.randomUUID();
        var record = MemberRecord.fromRows(
                node("{\"id\":\"" + id + "\",\"first_name\":\"Bert\",\"last_name\":\"Beispiel\",\"member_number\":\"7\","
                        + "\"sport_id\":\"goalball\",\"default_function\":\"\",\"member_of_gvsc\":true,"
                        + "\"joined_at\":\"2026-10-13T20:55:51.439+00:00\"}"),
                node("{\"id\":\"" + id + "\",\"city\":\"Graz\",\"phone\":\"0664\"}"));
        assertEquals(id.toString().toUpperCase(), record.id());
        assertEquals("Graz", record.city());
        assertEquals("goalball", record.sportId());
        assertEquals(1_791_924_951_439L, record.joinedAt().toEpochMilli());
        assertTrue(record.privateData().isEmpty());
    }

    @Test
    void missingContactRowGivesEmptyContactFields() throws Exception {
        var record = MemberRecord.fromRows(node("{\"id\":\"" + UUID.randomUUID()
                + "\",\"first_name\":\"C\",\"last_name\":\"D\",\"joined_at\":\"2026-01-01T00:00:00+00:00\"}"),
                MissingNode.getInstance());
        assertEquals("", record.street());
        assertEquals("", record.email());
        assertTrue(record.memberOfGVSC());
    }

    @Test
    void timestampRoundTrips() {
        Instant date = Instant.ofEpochMilli(1_800_000_000_250L);
        assertEquals(date, Dates.parseTimestamp(Dates.formatTimestamp(date)).orElseThrow());
        assertTrue(Dates.parseTimestamp("2026-10-13T20:55:51+00:00").isPresent());
    }

    @Test
    void privateRowRoundTripKeepsTheDay() throws Exception {
        var data = new MemberPrivate("1", "AT", birth, null);
        var row = data.row(null);
        assertEquals("1990-05-03", row.get("birth_date"));
        assertTrue(row.containsKey("last_medical_examination"));
        assertNull(row.get("last_medical_examination"));
        assertFalse(row.containsKey("updated_by"));
        assertEquals(data, MemberPrivate.fromRow(JSON.valueToTree(row)));
    }

    @Test
    void updatedByIsLowercaseUuid() {
        UUID admin = UUID.randomUUID();
        assertEquals(admin.toString(), MemberPrivate.EMPTY.row(admin).get("updated_by"));
    }

    @Test
    void importRowPrivateDataParsesGermanDates() {
        var row = new MemberBulkInput(null, "A", "B", null, null, null, null, null, null, null, null, null, null, null,
                "03.05.1990", null, " 1234 ", null, null, null, null);
        assertEquals("1234", row.privateData().svnr());
        assertEquals(birth, row.privateData().birthDate());
        assertTrue(new MemberBulkInput(null, "A", "B", null, null, null, null, null, null, null, null, null, null,
                null, null, null, null, null, null, null, null).privateData().isEmpty());
    }

    @Test
    void importAcceptsPlzAsZipAlias() throws Exception {
        var row = JSON.readValue("{\"firstName\":\"A\",\"lastName\":\"B\",\"plz\":\"8010\",\"extra\":1}",
                MemberBulkInput.class);
        assertEquals("8010", row.zip());
    }

    @Test
    void keyAcceptsOnlyFullUuids() {
        assertTrue(MemberStore.key("6F9619FF-8B86-D011-B42D-00C04FC964FF").isPresent());
        assertEquals("6f9619ff-8b86-d011-b42d-00c04fc964ff",
                MemberStore.key("6F9619FF-8B86-D011-B42D-00C04FC964FF").orElseThrow());
        assertTrue(MemberStore.key("1-2-3-4-5").isEmpty());
        assertTrue(MemberStore.key("abc").isEmpty());
    }
}
