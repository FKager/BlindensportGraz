package it.a11y.blindensport.webui.supabase;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ArrayNode;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.function.Supplier;

import static it.a11y.blindensport.webui.supabase.SupabaseHttp.Param;

/**
 * PostgREST (tables + RPCs) with one identity: either a signed-in admin
 * (anon key + their access token — RLS applies) or the service role (feed
 * only). Port of RootCLI's {@code SupabaseAdminClient} PostgREST half.
 */
public final class Postgrest {
    private final SupabaseHttp http;
    private final String apiKey;
    private final Supplier<String> bearer;

    public Postgrest(SupabaseHttp http, String apiKey, Supplier<String> bearer) {
        this.http = http;
        this.apiKey = apiKey;
        this.bearer = bearer;
    }

    public static Param eq(String column, Object value) {
        return new Param(column, "eq." + value);
    }

    public static Param gte(String column, Object value) {
        return new Param(column, "gte." + value);
    }

    public static Param in(String column, List<?> values) {
        List<String> parts = new ArrayList<>();
        values.forEach(v -> parts.add(String.valueOf(v)));
        return new Param(column, "in.(" + String.join(",", parts) + ")");
    }

    public static Param order(String spec) {
        return new Param("order", spec);
    }

    public static Param limit(int rows) {
        return new Param("limit", String.valueOf(rows));
    }

    /**
     * Rows per request. PostgREST answers at most {@code max_rows} rows (1000
     * on Supabase, supabase/config.toml) and says nothing when it cuts a
     * result off, so every read pages until a page comes back short.
     */
    static final int PAGE_SIZE = 1000;

    /** Primary keys that aren't {@code id}; a comma list is a composite key. */
    private static final Map<String, String> KEYS = Map.of(
            "user_roles", "user_id",
            "account_approvals", "user_id",
            "member_private", "member_id",
            "member_private_requests", "member_id",
            "club_functions", "function_key",
            "role_permissions", "role,permission");

    /**
     * Rows as JSON objects, all of them. {@code filters} are PostgREST query
     * items, e.g. {@code eq("id", id)}.
     * <ul>
     *   <li>With a {@code limit}: one request, as asked.</li>
     *   <li>Without an {@code order}: pages after the last row read, by the
     *       table's key — nothing is skipped even if rows change meanwhile.</li>
     *   <li>With an {@code order}: pages by position in that order, the key
     *       breaking ties; a row read twice is kept once.</li>
     * </ul>
     * The key column is added to {@code columns} when it isn't there.
     */
    public ArrayNode select(String table, String columns, Param... filters) {
        List<Param> given = List.of(filters);
        if (given.stream().anyMatch(p -> p.name().equals("limit"))) {
            return page(table, columns, given);
        }
        String key = KEYS.getOrDefault(table, "id");
        List<String> keyColumns = List.of(key.split(","));
        String selected = withColumns(columns, keyColumns);
        Optional<Param> order = given.stream().filter(p -> p.name().equals("order")).findFirst();
        List<Param> other = given.stream().filter(p -> !p.name().equals("order")).toList();
        ArrayNode all = http.json().createArrayNode();
        if (order.isEmpty() && keyColumns.size() == 1) {
            String last = null;
            while (true) {
                List<Param> query = new ArrayList<>(other);
                query.add(new Param("order", key + ".asc"));
                query.add(limit(PAGE_SIZE));
                if (last != null) {
                    query.add(new Param(key, "gt." + last));
                }
                ArrayNode page = page(table, selected, query);
                all.addAll(page);
                if (page.size() < PAGE_SIZE) {
                    return all;
                }
                last = page.get(page.size() - 1).path(key).asText();
            }
        }
        String orderBy = withTieBreak(order.map(Param::value).orElse(""), keyColumns);
        Set<String> seen = new HashSet<>();
        for (int offset = 0; ; offset += PAGE_SIZE) {
            List<Param> query = new ArrayList<>(other);
            query.add(new Param("order", orderBy));
            query.add(limit(PAGE_SIZE));
            query.add(new Param("offset", String.valueOf(offset)));
            ArrayNode page = page(table, selected, query);
            for (JsonNode row : page) {
                // A row without its key (a view, a test double) is never taken for a duplicate.
                boolean keyed = keyColumns.stream().allMatch(row::hasNonNull);
                StringBuilder id = new StringBuilder();
                keyColumns.forEach(c -> id.append(row.path(c).asText()).append('|'));
                if (!keyed || seen.add(id.toString())) {
                    all.add(row);
                }
            }
            if (page.size() < PAGE_SIZE) {
                return all;
            }
        }
    }

    private ArrayNode page(String table, String columns, List<Param> filters) {
        List<Param> query = new ArrayList<>();
        query.add(new Param("select", columns));
        query.addAll(filters);
        SupabaseHttp.Result result = send("GET", table, query, null, Map.of(), "select " + table);
        JsonNode rows = http.parse(result.body());
        return rows instanceof ArrayNode array ? array : http.json().createArrayNode();
    }

    /** {@code order} ("start_date.desc,title.asc") with the key columns appended unless already ordered by. */
    static String withTieBreak(String order, List<String> keyColumns) {
        List<String> ordered = new ArrayList<>();
        for (String part : order.split(",")) {
            if (!part.isBlank()) {
                ordered.add(part.trim().split("\\.")[0]);
            }
        }
        StringBuilder result = new StringBuilder(order);
        for (String column : keyColumns) {
            if (!ordered.contains(column)) {
                result.append(result.isEmpty() ? "" : ",").append(column).append(".asc");
            }
        }
        return result.toString();
    }

    /** {@code columns} plus any of {@code needed} it doesn't select yet ("*" selects all). */
    static String withColumns(String columns, List<String> needed) {
        List<String> parts = new ArrayList<>();
        for (String part : columns.split(",")) {
            parts.add(part.trim());
        }
        if (parts.contains("*")) {
            return columns;
        }
        StringBuilder result = new StringBuilder(columns);
        for (String column : needed) {
            if (!parts.contains(column)) {
                result.append(',').append(column);
            }
        }
        return result.toString();
    }

    /** Insert-or-update ({@code resolution=merge-duplicates}). */
    public void upsert(String table, List<? extends Map<String, ?>> rows, String onConflict) {
        if (rows.isEmpty()) {
            return;
        }
        send("POST", table, List.of(new Param("on_conflict", onConflict)), rows,
                Map.of("Prefer", "resolution=merge-duplicates,return=minimal"), "upsert " + table);
    }

    public void insert(String table, Map<String, ?> row) {
        send("POST", table, List.of(), List.of(row), Map.of("Prefer", "return=minimal"), "insert " + table);
    }

    /**
     * PATCH matching rows. Returns how many rows changed — 0 usually means RLS
     * hid the row (PostgREST doesn't report that as an error).
     */
    public int update(String table, Map<String, ?> values, Param... filters) {
        SupabaseHttp.Result result = send("PATCH", table, List.of(filters), values,
                Map.of("Prefer", "return=representation"), "update " + table);
        JsonNode rows = http.parse(result.body());
        return rows.isArray() ? rows.size() : 0;
    }

    /** DELETE matching rows; returns how many were deleted (0 = none visible / allowed). */
    public int delete(String table, Param... filters) {
        SupabaseHttp.Result result = send("DELETE", table, List.of(filters), null,
                Map.of("Prefer", "return=representation"), "delete " + table);
        JsonNode rows = http.parse(result.body());
        return rows.isArray() ? rows.size() : 0;
    }

    /** Supabase Storage with the same identity (storage RLS applies to users). */
    public Storage storage() {
        return new Storage(http, apiKey, bearer);
    }

    /** POST /rpc/{name}; the parsed JSON result (null node for void functions). */
    public JsonNode rpc(String name, Map<String, ?> params) {
        SupabaseHttp.Result result = send("POST", "rpc/" + name, List.of(), params, Map.of(), "rpc " + name);
        return http.parse(result.body());
    }

    private SupabaseHttp.Result send(String method, String path, List<Param> query, Object body,
                                     Map<String, String> headers, String what) {
        return http.check(http.send(method, "rest/v1/" + path, query, body, headers, apiKey, bearer.get()), what);
    }
}
