package it.a11y.blindensport.webadmin.api;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import it.a11y.blindensport.webadmin.auth.AdminSession;
import it.a11y.blindensport.webadmin.auth.Permission;
import it.a11y.blindensport.webadmin.members.MemberBulkImport;
import it.a11y.blindensport.webadmin.members.MemberBulkInput;
import it.a11y.blindensport.webadmin.members.MemberInput;
import it.a11y.blindensport.webadmin.members.MemberJson;
import it.a11y.blindensport.webadmin.members.MemberPrivate;
import it.a11y.blindensport.webadmin.members.MemberRecord;
import it.a11y.blindensport.webadmin.members.MemberStore;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * The roster REST API, unchanged contract from the Swift server:
 * <ul>
 *   <li>members.manage — read/create/edit/delete entries</li>
 *   <li>members.private.read — see svnr, iban, birthDate, lastMedicalExamination</li>
 *   <li>members.private.write — change them</li>
 * </ul>
 * Supabase RLS enforces the same rules again, since every call runs as the admin.
 */
@Path("/api/members")
@Produces(MediaType.APPLICATION_JSON)
public class MembersResource {
    @Inject
    ObjectMapper json;

    @GET
    public List<Map<String, Object>> all(@Context ContainerRequestContext request) {
        AdminSession admin = CurrentAdmin.require(request, Permission.MEMBERS_MANAGE);
        return new MemberStore(admin.db()).all(admin.can(Permission.MEMBERS_PRIVATE_READ)).stream()
                .map(MemberJson::toMap).toList();
    }

    @GET
    @Path("{id}")
    public Map<String, Object> get(@PathParam("id") String id, @Context ContainerRequestContext request) {
        AdminSession admin = CurrentAdmin.require(request, Permission.MEMBERS_MANAGE);
        return new MemberStore(admin.db()).get(id, admin.can(Permission.MEMBERS_PRIVATE_READ))
                .map(MemberJson::toMap)
                .orElseThrow(() -> ApiException.notFound(id));
    }

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    public Response create(String body, @Context ContainerRequestContext request) {
        AdminSession admin = CurrentAdmin.require(request, Permission.MEMBERS_MANAGE);
        MemberInput input = decode(parse(body));
        input.validate();
        if (input.carriesPrivateData()) {
            requirePermission(admin, Permission.MEMBERS_PRIVATE_WRITE);
        }
        MemberRecord record = input.toNewRecord(UUID.randomUUID().toString().toUpperCase());
        new MemberStore(admin.db()).save(record, !record.privateData().isEmpty(), admin.userId());
        return Response.status(201).entity(MemberJson.toMap(record)).build();
    }

    @PUT
    @Path("{id}")
    @Consumes(MediaType.APPLICATION_JSON)
    public Map<String, Object> update(@PathParam("id") String id, String body,
                                      @Context ContainerRequestContext request) {
        AdminSession admin = CurrentAdmin.require(request, Permission.MEMBERS_MANAGE);
        JsonNode tree = parse(body);
        MemberInput input = decode(tree);
        input.validate();
        // An omitted field keeps its stored value; the two protected dates
        // can't be cleared with "" like svnr/iban, so an explicit null clears them.
        Set<String> clearedDates = new HashSet<>();
        for (String key : MemberInput.CLEARABLE_DATES) {
            if (tree.has(key) && tree.get(key).isNull()) {
                clearedDates.add(key);
            }
        }
        boolean touchesPrivate = input.carriesPrivateData() || !clearedDates.isEmpty();
        if (touchesPrivate) {
            requirePermission(admin, Permission.MEMBERS_PRIVATE_WRITE);
        }
        MemberStore store = new MemberStore(admin.db());
        MemberRecord existing = store.get(id, touchesPrivate).orElseThrow(() -> ApiException.notFound(id));
        MemberRecord record = input.applyTo(existing, clearedDates);
        boolean privateChanged = touchesPrivate && !record.privateData().equals(existing.privateData());
        store.save(record, privateChanged, admin.userId());
        if (!admin.can(Permission.MEMBERS_PRIVATE_READ)) {
            record = record.withPrivateData(MemberPrivate.EMPTY);
        } else if (!touchesPrivate) {
            record = record.withPrivateData(store.getPrivate(id).orElse(MemberPrivate.EMPTY));
        }
        return MemberJson.toMap(record);
    }

    @DELETE
    @Path("{id}")
    public Response delete(@PathParam("id") String id, @Context ContainerRequestContext request) {
        AdminSession admin = CurrentAdmin.require(request, Permission.MEMBERS_MANAGE);
        MemberStore store = new MemberStore(admin.db());
        if (store.get(id, false).isEmpty()) {
            throw ApiException.notFound(id);
        }
        store.delete(id);
        return Response.noContent().build();
    }

    /**
     * Bulk create-or-update from a JSON array — the same shape as the app's
     * export and {@code rootcli import-members}.
     */
    @POST
    @Path("import")
    @Consumes(MediaType.APPLICATION_JSON)
    public Map<String, Object> importMembers(String body, @Context ContainerRequestContext request) {
        AdminSession admin = CurrentAdmin.require(request, Permission.MEMBERS_MANAGE);
        List<MemberBulkInput> inputs;
        try {
            inputs = json.readValue(body == null ? "" : body, new TypeReference<>() {
            });
        } catch (JsonProcessingException e) {
            throw new ApiException(400, "Body must be a JSON array of members: " + e.getOriginalMessage());
        }
        if (inputs == null) {
            throw new ApiException(400, "Body must be a JSON array of members.");
        }
        if (inputs.stream().anyMatch(i -> !i.privateData().isEmpty())) {
            requirePermission(admin, Permission.MEMBERS_PRIVATE_WRITE);
        }
        MemberBulkImport.Result result = MemberBulkImport.run(inputs, new MemberStore(admin.db()), admin.userId());
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("succeeded", result.succeeded());
        response.put("failed", result.failed());
        response.put("total", result.total());
        response.put("messages", result.messages());
        return response;
    }

    private static void requirePermission(AdminSession admin, String permission) {
        if (!admin.can(permission)) {
            throw ApiException.forbidden(permission);
        }
    }

    private JsonNode parse(String body) {
        try {
            JsonNode tree = json.readTree(body == null ? "" : body);
            if (tree == null || !tree.isObject()) {
                throw new ApiException(400, "Body must be a JSON object.");
            }
            return tree;
        } catch (JsonProcessingException e) {
            throw new ApiException(400, "Invalid JSON: " + e.getOriginalMessage());
        }
    }

    private MemberInput decode(JsonNode tree) {
        try {
            return json.treeToValue(tree, MemberInput.class);
        } catch (JsonProcessingException e) {
            throw new ApiException(400, "Invalid member: " + e.getOriginalMessage());
        }
    }
}
