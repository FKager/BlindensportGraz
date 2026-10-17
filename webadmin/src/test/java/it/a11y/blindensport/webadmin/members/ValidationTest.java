package it.a11y.blindensport.webadmin.members;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ValidationTest {
    @Test
    void ibanChecksum() {
        assertTrue(Validation.ibanChecksumIsValid(""));
        assertTrue(Validation.ibanChecksumIsValid("AT61 1904 3002 3457 3201"));
        assertTrue(Validation.ibanChecksumIsValid("de89370400440532013000"));
        assertFalse(Validation.ibanChecksumIsValid("AT61 1904 3002 3457 3202"));
        assertFalse(Validation.ibanChecksumIsValid("AT6"));
        assertFalse(Validation.ibanChecksumIsValid("AT61-1904"));
    }

    @Test
    void svnrNeedsTenDigits() {
        assertTrue(Validation.isPlausibleAustrianSvnr(""));
        assertTrue(Validation.isPlausibleAustrianSvnr("1234 010190"));
        assertFalse(Validation.isPlausibleAustrianSvnr("12345"));
    }
}
