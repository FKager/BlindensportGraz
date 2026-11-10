package it.a11y.blindensport.webui.ui;

import com.vaadin.flow.component.checkbox.Checkbox;
import com.vaadin.flow.component.checkbox.CheckboxGroup;
import com.vaadin.flow.component.grid.Grid;
import com.vaadin.flow.component.grid.GridVariant;
import com.vaadin.flow.component.html.Anchor;
import com.vaadin.flow.component.html.H2;
import com.vaadin.flow.component.html.ListItem;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.html.UnorderedList;
import com.vaadin.flow.component.orderedlayout.FlexComponent;
import com.vaadin.flow.component.orderedlayout.HorizontalLayout;
import com.vaadin.flow.component.orderedlayout.VerticalLayout;
import com.vaadin.flow.component.radiobutton.RadioButtonGroup;
import com.vaadin.flow.component.select.Select;
import com.vaadin.flow.router.BeforeEnterEvent;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.QueryParameters;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.server.streams.DownloadHandler;
import com.vaadin.flow.server.streams.DownloadResponse;
import it.a11y.blindensport.webui.auth.AdminSession;
import it.a11y.blindensport.webui.auth.AdminSessions;
import it.a11y.blindensport.webui.auth.Permission;
import it.a11y.blindensport.webui.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webui.club.ClubStore;
import it.a11y.blindensport.webui.members.MemberStore;
import it.a11y.blindensport.webui.prae.PraeForm;
import it.a11y.blindensport.webui.prae.PraeService;
import it.a11y.blindensport.webui.reports.KostZ;
import it.a11y.blindensport.webui.reports.KostZ.PersonAmount;
import it.a11y.blindensport.webui.reports.ReportService;
import it.a11y.blindensport.webui.reports.Reports;
import it.a11y.blindensport.webui.reports.Teilnehmerliste;
import it.a11y.blindensport.webui.reports.Trainingsfrequenzliste;
import it.a11y.blindensport.webui.xlsx.XlsxPatch;
import jakarta.inject.Inject;

import java.io.ByteArrayInputStream;
import java.text.NumberFormat;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

import static it.a11y.blindensport.webui.members.Dates.CLUB_ZONE;

/**
 * "Abrechnung": the invoicing of the app's Berichte menus — KostZ, PRAE
 * (Formular + Darstellung) and, for tournaments, the TeilnehmerInnenlisten
 * of players and helpers, one at a time or bundled as a Sammelabrechnung.
 * Either every training of a month or one tournament, as in the app. Admins
 * only (club.manage, like the app); PRAE files also need members.private.read
 * for SVNR and IBAN. Files are made when downloaded, from the current data.
 * Opened from Termine with {@code ?turnier=<id>} or {@code ?monat=&jahr=}.
 */
@Route(value = "abrechnung", layout = MainLayout.class)
@PageTitle("Abrechnung – Blindensport Graz")
@RequiresPermission(Permission.CLUB_MANAGE)
public class ReportsView extends AdminView {
    static final String MONTH = "Trainings eines Monats";
    static final String TOURNAMENT = "Turnier";
    private static final Locale AUSTRIA = Locale.forLanguageTag("de-AT");
    private static final DateTimeFormatter MONTH_NAME = DateTimeFormatter.ofPattern("LLLL", AUSTRIA);

    private final RadioButtonGroup<String> scope = new RadioButtonGroup<>("Abrechnen für");
    private final Select<Integer> month = new Select<>();
    private final Select<Integer> year = new Select<>();
    private final Select<String> sport = new Select<>();
    private final Select<ClubEvent> tournament = new Select<>();
    private final HorizontalLayout periodFields = new HorizontalLayout(month, year, sport);
    private final VerticalLayout result = new VerticalLayout();

    private final Checkbox bundleKostZ = new Checkbox("KostZ-Formular", true);
    private final Checkbox bundleSportler = new Checkbox("TeilnehmerInnenliste Sportler", true);
    private final Checkbox bundleHelfer = new Checkbox("TeilnehmerInnenliste Helfer", true);
    private final Checkbox bundleFrequenz = new Checkbox("Trainingsfrequenzliste", true);
    private final CheckboxGroup<String> bundlePrae = new CheckboxGroup<>("PRAE (Formular + Darstellung)");
    private final Paragraph bundleHint = new Paragraph();
    private Anchor bundleDownload;

    private Map<String, String> personNames = Map.of();
    private boolean loading;
    /** Tournament named in the address, chosen once the list is loaded. */
    private String pendingTournament;
    /** Sport named in the address, chosen once the list is loaded. */
    private String pendingSport;

    /** What the download links make; replaced as the choices change. */
    private volatile Request request;

    private record Request(boolean tournament, int month, int year, String sport, String tournamentId,
                           Reports.Selection selection) {
    }

    @Inject
    public ReportsView(AdminSessions sessions) {
        super(sessions, "Abrechnung");
        add(new Paragraph("KostZ, PRAE, Trainingsfrequenzliste und TeilnehmerInnenlisten auf den Formularen von "
                + "Sport Austria, wie in der App unter „Berichte“. Trainings werden pro Monat und Sportart "
                + "abgerechnet, Turniere einzeln."));

        scope.setItems(MONTH, TOURNAMENT);
        scope.setValue(MONTH);
        scope.addValueChangeListener(e -> {
            showScopeFields();
            reload();
        });

        LocalDate today = LocalDate.now(CLUB_ZONE);
        month.setLabel("Monat");
        month.setItems(IntStream.rangeClosed(1, 12).boxed().toList());
        month.setItemLabelGenerator(m -> capitalized(MONTH_NAME.format(LocalDate.of(2000, m, 1))));
        month.setValue(today.getMonthValue());
        year.setLabel("Jahr");
        year.setItems(IntStream.rangeClosed(2020, today.getYear() + 1).boxed().sorted((a, b) -> b - a).toList());
        year.setItemLabelGenerator(String::valueOf);
        year.setValue(today.getYear());
        sport.setLabel("Sportart");
        sport.setEmptySelectionAllowed(false);
        month.addValueChangeListener(e -> reload());
        year.addValueChangeListener(e -> reload());
        sport.addValueChangeListener(e -> reload());
        periodFields.setDefaultVerticalComponentAlignment(FlexComponent.Alignment.BASELINE);
        periodFields.setWrap(true);

        tournament.setLabel("Turnier");
        tournament.setItemLabelGenerator(ReportsView::tournamentLabel);
        tournament.setEmptySelectionAllowed(false);
        tournament.addValueChangeListener(e -> reload());

        bundleKostZ.addValueChangeListener(e -> updateRequest());
        bundleSportler.addValueChangeListener(e -> updateRequest());
        bundleHelfer.addValueChangeListener(e -> updateRequest());
        bundleFrequenz.addValueChangeListener(e -> updateRequest());
        bundlePrae.setItemLabelGenerator(id -> personNames.getOrDefault(id, id));
        bundlePrae.addValueChangeListener(e -> updateRequest());

        result.setPadding(false);
        add(scope, periodFields, tournament, result);
        showScopeFields();
    }

    @Override
    public void beforeEnter(BeforeEnterEvent event) {
        QueryParameters query = event.getLocation().getQueryParameters();
        loading = true;
        query.getSingleParameter("turnier").ifPresent(id -> scope.setValue(TOURNAMENT));
        query.getSingleParameter("monat").flatMap(ReportsView::number).filter(m -> m >= 1 && m <= 12)
                .ifPresent(m -> {
                    scope.setValue(MONTH);
                    month.setValue(m);
                });
        query.getSingleParameter("jahr").flatMap(ReportsView::number).filter(y -> y >= 2020 && y <= 2100)
                .ifPresent(y -> {
                    if (y > LocalDate.now(CLUB_ZONE).getYear() + 1) {
                        year.setItems(IntStream.rangeClosed(2020, y).boxed().sorted((a, b) -> b - a).toList());
                    }
                    year.setValue(y);
                });
        pendingTournament = query.getSingleParameter("turnier").map(id -> id.toLowerCase(Locale.ROOT)).orElse(null);
        pendingSport = query.getSingleParameter("sportart").orElse(null);
        loading = false;
        super.beforeEnter(event);
    }

    @Override
    protected void refresh() {
        loading = true;
        try {
            String keep = pendingTournament != null ? pendingTournament
                    : tournament.getValue() == null ? null : tournament.getValue().id();
            pendingTournament = null;
            String keepSport = pendingSport != null ? pendingSport : sport.getValue();
            pendingSport = null;
            List<String> sports = service(session()).trainingSports();
            sport.setItems(sports);
            sport.setValue(sports.contains(keepSport) ? keepSport : sports.isEmpty() ? null : sports.get(0));
            List<ClubEvent> tournaments = service(session()).tournaments();
            tournament.setItems(tournaments);
            tournament.setValue(tournaments.stream().filter(t -> t.id().equals(keep)).findFirst()
                    .orElse(tournaments.isEmpty() ? null : tournaments.get(0)));
        } finally {
            loading = false;
        }
        calculate();
    }

    private void reload() {
        if (!loading) {
            attempt("Laden", this::calculate);
        }
    }

    private void showScopeFields() {
        boolean isTournament = TOURNAMENT.equals(scope.getValue());
        periodFields.setVisible(!isTournament);
        tournament.setVisible(isTournament);
    }

    // ------------------------------------------------------------ the page

    private void calculate() {
        result.removeAll();
        request = null;
        ReportService service = service(session());
        if (TOURNAMENT.equals(scope.getValue())) {
            ClubEvent chosen = tournament.getValue();
            if (chosen == null) {
                result.add(new Paragraph("Es gibt noch keine Turniere."));
                return;
            }
            Reports.Tournament report = service.tournament(chosen.id(), false);
            show(report.kostZ(), report.prae(), report.teilnehmer(), null, report.event().title());
        } else {
            if (sport.getValue() == null) {
                result.add(new Paragraph("Noch kein Training angelegt."));
                return;
            }
            Reports.Month report = service.month(month.getValue(), year.getValue(), sport.getValue(), false);
            show(report.kostZ(), report.prae(), null, report.trainingsfrequenzliste(),
                    report.title() + ", " + sport.getValue());
        }
    }

    private void show(KostZ kostZ, List<PraeForm> prae, Teilnehmerliste.Pair teilnehmer,
                      Trainingsfrequenzliste frequenz, String title) {
        boolean isTournament = teilnehmer != null;
        boolean privateRead = can(Permission.MEMBERS_PRIVATE_READ);
        personNames = kostZ.people().stream()
                .collect(Collectors.toMap(p -> p.person().id(), p -> p.person().displayName(), (a, b) -> a,
                        LinkedHashMap::new));
        Map<String, List<String>> warnings = prae.stream().collect(Collectors.groupingBy(f -> f.person().id(),
                Collectors.flatMapping(f -> f.capWarnings().stream(), Collectors.toList())));

        // Honoraria
        result.add(new H2("Honorare Trainer:innen / Helfer:innen"));
        result.add(new Paragraph(period(kostZ, isTournament)));
        if (kostZ.people().isEmpty()) {
            result.add(new Paragraph(isTournament ? "Keine Einsätze mit hinterlegtem PRAE-Betrag bei diesem Turnier."
                    : "Keine Einsätze mit hinterlegtem PRAE-Betrag in diesem Monat für diese Sportart."));
        } else {
            Grid<PersonAmount> grid = new Grid<>();
            grid.addColumn(p -> p.person().displayName()).setHeader("Name").setRowHeader(true).setFlexGrow(1);
            grid.addColumn(p -> euro(p.amount())).setHeader("Betrag").setAutoWidth(true);
            grid.addColumn(p -> String.join("; ", warnings.getOrDefault(p.person().id(), List.of())))
                    .setHeader("Hinweise").setFlexGrow(1);
            if (privateRead) {
                grid.addComponentColumn(p -> download("PRAE herunterladen",
                                "PRAE von " + p.person().displayName() + " herunterladen", praeOf(p.person().id())))
                        .setHeader("PRAE").setAutoWidth(true).setFlexGrow(0);
            }
            grid.setItems(kostZ.people());
            grid.setAllRowsVisible(true);
            grid.addThemeVariants(GridVariant.LUMO_ROW_STRIPES);
            grid.getElement().setAttribute("aria-label", "Honorare " + title);
            result.add(grid);
            result.add(new Paragraph("Gesamt: " + euro(kostZ.total()) + " · " + people(kostZ.personCount())));
        }

        // Single forms
        result.add(new H2("Formulare"));
        UnorderedList forms = new UnorderedList();
        forms.add(new ListItem(download("KostZ-Formular herunterladen", null, kostZFile())));
        if (isTournament) {
            forms.add(new ListItem(download("TeilnehmerInnenliste Sportler herunterladen (" + people(
                    teilnehmer.sportler().rows().size()) + ")", null, teilnehmerFile(true))));
            forms.add(new ListItem(download("TeilnehmerInnenliste Helfer herunterladen (" + people(
                    teilnehmer.helfer().rows().size()) + ")", null, teilnehmerFile(false))));
        }
        boolean hasFrequenz = frequenz != null && !frequenz.dates().isEmpty();
        if (hasFrequenz) {
            forms.add(new ListItem(download("Trainingsfrequenzliste herunterladen (" + frequenzPeriod(month.getValue(), year.getValue())
                    + ")", null, frequenzFile())));
        }
        if (privateRead && !prae.isEmpty()) {
            forms.add(new ListItem(download("Alle PRAE-Formulare mit Darstellung herunterladen (ZIP, "
                    + prae.size() + (prae.size() == 1 ? " Formular)" : " Formulare)"), null, praeOf(null))));
        }
        result.add(forms);
        result.add(new Paragraph("Auf dem KostZ-Formular werden nur „HONORARE / VERGÜTUNGEN“, Zeitraum, Ort und "
                + "Personenanzahl vorausgefüllt; alle übrigen Kostenarten und die Beilagen-Nummern bitte von Hand "
                + "ergänzen."));
        if (hasFrequenz && frequenz.missingDates() > 0) {
            result.add(new Paragraph("Achtung: Die Trainingsfrequenzliste hat nur " + Trainingsfrequenzliste.MAX_DATES
                    + " Spalten. " + frequenz.missingDates() + " Trainingstage am Ende fehlen und bitte von Hand "
                    + "nachtragen."));
        }
        if (hasFrequenz && frequenz.missingPeople() > 0) {
            result.add(new Paragraph("Achtung: Die Trainingsfrequenzliste hat nur " + Trainingsfrequenzliste.MAX_PEOPLE
                    + " Zeilen. " + people(frequenz.missingPeople()) + " fehlen und bitte von Hand nachtragen."));
        }
        if (isTournament) {
            for (Teilnehmerliste list : List.of(teilnehmer.sportler(), teilnehmer.helfer())) {
                if (list.overflows()) {
                    result.add(new Paragraph("Achtung: " + people(list.rows().size()) + " – das Formular hat nur "
                            + Teilnehmerliste.MAX_ROWS + " Zeilen. Die Anzahl stimmt, die übrigen Namen bitte von Hand "
                            + "nachtragen."));
                }
            }
        }
        if (!privateRead && !prae.isEmpty()) {
            result.add(new Paragraph("PRAE-Formulare enthalten SVNR und IBAN. Ihre Rolle darf diese Daten nicht "
                    + "lesen, darum fehlen sie hier."));
        }

        // Sammelabrechnung
        result.add(new H2("Sammelabrechnung"));
        result.add(new Paragraph("Bündelt die ausgewählten Teile als eine ZIP-Datei. Alles ist vorausgewählt."));
        bundleSportler.setVisible(isTournament);
        bundleHelfer.setVisible(isTournament);
        bundleFrequenz.setVisible(hasFrequenz);
        bundlePrae.setItems(privateRead ? List.copyOf(personNames.keySet()) : List.of());
        bundlePrae.setValue(privateRead ? new HashSet<>(personNames.keySet()) : Set.of());
        bundlePrae.setVisible(privateRead && !personNames.isEmpty());
        bundleKostZ.setValue(true);
        bundleSportler.setValue(true);
        bundleHelfer.setValue(true);
        bundleFrequenz.setValue(hasFrequenz);
        bundleDownload = download("Sammelabrechnung herunterladen (ZIP)", null, bundleFile());
        VerticalLayout bundle = new VerticalLayout(bundleKostZ, bundlePrae, bundleFrequenz, bundleSportler, bundleHelfer,
                bundleDownload, bundleHint);
        bundle.setPadding(false);
        bundle.setSpacing(false);
        result.add(bundle);

        String tournamentId = isTournament ? tournament.getValue().id() : null;
        request = new Request(isTournament, month.getValue(), year.getValue(), isTournament ? null : sport.getValue(),
                tournamentId, selection(privateRead));
        updateBundleState();
    }

    private void updateRequest() {
        Request current = request;
        if (current == null) {
            return;
        }
        request = new Request(current.tournament(), current.month(), current.year(), current.sport(),
                current.tournamentId(),
                selection(can(Permission.MEMBERS_PRIVATE_READ)));
        updateBundleState();
    }

    private Reports.Selection selection(boolean privateRead) {
        Set<String> prae = privateRead ? Set.copyOf(bundlePrae.getValue()) : Set.of();
        return new Reports.Selection(bundleKostZ.getValue(), prae, bundleSportler.getValue(), bundleHelfer.getValue(),
                bundleFrequenz.getValue());
    }

    private void updateBundleState() {
        Request current = request;
        boolean empty = current == null || current.selection().isEmpty(current.tournament());
        if (bundleDownload != null) {
            bundleDownload.setEnabled(!empty);
        }
        bundleHint.setText(empty ? "Bitte mindestens einen Teil auswählen." : "");
        bundleHint.setVisible(empty);
    }

    // ----------------------------------------------------------- downloads

    private interface FileMaker {
        /** Name and content, or null when there is nothing to make. */
        Map.Entry<String, byte[]> make(ReportService service, Request request);
    }

    /**
     * A download link whose file is made when clicked, as the current admin,
     * for the choices shown at that moment.
     */
    private Anchor download(String text, String ariaLabel, FileMaker maker) {
        Anchor anchor = new Anchor(DownloadHandler.fromInputStream(event -> {
            AdminSession admin = UiSession.current(sessions).orElse(null);
            Request current = request;
            if (admin == null || current == null || !admin.can(Permission.CLUB_MANAGE)) {
                return DownloadResponse.error(403);
            }
            Map.Entry<String, byte[]> file = maker.make(service(admin), current);
            if (file == null) {
                return DownloadResponse.error(404);
            }
            String type = file.getKey().endsWith(".zip") ? "application/zip"
                    : "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
            return new DownloadResponse(new ByteArrayInputStream(file.getValue()), file.getKey(), type,
                    file.getValue().length);
        }), text);
        anchor.getElement().setAttribute("download", true);
        if (ariaLabel != null) {
            GermanUi.label(anchor, ariaLabel);
        }
        return anchor;
    }

    private static FileMaker kostZFile() {
        return (service, r) -> {
            if (r.tournament()) {
                Reports.Tournament t = service.tournament(r.tournamentId(), false);
                return Map.entry("KostZ_" + t.label() + ".xlsx", t.kostZ().xlsx());
            }
            Reports.Month m = service.month(r.month(), r.year(), r.sport(), false);
            return Map.entry("KostZ_" + m.label() + ".xlsx", m.kostZ().xlsx());
        };
    }

    private static FileMaker teilnehmerFile(boolean sportler) {
        return (service, r) -> {
            if (!r.tournament()) {
                return null;
            }
            Reports.Tournament t = service.tournament(r.tournamentId(), false);
            Teilnehmerliste list = sportler ? t.teilnehmer().sportler() : t.teilnehmer().helfer();
            return Map.entry("TeilnehmerInnenliste-" + (sportler ? "Sportler" : "Helfer") + "_" + t.label() + ".xlsx",
                    list.xlsx());
        };
    }

    private static FileMaker frequenzFile() {
        return (service, r) -> {
            if (r.tournament()) {
                return null;
            }
            Reports.Month m = service.month(r.month(), r.year(), r.sport(), false);
            return m.hasTrainingsfrequenzliste()
                    ? Map.entry("Trainingsfrequenzliste_" + m.label() + ".xlsx", m.trainingsfrequenzliste().xlsx())
                    : null;
        };
    }

    /** One person's PRAE forms, or everyone's when {@code personId} is null; needs members.private.read. */
    private FileMaker praeOf(String personId) {
        return (service, r) -> {
            if (!UiSession.current(sessions).map(a -> a.can(Permission.MEMBERS_PRIVATE_READ)).orElse(false)) {
                return null;
            }
            List<PraeForm> forms;
            String label;
            if (r.tournament()) {
                Reports.Tournament t = service.tournament(r.tournamentId(), true);
                forms = t.prae();
                label = t.label();
            } else {
                Reports.Month m = service.month(r.month(), r.year(), r.sport(), true);
                forms = m.prae();
                label = m.label();
            }
            if (personId != null) {
                forms = Reports.formsOf(forms, personId);
                if (!forms.isEmpty()) {
                    label = Reports.fileSafe(forms.get(0).person().displayName()) + "_" + label;
                }
            }
            return forms.isEmpty() ? null : Map.entry("PRAE_" + label + ".zip", PraeService.zip(forms));
        };
    }

    private static FileMaker bundleFile() {
        return (service, r) -> {
            if (r.selection().isEmpty(r.tournament())) {
                return null;
            }
            boolean withPrivate = !r.selection().praePeople().isEmpty();
            LinkedHashMap<String, byte[]> files;
            String label;
            if (r.tournament()) {
                Reports.Tournament t = service.tournament(r.tournamentId(), withPrivate);
                files = t.sammelabrechnung(r.selection());
                label = t.label();
            } else {
                Reports.Month m = service.month(r.month(), r.year(), r.sport(), withPrivate);
                files = m.sammelabrechnung(r.selection());
                label = m.label();
            }
            return files.isEmpty() ? null : Map.entry("Sammelabrechnung_" + label + ".zip", XlsxPatch.zip(files));
        };
    }

    // ------------------------------------------------------------- helpers

    private static ReportService service(AdminSession admin) {
        return new ReportService(new ClubStore(admin.db(), admin.userId()), new MemberStore(admin.db()));
    }

    private static String period(KostZ kostZ, boolean isTournament) {
        String from = GermanUi.DAY.format(kostZ.start());
        String to = GermanUi.DAY.format(kostZ.end());
        String days = isTournament ? (kostZ.dayCount() == 1 ? "1 Tag" : kostZ.dayCount() + " Tage")
                : (kostZ.dayCount() == 1 ? "1 Training" : kostZ.dayCount() + " Trainings");
        String betrifft = kostZ.betrifft().isBlank() ? "" : "Betrifft: " + kostZ.betrifft() + ". ";
        String ort = kostZ.ort() == null || kostZ.ort().isBlank() ? "" : " Ort: " + kostZ.ort() + ".";
        return betrifft + "Zeitraum: " + from + " bis " + to + " (" + days + ")." + ort;
    }

    /** "Juli bis August 2026" (season start to the chosen month), or "Juli 2026" for the season's first month. */
    static String frequenzPeriod(int month, int year) {
        int first = month <= 6 ? 1 : 7;
        String to = capitalized(MONTH_NAME.format(LocalDate.of(2000, month, 1))) + " " + year;
        return first == month ? to : capitalized(MONTH_NAME.format(LocalDate.of(2000, first, 1))) + " bis " + to;
    }

    static String euro(double amount) {
        return NumberFormat.getCurrencyInstance(AUSTRIA).format(amount);
    }

    private static String people(int count) {
        return count == 1 ? "1 Person" : count + " Personen";
    }

    static String tournamentLabel(ClubEvent e) {
        return GermanUi.DAY.format(e.startDate().atZone(CLUB_ZONE)) + " – " + e.title();
    }

    private static String capitalized(String text) {
        return text.isEmpty() ? text : text.substring(0, 1).toUpperCase(AUSTRIA) + text.substring(1);
    }

    private static java.util.Optional<Integer> number(String text) {
        try {
            return java.util.Optional.of(Integer.parseInt(text.trim()));
        } catch (NumberFormatException e) {
            return java.util.Optional.empty();
        }
    }
}
