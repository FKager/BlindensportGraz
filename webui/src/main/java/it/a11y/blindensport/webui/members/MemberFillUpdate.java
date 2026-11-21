package it.a11y.blindensport.webui.members;

import it.a11y.blindensport.webui.supabase.DbErrorMessages;
import it.a11y.blindensport.webui.supabase.SupabaseException;

import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Stream;

/**
 * The non-destructive import ({@code POST /api/members/import?mode=fill},
 * {@code bsg members import --fill}; formerly {@code rootcli update-members}):
 * an existing entry, matched by first + last name (case and spaces ignored),
 * only gets the fields that are blank there; nothing is overwritten. A row
 * without a match is created like in {@link MemberBulkImport}.
 * {@code memberOfGVSC} has no blank state, so it is only set on creation.
 */
public final class MemberFillUpdate {
    /** An existing entry with the blank fields filled, and which ones. */
    public record Filled(MemberRecord record, List<String> fields) {
    }

    private MemberFillUpdate() {
    }

    public static MemberBulkImport.Result run(List<MemberBulkInput> inputs, MemberStore store, UUID updatedBy) {
        if (inputs.isEmpty()) {
            return new MemberBulkImport.Result(0, 0, List.of());
        }
        List<MemberRecord> existing;
        try {
            existing = store.all(true);
        } catch (RuntimeException e) {
            return new MemberBulkImport.Result(0, inputs.size(),
                    List.of("Could not read the existing members, nothing changed: " + e.getMessage()));
        }
        Map<String, MemberRecord> byName = new HashMap<>();
        for (MemberRecord r : existing) {
            if (!r.firstName().isBlank() && !r.lastName().isBlank()) {
                byName.put(nameKey(r.firstName(), r.lastName()), r);
            }
        }

        int succeeded = 0;
        int failed = 0;
        List<String> messages = new ArrayList<>();
        for (MemberBulkInput input : inputs) {
            String firstName = trim(input.firstName());
            String lastName = trim(input.lastName());
            String fullName = String.join(" ", Stream.of(firstName, lastName).filter(s -> !s.isEmpty()).toList());
            if (firstName.isEmpty() || lastName.isEmpty()) {
                failed++;
                messages.add("Skipped an entry with an empty firstName or lastName.");
                continue;
            }
            String key = nameKey(firstName, lastName);
            MemberRecord match = byName.get(key);
            try {
                if (match == null) {
                    String id = UUID.randomUUID().toString().toUpperCase(Locale.ROOT);
                    MemberPrivate privateData = input.privateData();
                    MemberRecord created = MemberBulkImport.record(input, id, firstName, lastName)
                            .withPrivateData(privateData);
                    store.save(created, !privateData.isEmpty(), updatedBy);
                    // A later row with the same name fills this one instead of creating a second entry.
                    byName.put(key, created);
                    succeeded++;
                    messages.add("Created " + fullName + " (" + id + ") — no existing match.");
                    continue;
                }
                Filled filled = fill(match, input);
                if (filled.fields().isEmpty()) {
                    messages.add("No blank fields to fill for " + fullName + " — already up to date.");
                    continue;
                }
                store.save(filled.record(), !filled.record().privateData().equals(match.privateData()), updatedBy);
                // Later rows for the same member build on what this row filled.
                byName.put(key, filled.record());
                succeeded++;
                messages.add("Filled " + fullName + " (" + match.id() + "): " + String.join(", ", filled.fields()));
            } catch (SupabaseException e) {
                failed++;
                messages.add("Failed for " + fullName + ": " + DbErrorMessages.german(e));
            } catch (RuntimeException e) {
                failed++;
                messages.add("Failed for " + fullName + ": " + e.getMessage());
            }
        }
        return new MemberBulkImport.Result(succeeded, failed, messages);
    }

    /** {@code existing} with each blank field taken from {@code input}, if the input has a value. */
    public static Filled fill(MemberRecord existing, MemberBulkInput input) {
        List<String> filled = new ArrayList<>();
        MemberRecord record = new MemberRecord(existing.id(), existing.firstName(), existing.lastName(),
                text(existing.street(), input.street(), "street", filled),
                text(existing.zip(), input.zip(), "zip", filled),
                text(existing.city(), input.city(), "city", filled),
                text(existing.country(), input.country(), "country", filled),
                text(existing.email(), input.email(), "email", filled),
                text(existing.phone(), input.phone(), "phone", filled),
                text(existing.memberNumber(), input.memberNumber(), "memberNumber", filled),
                existing.joinedAt(),
                text(existing.notes(), input.notes(), "notes", filled),
                text(existing.gender(), input.gender(), "gender", filled),
                text(existing.title(), input.title(), "title", filled),
                text(existing.sportId(), input.sportId(), "sportId", filled),
                text(existing.defaultFunction(), input.defaultFunction(), "defaultFunction", filled),
                existing.memberOfGVSC(), null, existing.status());
        MemberPrivate stored = existing.privateData();
        MemberPrivate incoming = input.privateData();
        MemberPrivate privateData = new MemberPrivate(
                text(stored.svnr(), incoming.svnr(), "svnr", filled),
                text(stored.iban(), incoming.iban(), "iban", filled),
                date(stored.birthDate(), incoming.birthDate(), "birthDate", filled),
                date(stored.lastMedicalExamination(), incoming.lastMedicalExamination(), "lastMedicalExamination", filled));
        return new Filled(record.withPrivateData(privateData), filled);
    }

    private static String text(String current, String incoming, String name, List<String> filled) {
        String value = trim(incoming);
        if (current.isEmpty() && !value.isEmpty()) {
            filled.add(name);
            return value;
        }
        return current;
    }

    private static Instant date(Instant current, Instant incoming, String name, List<String> fields) {
        if (current == null && incoming != null) {
            fields.add(name);
            return incoming;
        }
        return current;
    }

    private static String nameKey(String first, String last) {
        return (first.trim() + "|" + last.trim()).toLowerCase(Locale.ROOT);
    }

    private static String trim(String s) {
        return s == null ? "" : s.trim();
    }
}
