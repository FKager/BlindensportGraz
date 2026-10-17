package it.a11y.blindensport.webadmin.members;

import java.util.Locale;

/**
 * Soft checks as in the app's {@code Validation.swift}: they warn, never
 * block saving (imported real-world data is often messy).
 */
public final class Validation {
    private Validation() {
    }

    /** Empty, or a mod-97 IBAN checksum that adds up. */
    public static boolean ibanChecksumIsValid(String raw) {
        String iban = raw == null ? "" : raw.toUpperCase(Locale.ROOT).replace(" ", "");
        if (iban.isEmpty()) {
            return true;
        }
        if (iban.length() < 5 || !iban.chars().allMatch(c -> (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))) {
            return false;
        }
        String rearranged = iban.substring(4) + iban.substring(0, 4);
        int remainder = 0;
        for (char c : rearranged.toCharArray()) {
            int value = Character.isDigit(c) ? c - '0' : c - 'A' + 10;
            for (char digit : String.valueOf(value).toCharArray()) {
                remainder = (remainder * 10 + (digit - '0')) % 97;
            }
        }
        return remainder == 1;
    }

    /** Empty, or exactly 10 digits (spaces and separators ignored). */
    public static boolean isPlausibleAustrianSvnr(String raw) {
        long digits = raw == null ? 0 : raw.chars().filter(c -> c >= '0' && c <= '9').count();
        return digits == 0 || digits == 10;
    }
}
