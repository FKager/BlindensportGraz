package it.a11y.blindensport.webadmin.ui;

import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.button.ButtonVariant;
import com.vaadin.flow.component.checkbox.Checkbox;
import com.vaadin.flow.component.grid.Grid;
import com.vaadin.flow.component.grid.GridVariant;
import com.vaadin.flow.component.orderedlayout.FlexComponent;
import com.vaadin.flow.component.orderedlayout.HorizontalLayout;
import com.vaadin.flow.component.select.Select;
import com.vaadin.flow.component.textfield.TextField;
import com.vaadin.flow.data.value.ValueChangeMode;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import it.a11y.blindensport.webadmin.auth.AdminSession;
import it.a11y.blindensport.webadmin.auth.AdminSessions;
import it.a11y.blindensport.webadmin.auth.Permission;
import it.a11y.blindensport.webadmin.club.ClubModels;
import it.a11y.blindensport.webadmin.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webadmin.club.ClubModels.Membership;
import it.a11y.blindensport.webadmin.club.ClubModels.Team;
import it.a11y.blindensport.webadmin.club.ClubStore;
import it.a11y.blindensport.webadmin.members.MemberRecord;
import it.a11y.blindensport.webadmin.members.MemberStore;
import jakarta.inject.Inject;

import java.time.Instant;
import java.time.LocalDate;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;
import java.util.stream.Stream;

import static it.a11y.blindensport.webadmin.members.Dates.CLUB_ZONE;

/** Trainings, tournaments and other events in one list, filterable by type; attendance per entry. */
@Route(value = "termine", layout = MainLayout.class)
@PageTitle("Termine – Blindensport Graz")
@RequiresPermission(Permission.EVENTS_MANAGE)
public class EventsView extends AdminView {
    static final String ALL = "Alle";

    private final Grid<ClubEvent> grid = new Grid<>();
    private final Select<String> kind = new Select<>();
    private final Checkbox upcoming = new Checkbox("Nur kommende", true);
    private final TextField search = new TextField("Suchen");
    private List<ClubEvent> events = List.of();
    private List<Team> teams = List.of();
    private Map<String, Team> teamsById = Map.of();
    private List<Membership> memberships = List.of();
    private Map<String, MemberRecord> members = Map.of();
    private Map<String, String> accountNames = Map.of();

    @Inject
    public EventsView(AdminSessions sessions) {
        super(sessions, "Termine");
        setSizeFull();
        kind.setLabel("Art");
        kind.setItems(ALL, "training", "tournament", "event");
        kind.setItemLabelGenerator(EventsView::kindPlural);
        kind.setValue(ALL);
        kind.addValueChangeListener(e -> applyFilter());
        upcoming.addValueChangeListener(e -> applyFilter());
        search.setPlaceholder("Titel oder Ort");
        search.setClearButtonVisible(true);
        search.setValueChangeMode(ValueChangeMode.LAZY);
        search.addValueChangeListener(e -> applyFilter());

        Button newTraining = new Button("Neues Training", e -> openEvent("training", null));
        Button newTournament = new Button("Neues Turnier", e -> openEvent("tournament", null));
        Button newEvent = new Button("Neues Event", e -> openEvent("event", null));
        newTraining.addThemeVariants(ButtonVariant.LUMO_PRIMARY);
        HorizontalLayout toolbar = new HorizontalLayout(kind, search, upcoming, newTraining, newTournament, newEvent);
        toolbar.setDefaultVerticalComponentAlignment(FlexComponent.Alignment.BASELINE);
        toolbar.setWrap(true);

        grid.addColumn(this::when).setHeader("Datum").setAutoWidth(true).setSortable(true)
                .setComparator(Comparator.comparing(ClubEvent::startDate));
        grid.addColumn(e -> ClubModels.KINDS.getOrDefault(e.kind(), e.kind())).setHeader("Art").setAutoWidth(true);
        grid.addColumn(ClubEvent::title).setHeader("Titel").setRowHeader(true).setFlexGrow(1);
        grid.addColumn(e -> Stream.of(e.location(), e.city()).filter(s -> !s.isBlank()).collect(Collectors.joining(", ")))
                .setHeader("Ort").setFlexGrow(1);
        grid.addColumn(e -> ClubFields.teamNames(e.teamIds(), teamsById)).setHeader("Teams").setAutoWidth(true);
        grid.addColumn(EventsView::statusLabel).setHeader("Status").setAutoWidth(true);
        grid.addComponentColumn(this::actions).setHeader("Aktionen").setAutoWidth(true).setFlexGrow(0)
                .setFrozenToEnd(true);
        grid.addThemeVariants(GridVariant.LUMO_ROW_STRIPES);
        grid.setEmptyStateText("Keine Termine gefunden.");
        grid.getElement().setAttribute("aria-label", "Termine");
        grid.setSizeFull();
        add(toolbar, grid);
        setFlexGrow(1, grid);
    }

    @Override
    protected void refresh() {
        AdminSession admin = session();
        ClubStore store = store();
        teams = store.teams();
        teamsById = teams.stream().collect(Collectors.toMap(Team::id, Function.identity()));
        memberships = store.memberships();
        accountNames = store.accountNames();
        members = new MemberStore(admin.db()).all(false).stream()
                .collect(Collectors.toMap(m -> m.id().toLowerCase(Locale.ROOT), Function.identity(), (a, b) -> a));
        events = store.events();
        applyFilter();
    }

    private ClubStore store() {
        AdminSession admin = session();
        return new ClubStore(admin.db(), admin.userId());
    }

    private void applyFilter() {
        String q = search.getValue().trim().toLowerCase(Locale.ROOT);
        Instant startOfToday = LocalDate.now(CLUB_ZONE).atStartOfDay(CLUB_ZONE).toInstant();
        List<ClubEvent> shown = events.stream()
                .filter(e -> ALL.equals(kind.getValue()) || e.kind().equals(kind.getValue()))
                .filter(e -> !upcoming.getValue() || !e.endDate().isBefore(startOfToday))
                .filter(e -> q.isEmpty() || Stream.of(e.title(), e.location(), e.city())
                        .anyMatch(s -> s.toLowerCase(Locale.ROOT).contains(q)))
                .sorted(upcoming.getValue() ? Comparator.comparing(ClubEvent::startDate)
                        : Comparator.comparing(ClubEvent::startDate).reversed())
                .toList();
        grid.setItems(shown);
    }

    private HorizontalLayout actions(ClubEvent e) {
        Button edit = GermanUi.label(new Button("Bearbeiten", c -> openEvent(e.kind(), e)), e.title() + " bearbeiten");
        Button delete = GermanUi.label(new Button("Löschen", c -> confirmDelete(e)), e.title() + " löschen");
        delete.addThemeVariants(ButtonVariant.LUMO_ERROR, ButtonVariant.LUMO_SMALL);
        edit.addThemeVariants(ButtonVariant.LUMO_SMALL);
        HorizontalLayout row = new HorizontalLayout(edit);
        if (!"event".equals(e.kind())) {
            Button attendance = GermanUi.label(new Button("Anwesenheit", c -> new AttendanceDialog(e, memberships,
                    this::personName, this::store, this).open()), "Anwesenheit für " + e.title());
            attendance.addThemeVariants(ButtonVariant.LUMO_SMALL);
            row.add(attendance);
        }
        row.add(delete);
        return row;
    }

    private void openEvent(String eventKind, ClubEvent existing) {
        EventDialog[] dialog = new EventDialog[1];
        dialog[0] = new EventDialog(eventKind, existing, teams, store().createdBy(), event -> {
            if (attempt("Speichern", () -> store().saveEvent(event))) {
                dialog[0].close();
                Announcer.success(event.title().trim() + " gespeichert.");
                attempt("Laden", this::refresh);
            }
        });
        dialog[0].open();
    }

    private void confirmDelete(ClubEvent e) {
        GermanUi.confirm(e.title() + " löschen?",
                "Anwesenheiten, Anmeldungen und Bilder dieses Termins werden mitgelöscht. Das kann nicht rückgängig "
                        + "gemacht werden.",
                "Löschen", () -> {
                    if (attempt("Löschen", () -> store().deleteEvent(e.id()))) {
                        Announcer.success(e.title() + " gelöscht.");
                        attempt("Laden", this::refresh);
                    }
                });
    }

    String personName(Membership m) {
        if (m.userId() != null && accountNames.containsKey(m.userId())) {
            return accountNames.get(m.userId());
        }
        MemberRecord member = m.memberId() == null ? null : members.get(m.memberId());
        return member != null ? member.fullName() : "?";
    }

    private String when(ClubEvent e) {
        var start = e.startDate().atZone(CLUB_ZONE);
        var end = e.endDate().atZone(CLUB_ZONE);
        if ("tournament".equals(e.kind())) {
            return start.toLocalDate().equals(end.toLocalDate()) ? GermanUi.DAY.format(start)
                    : GermanUi.DAY.format(start) + " – " + GermanUi.DAY.format(end);
        }
        return GermanUi.DAY_TIME.format(start) + "–" + String.format("%02d:%02d", end.getHour(), end.getMinute());
    }

    static String statusLabel(ClubEvent e) {
        if ("tournament".equals(e.kind())) {
            return ClubModels.TOURNAMENT_STATUS.getOrDefault(e.status(), e.status());
        }
        if ("training".equals(e.kind())) {
            return ClubModels.TRAINING_STATUS.getOrDefault(e.status(), e.status());
        }
        return "";
    }

    static String kindPlural(String kind) {
        return switch (kind) {
            case "training" -> "Trainings";
            case "tournament" -> "Turniere";
            case "event" -> "Events";
            default -> "Alle";
        };
    }
}
