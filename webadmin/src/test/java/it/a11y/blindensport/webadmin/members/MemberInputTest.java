package it.a11y.blindensport.webadmin.members;

import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** PUT semantics of the members API, as the Swift server had them. */
class MemberInputTest {
    private final Instant birth = Instant.parse("1990-05-03T00:00:00Z");
    private final Instant joined = Instant.parse("2020-01-01T00:00:00Z");
    private final MemberRecord existing = new MemberRecord("ID", "Anna", "Muster", "Gasse 1", "8010", "Graz", "AT",
            "a@b.at", "0664", "42", joined, "Notiz", "w", "Mag.", "torball", "Spielerin", false,
            new MemberPrivate("1234", "AT00", birth, birth));

    private static MemberInput input(String first, String last) {
        return new MemberInput(first, last, null, null, null, null, null, null, null, null, null, null, null, null,
                null, null, null, null, null, null);
    }

    @Test
    void omittedFieldsKeepOrReplaceLikeTheSwiftServer() {
        MemberRecord updated = input(" Anna ", "Neu").applyTo(existing, Set.of());
        assertEquals("Anna", updated.firstName());
        assertEquals("Neu", updated.lastName());
        // Replaced when not sent (the old web form always sends them):
        assertEquals("", updated.street());
        assertEquals("", updated.memberNumber());
        assertEquals("", updated.notes());
        // Kept when not sent:
        assertEquals("w", updated.gender());
        assertEquals("Mag.", updated.title());
        assertEquals("torball", updated.sportId());
        assertEquals("Spielerin", updated.defaultFunction());
        assertFalse(updated.memberOfGVSC());
        assertEquals(joined, updated.joinedAt());
        assertEquals(existing.privateData(), updated.privateData());
    }

    @Test
    void explicitNullClearsProtectedDates() {
        MemberRecord updated = input("A", "B").applyTo(existing, Set.of("birthDate"));
        assertNull(updated.privateData().birthDate());
        assertEquals(birth, updated.privateData().lastMedicalExamination());
    }

    @Test
    void emptyStringClearsSvnrAndCountsAsPrivateData() {
        MemberInput in = new MemberInput("A", "B", null, null, null, null, null, null, null, null, null, null, null,
                null, null, "", null, null, null, null);
        assertTrue(in.carriesPrivateData());
        assertEquals("", in.applyTo(existing, Set.of()).privateData().svnr());
        assertEquals("AT00", in.applyTo(existing, Set.of()).privateData().iban());
        assertFalse(input("A", "B").carriesPrivateData());
    }

    @Test
    void namesAreRequired() {
        assertThrows(IllegalArgumentException.class, () -> input(" ", "B").validate());
        assertThrows(IllegalArgumentException.class, () -> input("A", null).validate());
    }

    @Test
    void newRecordDefaults() {
        MemberRecord created = input("A", "B").toNewRecord("NEW");
        assertTrue(created.memberOfGVSC());
        assertEquals("", created.city());
        assertTrue(created.privateData().isEmpty());
    }
}
