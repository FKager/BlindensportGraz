package it.a11y.blindensport.webui.api;

import it.a11y.blindensport.webui.auth.AdminSession;
import it.a11y.blindensport.webui.auth.Permission;
import it.a11y.blindensport.webui.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webui.club.ClubStore;
import it.a11y.blindensport.webui.members.MemberStore;
import it.a11y.blindensport.webui.prae.PraeForm;
import it.a11y.blindensport.webui.prae.PraeService;
import it.a11y.blindensport.webui.reports.KostZ;
import it.a11y.blindensport.webui.reports.ReportService;
import it.a11y.blindensport.webui.reports.Reports;
import it.a11y.blindensport.webui.reports.Teilnehmerliste;
import it.a11y.blindensport.webui.xlsx.XlsxPatch;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Invoicing ("Abrechnung") as REST — the same files as the web UI's
 * Abrechnung page and the app's Berichte menus, so the app can later fetch
 * them from here. All GET (nothing changes), club.manage like the app's
 * admin-only reports; anything holding PRAE forms (SVNR, IBAN) also needs
 * members.private.read.
 * <ul>
 *   <li>{@code GET /api/reports/months/{year}/{month}} — KostZ amounts and PRAE forms of a month's trainings</li>
 *   <li>{@code .../kostz.xlsx}, {@code .../prae.zip[?person=]}, {@code .../sammelabrechnung.zip}</li>
 *   <li>{@code GET /api/reports/tournaments} — tournaments to choose from</li>
 *   <li>{@code GET /api/reports/tournaments/{id}} — KostZ, PRAE, both TeilnehmerInnenlisten</li>
 *   <li>{@code .../kostz.xlsx}, {@code .../teilnehmer-sportler.xlsx}, {@code .../teilnehmer-helfer.xlsx},
 *       {@code .../prae.zip[?person=]}, {@code .../sammelabrechnung.zip}</li>
 * </ul>
 * Sammelabrechnung parts: {@code kostz}, {@code sportler}, {@code helfer} (default true) and
 * {@code prae} — repeated person ids; absent for everyone, {@code prae=none} for no one.
 */
@Path("/api/reports")
@Produces(MediaType.APPLICATION_JSON)
public class ReportsResource {
    static final String XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
    static final String ZIP = "application/zip";

    // --------------------------------------------------------------- months

    @GET
    @Path("months/{year}/{month}")
    public Map<String, Object> month(@PathParam("year") int year, @PathParam("month") int month,
                                     @Context ContainerRequestContext request) {
        Reports.Month report = month(admin(request), month, year, false);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("month", month);
        result.put("year", year);
        result.put("title", report.title());
        result.put("kostz", kostZ(report.kostZ()));
        result.put("prae", report.prae().stream().map(ReportsResource::form).toList());
        return result;
    }

    @GET
    @Path("months/{year}/{month}/kostz.xlsx")
    @Produces(XLSX)
    public Response monthKostZ(@PathParam("year") int year, @PathParam("month") int month,
                               @Context ContainerRequestContext request) {
        Reports.Month report = month(admin(request), month, year, false);
        return file(report.kostZ().xlsx(), "KostZ_" + report.label() + ".xlsx", XLSX);
    }

    @GET
    @Path("months/{year}/{month}/prae.zip")
    @Produces(ZIP)
    public Response monthPrae(@PathParam("year") int year, @PathParam("month") int month,
                              @QueryParam("person") String person, @Context ContainerRequestContext request) {
        AdminSession admin = privateReader(request);
        Reports.Month report = month(admin, month, year, true);
        return praeZip(report.prae(), person, "PRAE_" + report.label() + ".zip");
    }

    @GET
    @Path("months/{year}/{month}/sammelabrechnung.zip")
    @Produces(ZIP)
    public Response monthBundle(@PathParam("year") int year, @PathParam("month") int month,
                                @QueryParam("kostz") Boolean kostz, @QueryParam("prae") List<String> prae,
                                @Context ContainerRequestContext request) {
        Reports.Selection selection = selection(kostz, prae, false, false);
        AdminSession admin = withPrae(request, selection);
        Reports.Month report = month(admin, month, year, needsPrivate(selection));
        return bundle(report.sammelabrechnung(selection), "Sammelabrechnung_" + report.label() + ".zip");
    }

    // ---------------------------------------------------------- tournaments

    @GET
    @Path("tournaments")
    public List<Map<String, Object>> tournaments(@Context ContainerRequestContext request) {
        return service(admin(request)).tournaments().stream().map(ReportsResource::event).toList();
    }

    @GET
    @Path("tournaments/{id}")
    public Map<String, Object> tournament(@PathParam("id") String id, @Context ContainerRequestContext request) {
        Reports.Tournament report = tournament(admin(request), id, false);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("tournament", event(report.event()));
        result.put("kostz", kostZ(report.kostZ()));
        result.put("prae", report.prae().stream().map(ReportsResource::form).toList());
        result.put("teilnehmerSportler", teilnehmer(report.teilnehmer().sportler()));
        result.put("teilnehmerHelfer", teilnehmer(report.teilnehmer().helfer()));
        return result;
    }

    @GET
    @Path("tournaments/{id}/kostz.xlsx")
    @Produces(XLSX)
    public Response tournamentKostZ(@PathParam("id") String id, @Context ContainerRequestContext request) {
        Reports.Tournament report = tournament(admin(request), id, false);
        return file(report.kostZ().xlsx(), "KostZ_" + report.label() + ".xlsx", XLSX);
    }

    @GET
    @Path("tournaments/{id}/teilnehmer-sportler.xlsx")
    @Produces(XLSX)
    public Response sportler(@PathParam("id") String id, @Context ContainerRequestContext request) {
        Reports.Tournament report = tournament(admin(request), id, false);
        return file(report.teilnehmer().sportler().xlsx(), "TeilnehmerInnenliste-Sportler_" + report.label() + ".xlsx",
                XLSX);
    }

    @GET
    @Path("tournaments/{id}/teilnehmer-helfer.xlsx")
    @Produces(XLSX)
    public Response helfer(@PathParam("id") String id, @Context ContainerRequestContext request) {
        Reports.Tournament report = tournament(admin(request), id, false);
        return file(report.teilnehmer().helfer().xlsx(), "TeilnehmerInnenliste-Helfer_" + report.label() + ".xlsx",
                XLSX);
    }

    @GET
    @Path("tournaments/{id}/prae.zip")
    @Produces(ZIP)
    public Response tournamentPrae(@PathParam("id") String id, @QueryParam("person") String person,
                                   @Context ContainerRequestContext request) {
        Reports.Tournament report = tournament(privateReader(request), id, true);
        return praeZip(report.prae(), person, "PRAE_" + report.label() + ".zip");
    }

    @GET
    @Path("tournaments/{id}/sammelabrechnung.zip")
    @Produces(ZIP)
    public Response tournamentBundle(@PathParam("id") String id, @QueryParam("kostz") Boolean kostz,
                                     @QueryParam("prae") List<String> prae, @QueryParam("sportler") Boolean sportler,
                                     @QueryParam("helfer") Boolean helfer, @Context ContainerRequestContext request) {
        Reports.Selection selection = selection(kostz, prae, orTrue(sportler), orTrue(helfer));
        AdminSession admin = withPrae(request, selection);
        Reports.Tournament report = tournament(admin, id, needsPrivate(selection));
        return bundle(report.sammelabrechnung(selection), "Sammelabrechnung_" + report.label() + ".zip");
    }

    // -------------------------------------------------------------- helpers

    private static AdminSession admin(ContainerRequestContext request) {
        return CurrentAdmin.require(request, Permission.CLUB_MANAGE);
    }

    private static AdminSession privateReader(ContainerRequestContext request) {
        AdminSession admin = admin(request);
        if (!admin.can(Permission.MEMBERS_PRIVATE_READ)) {
            throw ApiException.forbidden(Permission.MEMBERS_PRIVATE_READ);
        }
        return admin;
    }

    private static AdminSession withPrae(ContainerRequestContext request, Reports.Selection selection) {
        return needsPrivate(selection) ? privateReader(request) : admin(request);
    }

    private static boolean needsPrivate(Reports.Selection selection) {
        return selection.praePeople() == null || !selection.praePeople().isEmpty();
    }

    private static ReportService service(AdminSession admin) {
        return new ReportService(new ClubStore(admin.db(), admin.userId()), new MemberStore(admin.db()));
    }

    private static Reports.Month month(AdminSession admin, int month, int year, boolean withPrivate) {
        if (month < 1 || month > 12 || year < 2000 || year > 2100) {
            throw new ApiException(400, "Monat 1–12 und ein Jahr zwischen 2000 und 2100 angeben.");
        }
        return service(admin).month(month, year, withPrivate);
    }

    private static Reports.Tournament tournament(AdminSession admin, String id, boolean withPrivate) {
        try {
            return service(admin).tournament(id, withPrivate);
        } catch (IllegalArgumentException e) {
            throw new ApiException(404, e.getMessage());
        }
    }

    private static Reports.Selection selection(Boolean kostz, List<String> prae, boolean sportler, boolean helfer) {
        Set<String> people = prae == null || prae.isEmpty() ? null
                : prae.contains("none") ? Set.of()
                : Set.copyOf(prae.stream().map(p -> p.toLowerCase(java.util.Locale.ROOT)).toList());
        Reports.Selection selection = new Reports.Selection(orTrue(kostz), people, sportler, helfer);
        if (selection.isEmpty(true)) {
            throw new ApiException(400, "Bitte mindestens einen Teil auswählen.");
        }
        return selection;
    }

    private static boolean orTrue(Boolean value) {
        return value == null || value;
    }

    private static Response praeZip(List<PraeForm> forms, String person, String name) {
        List<PraeForm> chosen = person == null ? forms
                : Reports.formsOf(forms, person.toLowerCase(java.util.Locale.ROOT));
        if (chosen.isEmpty()) {
            throw new ApiException(404, "Keine Einsätze mit PRAE-Betrag gefunden.");
        }
        return file(PraeService.zip(chosen), name, ZIP);
    }

    private static Response bundle(LinkedHashMap<String, byte[]> files, String name) {
        if (files.isEmpty()) {
            throw new ApiException(404, "Für diese Auswahl gibt es keine Dateien.");
        }
        return file(XlsxPatch.zip(files), name, ZIP);
    }

    /** Download with a UTF-8 file name (RFC 6266) and an ASCII fallback. */
    static Response file(byte[] content, String name, String type) {
        String ascii = name.replaceAll("[^A-Za-z0-9._-]", "_");
        String encoded = java.net.URLEncoder.encode(name, StandardCharsets.UTF_8).replace("+", "%20");
        return Response.ok(content, type)
                .header("Content-Disposition", "attachment; filename=\"" + ascii + "\"; filename*=UTF-8''" + encoded)
                .header("Cache-Control", "no-store")
                .build();
    }

    private static Map<String, Object> event(ClubEvent e) {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("id", e.id());
        row.put("title", e.title());
        row.put("startDate", e.startDate().toString());
        row.put("endDate", e.endDate().toString());
        row.put("city", e.city());
        row.put("country", e.country());
        return row;
    }

    private static Map<String, Object> kostZ(KostZ kostZ) {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("betrifft", kostZ.betrifft());
        row.put("ort", kostZ.ort());
        row.put("start", kostZ.start().toString());
        row.put("end", kostZ.end().toString());
        row.put("days", kostZ.dayCount());
        row.put("total", kostZ.total());
        row.put("people", kostZ.people().stream().map(p -> {
            Map<String, Object> person = new LinkedHashMap<>();
            person.put("personId", p.person().id());
            person.put("name", p.person().displayName());
            person.put("amount", p.amount());
            return person;
        }).toList());
        return row;
    }

    private static Map<String, Object> form(PraeForm form) {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("personId", form.person().id());
        row.put("person", form.person().displayName());
        row.put("purpose", form.purpose());
        row.put("month", form.month());
        row.put("year", form.year());
        row.put("total", form.total());
        row.put("warnings", form.capWarnings());
        return row;
    }

    private static Map<String, Object> teilnehmer(Teilnehmerliste list) {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("count", list.rows().size());
        row.put("maxRows", Teilnehmerliste.MAX_ROWS);
        row.put("days", list.dayCount());
        row.put("names", list.rows().stream().map(Teilnehmerliste.Row::name).toList());
        return row;
    }
}
