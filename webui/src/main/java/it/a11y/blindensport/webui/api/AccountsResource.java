package it.a11y.blindensport.webui.api;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import it.a11y.blindensport.webui.accounts.AccountService;
import it.a11y.blindensport.webui.accounts.AccountService.Account;
import it.a11y.blindensport.webui.auth.AdminSession;
import it.a11y.blindensport.webui.auth.Permission;
import it.a11y.blindensport.webui.members.Dates;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.MediaType;

import java.io.IOException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * App accounts over REST, for the {@code bsg} command line tool:
 * <ul>
 *   <li>{@code GET /api/accounts} — users.approve or roles.assign; blocked
 *       accounts are marked only with roles.assign</li>
 *   <li>{@code PUT /api/accounts/{id or e-mail}/role} with {@code {"role": "coach"}}
 *       ({@code null} = pending) — roles.assign</li>
 * </ul>
 * Every change is the same RPC the web UI uses, run as the caller: the
 * database re-checks the permission, refuses self-changes and protects the
 * last root, and logs the change under the caller's name.
 */
@Path("/api/accounts")
@Produces(MediaType.APPLICATION_JSON)
public class AccountsResource {
    @Inject
    ObjectMapper json;

    @GET
    public List<Map<String, Object>> all(@Context ContainerRequestContext request) {
        AdminSession admin = requireAccountAccess(request);
        return new AccountService(admin.db()).all(admin.can(Permission.ROLES_ASSIGN)).stream()
                .map(AccountsResource::toMap).toList();
    }

    @PUT
    @Path("{account}/role")
    @Consumes(MediaType.APPLICATION_JSON)
    public Map<String, Object> setRole(@PathParam("account") String account, String body,
                                       @Context ContainerRequestContext request) {
        AdminSession admin = CurrentAdmin.require(request, Permission.ROLES_ASSIGN);
        String role = role(body);
        AccountService accounts = new AccountService(admin.db());
        Account target = find(accounts.all(true), account);
        accounts.setRole(target.id(), role);
        return toMap(find(accounts.all(true), target.id().toString()));
    }

    private static AdminSession requireAccountAccess(ContainerRequestContext request) {
        AdminSession admin = CurrentAdmin.require(request);
        if (!admin.can(Permission.USERS_APPROVE) && !admin.can(Permission.ROLES_ASSIGN)) {
            throw ApiException.forbidden(Permission.USERS_APPROVE);
        }
        return admin;
    }

    private String role(String body) {
        JsonNode node;
        try {
            node = json.readTree(body == null || body.isBlank() ? "{}" : body);
        } catch (IOException e) {
            throw new ApiException(400, "Body muss JSON sein, z.B. {\"role\": \"coach\"}.");
        }
        if (!node.has("role")) {
            throw new ApiException(400, "Feld \"role\" fehlt: member, coach, admin, root oder null.");
        }
        if (node.get("role").isNull()) {
            return null;
        }
        String role = node.get("role").asText().trim().toLowerCase(Locale.ROOT);
        if (!AccountService.ROLES.contains(role)) {
            throw new ApiException(400, "Unbekannte Rolle \"" + role + "\": member, coach, admin, root oder null.");
        }
        return role;
    }

    /** By id or, case-insensitively, by e-mail. */
    static Account find(List<Account> all, String key) {
        String wanted = key.trim();
        for (Account a : all) {
            if (a.id().toString().equalsIgnoreCase(wanted) || a.email().equalsIgnoreCase(wanted)) {
                return a;
            }
        }
        throw new ApiException(404, "Kein Konto mit dieser ID oder E-Mail-Adresse.");
    }

    static Map<String, Object> toMap(Account a) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", a.id().toString());
        m.put("email", a.email());
        m.put("firstName", a.firstName());
        m.put("lastName", a.lastName());
        m.put("role", a.role());
        m.put("approved", a.approval() != null);
        m.put("memberId", a.approval() == null ? null : a.approval().memberId());
        m.put("blocked", a.blocked());
        m.put("createdAt", a.createdAt() == null ? null : Dates.formatApi(a.createdAt()));
        return m;
    }

}
