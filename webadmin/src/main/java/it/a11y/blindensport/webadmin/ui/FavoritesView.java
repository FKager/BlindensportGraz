package it.a11y.blindensport.webadmin.ui;

import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.button.ButtonVariant;
import com.vaadin.flow.component.combobox.ComboBox;
import com.vaadin.flow.component.combobox.MultiSelectComboBox;
import com.vaadin.flow.component.dialog.Dialog;
import com.vaadin.flow.component.formlayout.FormLayout;
import com.vaadin.flow.component.grid.Grid;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.orderedlayout.HorizontalLayout;
import com.vaadin.flow.component.select.Select;
import com.vaadin.flow.component.textfield.TextField;
import com.vaadin.flow.component.timepicker.TimePicker;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import it.a11y.blindensport.webadmin.auth.AdminSession;
import it.a11y.blindensport.webadmin.auth.AdminSessions;
import it.a11y.blindensport.webadmin.auth.Permission;
import it.a11y.blindensport.webadmin.club.ClubModels.Team;
import it.a11y.blindensport.webadmin.club.ClubModels.TrainingFavorite;
import it.a11y.blindensport.webadmin.club.ClubStore;
import jakarta.inject.Inject;

import java.time.Duration;
import java.time.LocalTime;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

/** Saved recurring trainings ("Favoriten") the app offers when creating a training. */
@Route(value = "favoriten", layout = MainLayout.class)
@PageTitle("Trainings-Favoriten – Blindensport Graz")
@RequiresPermission(Permission.EVENTS_MANAGE)
public class FavoritesView extends AdminView {
    /** The app stores Calendar weekdays: 1 = Sonntag … 7 = Samstag. */
    static final List<Integer> WEEKDAYS = List.of(2, 3, 4, 5, 6, 7, 1);
    static final Map<Integer, String> WEEKDAY_NAMES = Map.of(1, "Sonntag", 2, "Montag", 3, "Dienstag", 4, "Mittwoch",
            5, "Donnerstag", 6, "Freitag", 7, "Samstag");

    private final Grid<TrainingFavorite> grid = new Grid<>();
    private List<Team> teams = List.of();
    private Map<String, Team> teamsById = Map.of();

    @Inject
    public FavoritesView(AdminSessions sessions) {
        super(sessions, "Trainings-Favoriten");
        setSizeFull();
        Button add = new Button("Neuer Favorit", e -> open(null));
        add.addThemeVariants(ButtonVariant.LUMO_PRIMARY);
        grid.addColumn(TrainingFavorite::title).setHeader("Titel").setRowHeader(true).setFlexGrow(1);
        grid.addColumn(TrainingFavorite::sport).setHeader("Sportart").setAutoWidth(true);
        grid.addColumn(f -> WEEKDAY_NAMES.getOrDefault(f.weekday(), "?") + ", "
                + time(f.startHour(), f.startMinute()) + "–" + time(f.endHour(), f.endMinute()))
                .setHeader("Wann").setAutoWidth(true);
        grid.addColumn(TrainingFavorite::location).setHeader("Ort").setFlexGrow(1);
        grid.addColumn(f -> ClubFields.teamNames(f.teamIds(), teamsById)).setHeader("Teams").setAutoWidth(true);
        grid.addComponentColumn(f -> {
            Button edit = GermanUi.label(new Button("Bearbeiten", e -> open(f)), f.title() + " bearbeiten");
            Button delete = GermanUi.label(new Button("Löschen", e -> GermanUi.confirm(f.title() + " löschen?",
                    "Der Favorit wird entfernt; bereits angelegte Trainings bleiben.", "Löschen", () -> {
                        if (attempt("Löschen", () -> store().deleteFavorite(f.id()))) {
                            Announcer.success(f.title() + " gelöscht.");
                            attempt("Laden", this::refresh);
                        }
                    })), f.title() + " löschen");
            edit.addThemeVariants(ButtonVariant.LUMO_SMALL);
            delete.addThemeVariants(ButtonVariant.LUMO_SMALL, ButtonVariant.LUMO_ERROR);
            return new HorizontalLayout(edit, delete);
        }).setHeader("Aktionen").setAutoWidth(true).setFlexGrow(0).setFrozenToEnd(true);
        grid.setEmptyStateText("Noch keine Favoriten.");
        grid.getElement().setAttribute("aria-label", "Trainings-Favoriten");
        grid.setSizeFull();
        add(new Paragraph("Vorlagen für wiederkehrende Trainings – in der App unter „Neues Training“ auswählbar."),
                new HorizontalLayout(add), grid);
        setFlexGrow(1, grid);
    }

    @Override
    protected void refresh() {
        ClubStore store = store();
        teams = store.teams();
        teamsById = teams.stream().collect(Collectors.toMap(Team::id, Function.identity()));
        grid.setItems(store.favorites());
    }

    private ClubStore store() {
        AdminSession admin = session();
        return new ClubStore(admin.db(), admin.userId());
    }

    private void open(TrainingFavorite f) {
        Dialog dialog = new Dialog();
        dialog.setHeaderTitle(f == null ? "Neuer Favorit" : f.title() + " bearbeiten");
        dialog.setWidth("min(48rem, 100vw)");
        TextField title = new TextField("Titel");
        title.setRequired(true);
        ComboBox<String> sport = ClubFields.sport(f == null ? "" : f.sport());
        Select<Integer> weekday = new Select<>();
        weekday.setLabel("Wochentag");
        weekday.setItems(WEEKDAYS);
        weekday.setItemLabelGenerator(WEEKDAY_NAMES::get);
        TimePicker start = timePicker("Beginn");
        TimePicker end = timePicker("Ende");
        TextField location = new TextField("Ort / Halle");
        TextField street = new TextField("Straße");
        TextField zip = new TextField("PLZ");
        TextField city = new TextField("Stadt");
        TextField country = new TextField("Land");
        MultiSelectComboBox<Team> teamField = ClubFields.teams(teams, f == null ? List.of() : f.teamIds());
        if (f == null) {
            weekday.setValue(2);
            start.setValue(LocalTime.of(18, 0));
            end.setValue(LocalTime.of(19, 30));
            country.setValue("Österreich");
        } else {
            title.setValue(f.title());
            weekday.setValue(WEEKDAY_NAMES.containsKey(f.weekday()) ? f.weekday() : 2);
            start.setValue(LocalTime.of(f.startHour(), f.startMinute()));
            end.setValue(LocalTime.of(f.endHour(), f.endMinute()));
            location.setValue(f.location());
            street.setValue(f.street());
            zip.setValue(f.zip());
            city.setValue(f.city());
            country.setValue(f.country());
        }
        FormLayout form = new FormLayout(title, sport, weekday, start, end, teamField, location, street, zip, city, country);
        form.setColspan(teamField, 2);
        dialog.add(form);
        Button save = new Button("Speichern", e -> {
            if (title.getValue().isBlank() || start.getValue() == null || end.getValue() == null) {
                Announcer.error("Bitte Titel, Beginn und Ende angeben.");
                title.focus();
                return;
            }
            if (!end.getValue().isAfter(start.getValue())) {
                Announcer.error("Das Ende muss nach dem Beginn liegen.");
                end.focus();
                return;
            }
            TrainingFavorite saved = new TrainingFavorite(f == null ? ClubStore.newId() : f.id(), title.getValue(),
                    ClubFields.sportValue(sport), weekday.getValue(), start.getValue().getHour(),
                    start.getValue().getMinute(), end.getValue().getHour(), end.getValue().getMinute(),
                    location.getValue(), street.getValue(), zip.getValue(), city.getValue(), country.getValue(),
                    ClubFields.teamIds(teamField));
            if (attempt("Speichern", () -> store().saveFavorite(saved))) {
                dialog.close();
                Announcer.success(saved.title().trim() + " gespeichert.");
                attempt("Laden", this::refresh);
            }
        });
        save.addThemeVariants(ButtonVariant.LUMO_PRIMARY);
        dialog.getFooter().add(new Button("Abbrechen", e -> dialog.close()), save);
        dialog.addOpenedChangeListener(e -> title.focus());
        dialog.open();
    }

    private static TimePicker timePicker(String label) {
        TimePicker picker = new TimePicker(label);
        picker.setLocale(GermanUi.LOCALE);
        picker.setStep(Duration.ofMinutes(15));
        return picker;
    }

    private static String time(int hour, int minute) {
        return String.format("%02d:%02d", hour, minute);
    }
}
