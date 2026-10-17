package it.a11y.blindensport.webadmin.accounts;

import com.fasterxml.jackson.databind.JsonNode;
import it.a11y.blindensport.webadmin.members.Dates;
import it.a11y.blindensport.webadmin.members.MemberRecord;
import it.a11y.blindensport.webadmin.members.MemberStore;
import it.a11y.blindensport.webadmin.supabase.Postgrest;

import java.time.Instant;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static it.a11y.blindensport.webadmin.supabase.Postgrest.order;

/**
 * App accounts ("App-Konten"), as the signed-in admin sees them. Every
 * change is a Supabase RPC that re-checks the permission and the guards
 * (no self-change, root targets refused, last root protected, audit logs):
 * users.approve for approvals and activation codes, roles.assign for roles,
 * blocking and deleting.
 */
public final class AccountService {
    public static final List<String> ROLES = List.of("member", "coach", "admin", "root");

    public record Approval(String memberId, Instant approvedAt) {
    }

    public record Account(UUID id, String email, String firstName, String lastName, Instant createdAt,
                          String role, Approval approval, boolean blocked) {
        public String displayName() {
            String name = (firstName + " " + lastName).trim();
            return name.isEmpty() ? email : name;
        }

        public boolean hasFullAccess() {
            return "admin".equals(role) || "root".equals(role);
        }
    }

    /** A likely roster entry for an unapproved account: e-mail match first, else first + last name. */
    public record Suggestion(MemberRecord member, boolean byEmail) {
    }

    public record RoleChange(UUID userId, String oldRole, String newRole, UUID changedBy, Instant changedAt) {
    }

    public record AdminAction(String action, UUID target, String targetEmail, String targetName, UUID actor, Instant at) {
    }

    private final Postgrest db;

    public AccountService(Postgrest db) {
        this.db = db;
    }

    /** All accounts with an e-mail, sorted by name. {@code withBlocked} needs roles.assign. */
    public List<Account> all(boolean withBlocked) {
        Map<String, String> roles = new HashMap<>();
        db.select("user_roles", "user_id,role").forEach(r -> roles.put(r.path("user_id").asText(), r.path("role").asText()));
        Map<String, Approval> approvals = new HashMap<>();
        db.select("account_approvals", "user_id,member_id,approved_at").forEach(r -> approvals.put(
                r.path("user_id").asText(),
                new Approval(r.path("member_id").asText().toUpperCase(Locale.ROOT),
                        Dates.parseTimestamp(r.path("approved_at").asText(null)).orElse(null))));
        Set<String> blocked = new HashSet<>();
        if (withBlocked) {
            db.rpc("blocked_accounts", Map.of()).forEach(r -> blocked.add(r.path("user_id").asText()));
        }
        return java.util.stream.StreamSupport.stream(
                        db.select("profiles", "id,email,first_name,last_name,created_at").spliterator(), false)
                .filter(p -> !p.path("email").asText("").isBlank())
                .map(p -> {
                    String id = p.path("id").asText();
                    return new Account(UUID.fromString(id), p.path("email").asText(), p.path("first_name").asText(""),
                            p.path("last_name").asText(""),
                            Dates.parseTimestamp(p.path("created_at").asText(null)).orElse(null),
                            roles.get(id), approvals.get(id), blocked.contains(id));
                })
                .sorted(Comparator.comparing((Account a) -> a.lastName().toLowerCase(Locale.ROOT))
                        .thenComparing(a -> a.firstName().toLowerCase(Locale.ROOT))
                        .thenComparing(Account::email))
                .toList();
    }

    public static Optional<Suggestion> suggest(Account account, List<MemberRecord> roster) {
        String email = account.email().trim().toLowerCase(Locale.ROOT);
        if (!email.isEmpty()) {
            for (MemberRecord m : roster) {
                if (m.email().trim().toLowerCase(Locale.ROOT).equals(email)) {
                    return Optional.of(new Suggestion(m, true));
                }
            }
        }
        String first = account.firstName().trim().toLowerCase(Locale.ROOT);
        String last = account.lastName().trim().toLowerCase(Locale.ROOT);
        if (first.isEmpty() || last.isEmpty()) {
            return Optional.empty();
        }
        return roster.stream()
                .filter(m -> m.firstName().trim().toLowerCase(Locale.ROOT).equals(first)
                        && m.lastName().trim().toLowerCase(Locale.ROOT).equals(last))
                .findFirst()
                .map(m -> new Suggestion(m, false));
    }

    /** Approves the account and links it to a roster entry (gives the member role if it had none). */
    public void approve(UUID account, String memberId) {
        String key = MemberStore.key(memberId).orElseThrow(() -> new IllegalArgumentException("Ungültige Mitglieds-ID."));
        db.rpc("approve_account", Map.of("target", account.toString(), "p_member_id", key));
    }

    public void revokeApproval(UUID account) {
        db.rpc("revoke_approval", Map.of("target", account.toString()));
    }

    /** One-time code "ABCD-EFGH", valid 14 days, redeemable only by this account. */
    public String createActivationCode(UUID account, String memberId) {
        Map<String, Object> params = new LinkedHashMap<>();
        params.put("target", account.toString());
        params.put("p_member_id", memberId == null ? null : MemberStore.key(memberId).orElse(null));
        return db.rpc("create_activation_code", params).asText();
    }

    /** {@code role} null removes the role (account becomes pending). */
    public void setRole(UUID account, String role) {
        if (role != null && !ROLES.contains(role)) {
            throw new IllegalArgumentException("Unbekannte Rolle.");
        }
        Map<String, Object> params = new LinkedHashMap<>();
        params.put("target", account.toString());
        params.put("new_role", role);
        db.rpc("set_user_role", params);
    }

    /** Blocking signs the account out everywhere and rotates its calendar link. */
    public void setBlocked(UUID account, boolean blocked) {
        db.rpc("set_account_blocked", Map.of("target", account.toString(), "blocked", blocked));
    }

    public void delete(UUID account) {
        db.rpc("delete_account", Map.of("target", account.toString()));
    }

    /** Newest first (rolelog.read). */
    public List<RoleChange> roleChanges(int limit) {
        return java.util.stream.StreamSupport.stream(db.select("role_change_log",
                        "user_id,old_role,new_role,changed_by,changed_at", order("changed_at.desc"),
                        Postgrest.limit(limit))
                        .spliterator(), false)
                .map(r -> new RoleChange(uuid(r, "user_id"), text(r, "old_role"), text(r, "new_role"),
                        uuid(r, "changed_by"), Dates.parseTimestamp(r.path("changed_at").asText(null)).orElse(null)))
                .toList();
    }

    /** Block / unblock / delete history, newest first (rolelog.read). */
    public List<AdminAction> adminActions(int limit) {
        return java.util.stream.StreamSupport.stream(db.select("account_admin_log",
                        "action,target,target_email,target_name,actor,at", order("at.desc"),
                        Postgrest.limit(limit))
                        .spliterator(), false)
                .map(r -> new AdminAction(r.path("action").asText(), uuid(r, "target"), r.path("target_email").asText(""),
                        r.path("target_name").asText(""), uuid(r, "actor"),
                        Dates.parseTimestamp(r.path("at").asText(null)).orElse(null)))
                .toList();
    }

    private static UUID uuid(JsonNode row, String key) {
        return row.hasNonNull(key) ? UUID.fromString(row.get(key).asText()) : null;
    }

    private static String text(JsonNode row, String key) {
        return row.hasNonNull(key) ? row.get(key).asText() : null;
    }
}
