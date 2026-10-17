package it.a11y.blindensport.webadmin.supabase;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ArrayNode;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.function.Supplier;

import static it.a11y.blindensport.webadmin.supabase.SupabaseHttp.Param;

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

    public static Param in(String column, List<?> values) {
        List<String> parts = new ArrayList<>();
        values.forEach(v -> parts.add(String.valueOf(v)));
        return new Param(column, "in.(" + String.join(",", parts) + ")");
    }

    public static Param order(String spec) {
        return new Param("order", spec);
    }

    /** Rows as JSON objects. {@code filters} are PostgREST query items, e.g. {@code eq("id", id)}. */
    public ArrayNode select(String table, String columns, Param... filters) {
        List<Param> query = new ArrayList<>();
        query.add(new Param("select", columns));
        query.addAll(List.of(filters));
        SupabaseHttp.Result result = send("GET", table, query, null, Map.of(), "select " + table);
        JsonNode rows = http.parse(result.body());
        return rows instanceof ArrayNode array ? array : http.json().createArrayNode();
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
