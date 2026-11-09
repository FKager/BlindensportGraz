package it.a11y.blindensport.webui.ui;

import com.vaadin.flow.component.grid.Grid;
import com.vaadin.flow.component.grid.GridVariant;
import com.vaadin.flow.component.html.Anchor;
import com.vaadin.flow.component.html.H2;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.orderedlayout.FlexComponent;
import com.vaadin.flow.component.orderedlayout.HorizontalLayout;
import com.vaadin.flow.component.orderedlayout.VerticalLayout;
import com.vaadin.flow.component.select.Select;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.server.streams.DownloadHandler;
import com.vaadin.flow.server.streams.DownloadResponse;
import it.a11y.blindensport.webui.auth.AdminSession;
import it.a11y.blindensport.webui.auth.AdminSessions;
import it.a11y.blindensport.webui.auth.Permission;
import it.a11y.blindensport.webui.club.ClubStore;
import it.a11y.blindensport.webui.members.MemberStore;
import it.a11y.blindensport.webui.reports.ReportService;
import it.a11y.blindensport.webui.reports.Trainingsfrequenzliste;
import it.a11y.blindensport.webui.reports.Trainingsfrequenzliste.Person;
import jakarta.inject.Inject;

import java.io.ByteArrayInputStream;
import java.time.LocalDate;
import java.util.List;
import java.util.stream.IntStream;

import static it.a11y.blindensport.webui.members.Dates.CLUB_ZONE;

/**
 * Sport Austria's Trainingsfrequenzliste: one training sport's attendance
 * per half year, as in the app (Trainings → Berichte). The roster is every
 * member of the teams assigned to that sport's trainings; "j"/"n" per
 * training day. Admins only (club.manage, like the app); reads no private
 * data. The file is made when downloaded, from the current data.
 */
@Route(value = "trainingsfrequenzliste", layout = MainLayout.class)
@PageTitle("Trainingsfrequenzliste – Blindensport Graz")
@RequiresPermission(Permission.CLUB_MANAGE)
public class TrainingsfrequenzlisteView extends AdminView {
    private final Select<String> sport = new Select<>();
    private final Select<Integer> half = new Select<>();
    private final Select<Integer> year = new Select<>();
    private final VerticalLayout result = new VerticalLayout();
    private boolean loading;

    /** What the download link makes; replaced as the choices change. */
    private volatile Request request;

    private record Request(String sport, int half, int year) {
    }

    @Inject
    public TrainingsfrequenzlisteView(AdminSessions sessions) {
        super(sessions, "Trainingsfrequenzliste");
        add(new Paragraph("Anwesenheit einer Sportart pro Halbjahr auf dem Formular von Sport Austria, wie in der App "
                + "unter Trainings → „Berichte“: alle Mitglieder der zugeordneten Teams, ein Trainingstag je Spalte, "
                + "„j“ oder „n“ je Zelle."));

        LocalDate today = LocalDate.now(CLUB_ZONE);
        sport.setLabel("Sportart");
        sport.setEmptySelectionAllowed(false);
        half.setLabel("Zeitraum");
        half.setItems(1, 2);
        half.setItemLabelGenerator(Trainingsfrequenzliste::halfLabel);
        half.setValue(today.getMonthValue() <= 6 ? 1 : 2);
        year.setLabel("Jahr");
        year.setItems(IntStream.rangeClosed(2020, today.getYear() + 1).boxed().sorted((a, b) -> b - a).toList());
        year.setItemLabelGenerator(String::valueOf);
        year.setValue(today.getYear());
        sport.addValueChangeListener(e -> reload());
        half.addValueChangeListener(e -> reload());
        year.addValueChangeListener(e -> reload());

        HorizontalLayout fields = new HorizontalLayout(sport, half, year);
        fields.setDefaultVerticalComponentAlignment(FlexComponent.Alignment.BASELINE);
        fields.setWrap(true);
        result.setPadding(false);
        add(fields, result);
    }

    @Override
    protected void refresh() {
        loading = true;
        try {
            String keep = sport.getValue();
            List<String> sports = service(session()).trainingSports();
            sport.setItems(sports);
            sport.setValue(sports.contains(keep) ? keep : sports.isEmpty() ? null : sports.get(0));
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

    private void calculate() {
        result.removeAll();
        request = null;
        if (sport.getValue() == null) {
            result.add(new Paragraph("Noch kein Training angelegt."));
            return;
        }
        Trainingsfrequenzliste list = service(session())
                .trainingsfrequenzliste(sport.getValue(), half.getValue(), year.getValue());
        result.add(new H2(list.title() + ", " + Trainingsfrequenzliste.halfLabel(list.half()) + " " + list.year()));
        if (list.dates().isEmpty()) {
            result.add(new Paragraph("Keine Trainings in diesem Zeitraum für diese Sportart."));
            return;
        }
        result.add(new Paragraph(days(list.dates().size()) + " · " + people(list.people().size())
                + (list.teams().isEmpty() ? "" : " · Teams: " + String.join(", ", list.teams()))
                + (list.location() == null ? "" : " · Sportstätte: " + list.location())));
        if (list.missingDates() > 0) {
            result.add(new Paragraph("Achtung: Das Formular hat nur " + Trainingsfrequenzliste.MAX_DATES
                    + " Spalten. " + days(list.missingDates()) + " am Ende fehlen und bitte von Hand nachtragen."));
        }
        if (list.missingPeople() > 0) {
            result.add(new Paragraph("Achtung: Das Formular hat nur " + Trainingsfrequenzliste.MAX_PEOPLE
                    + " Zeilen. " + people(list.missingPeople()) + " fehlen und bitte von Hand nachtragen."));
        }

        request = new Request(list.sport(), list.half(), list.year());
        result.add(download("Trainingsfrequenzliste herunterladen"));

        Grid<Person> grid = new Grid<>();
        grid.addColumn(Person::displayName).setHeader("Name").setRowHeader(true).setFlexGrow(1);
        grid.addColumn(p -> p.roleSuffix() == null ? "Sportler:in" : p.roleSuffix()).setHeader("Funktion")
                .setAutoWidth(true);
        grid.addColumn(p -> p.attended().size() + " von " + list.dates().size()).setHeader("Anwesend")
                .setAutoWidth(true);
        grid.setItems(list.people());
        grid.setAllRowsVisible(true);
        grid.addThemeVariants(GridVariant.LUMO_ROW_STRIPES);
        grid.getElement().setAttribute("aria-label", "Anwesenheit " + list.title());
        result.add(grid);
    }

    private Anchor download(String text) {
        Anchor anchor = new Anchor(DownloadHandler.fromInputStream(event -> {
            AdminSession admin = UiSession.current(sessions).orElse(null);
            Request current = request;
            if (admin == null || current == null || !admin.can(Permission.CLUB_MANAGE)) {
                return DownloadResponse.error(403);
            }
            Trainingsfrequenzliste list = service(admin)
                    .trainingsfrequenzliste(current.sport(), current.half(), current.year());
            byte[] file = list.xlsx();
            return new DownloadResponse(new ByteArrayInputStream(file), list.label() + "_Trainingsfrequenzliste.xlsx",
                    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", file.length);
        }), text);
        anchor.getElement().setAttribute("download", true);
        return anchor;
    }

    private static ReportService service(AdminSession admin) {
        return new ReportService(new ClubStore(admin.db(), admin.userId()), new MemberStore(admin.db()));
    }

    private static String days(int count) {
        return count == 1 ? "1 Trainingstag" : count + " Trainingstage";
    }

    private static String people(int count) {
        return count == 1 ? "1 Person" : count + " Personen";
    }
}
