package it.a11y.blindensport.webadmin.members;

import it.a11y.blindensport.webadmin.supabase.DbErrorMessages;
import it.a11y.blindensport.webadmin.supabase.SupabaseException;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.stream.Stream;

/**
 * Bulk create-or-update of roster entries — same per-row rules as RootCLI's
 * {@code MemberBulkImport} (shared with {@code rootcli import-members}):
 * a provided {@code id} must be a UUID and updates that entry in place; no
 * {@code id} mints a new one, so re-importing an id-less file duplicates.
 * Bad rows are skipped individually, never the batch. Protected fields are
 * written only when the row carries any.
 */
public final class MemberBulkImport {
    public record Result(int succeeded, int failed, List<String> messages) {
        public int total() {
            return succeeded + failed;
        }
    }

    private MemberBulkImport() {
    }

    public static Result run(List<MemberBulkInput> inputs, MemberStore store, UUID updatedBy) {
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
            String id;
            if (input.id() != null) {
                if (MemberStore.key(input.id()).isEmpty()) {
                    failed++;
                    messages.add("Skipped " + fullName + ": id '" + input.id() + "' is not a valid UUID.");
                    continue;
                }
                id = input.id();
            } else {
                id = UUID.randomUUID().toString().toUpperCase();
            }
            MemberPrivate privateData = input.privateData();
            MemberRecord record = record(input, id, firstName, lastName).withPrivateData(privateData);
            try {
                store.save(record, !privateData.isEmpty(), updatedBy);
                succeeded++;
                messages.add("Imported " + fullName + " (" + id + ")");
            } catch (SupabaseException e) {
                failed++;
                messages.add("Failed to import " + fullName + ": " + DbErrorMessages.german(e));
            } catch (RuntimeException e) {
                failed++;
                messages.add("Failed to import " + fullName + ": " + e.getMessage());
            }
        }
        return new Result(succeeded, failed, messages);
    }

    static MemberRecord record(MemberBulkInput input, String id, String firstName, String lastName) {
        return new MemberRecord(
                id, firstName, lastName,
                orEmpty(input.street()), orEmpty(input.zip()), orEmpty(input.city()), orEmpty(input.country()),
                orEmpty(input.email()), orEmpty(input.phone()), orEmpty(input.memberNumber()),
                Dates.parseJoinedAt(input.joinedAt()).orElse(Instant.now()),
                orEmpty(input.notes()), orEmpty(input.gender()), orEmpty(input.title()),
                orEmpty(input.sportId()), orEmpty(input.defaultFunction()),
                input.memberOfGVSC() == null || input.memberOfGVSC(),
                MemberPrivate.EMPTY);
    }

    private static String trim(String s) {
        return s == null ? "" : s.trim();
    }

    private static String orEmpty(String s) {
        return s == null ? "" : s;
    }
}
