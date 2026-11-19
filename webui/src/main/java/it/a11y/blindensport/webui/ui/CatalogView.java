package it.a11y.blindensport.webui.ui;

import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.button.ButtonVariant;
import com.vaadin.flow.component.dialog.Dialog;
import com.vaadin.flow.component.formlayout.FormLayout;
import com.vaadin.flow.component.grid.Grid;
import com.vaadin.flow.component.html.H2;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.orderedlayout.HorizontalLayout;
import com.vaadin.flow.component.select.Select;
import com.vaadin.flow.component.textfield.TextField;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import it.a11y.blindensport.webui.auth.AdminSession;
import it.a11y.blindensport.webui.auth.AdminSessions;
import it.a11y.blindensport.webui.auth.Permission;
import it.a11y.blindensport.webui.club.ClubModels;
import it.a11y.blindensport.webui.club.ClubModels.EventType;
import it.a11y.blindensport.webui.club.ClubModels.Sport;
import it.a11y.blindensport.webui.club.ClubStore;
import jakarta.inject.Inject;

import java.util.ArrayList;
import java.util.List;
import java.util.function.Consumer;

/**
 * The club's sport list and event-type list (club.manage), tables sports and
 * event_types. Same rules as the app's Verein screen: entries are
 * deactivated, not deleted; renaming changes every team, event and
 * favourite with the old name; an event type's behaviour is chosen once.
 * Order changes with "Nach oben" / "Nach unten" (no drag and drop, so it
 * works with a keyboard and a screen reader).
 */
@Route(value = "sportarten", layout = MainLayout.class)
@PageTitle("Sportarten und Veranstaltungsarten – Blindensport Graz")
@RequiresPermission(Permission.CLUB_MANAGE)
public class CatalogView extends AdminView {
    private final Grid<Sport> sports = new Grid<>();
    private final Grid<EventType> types = new Grid<>();
    private List<Sport> sportRows = List.of();
    private List<EventType> typeRows = List.of();

    @Inject
    public CatalogView(AdminSessions sessions) {
        super(sessions, "Sportarten und Veranstaltungsarten");

        sports.addColumn(Sport::name).setHeader("Sportart").setRowHeader(true).setFlexGrow(1);
        sports.addColumn(s -> s.active() ? "Ja" : "Nein (deaktiviert)").setHeader("Zur Auswahl").setAutoWidth(true);
        sports.addComponentColumn(s -> actions("sports", s.id(), s.name(), s.active(),
                sportRows.stream().map(Sport::id).toList(),
                name -> store().renameSport(s.id(), name))).setHeader("Aktionen").setAutoWidth(true).setFlexGrow(0);
        sports.setAllRowsVisible(true);
        sports.getElement().setAttribute("aria-label", "Sportarten");
        sports.setEmptyStateText("Noch keine Sportarten.");

        types.addColumn(EventType::name).setHeader("Veranstaltungsart").setRowHeader(true).setFlexGrow(1);
        types.addColumn(t -> ClubModels.BEHAVIORS.getOrDefault(t.behavior(), t.behavior())).setHeader("Verhalten")
                .setAutoWidth(true);
        types.addColumn(t -> t.active() ? "Ja" : "Nein (deaktiviert)").setHeader("Zur Auswahl").setAutoWidth(true);
        types.addComponentColumn(t -> actions("event_types", t.id(), t.name(), t.active(),
                typeRows.stream().map(EventType::id).toList(),
                name -> store().renameEventType(t.id(), name))).setHeader("Aktionen").setAutoWidth(true).setFlexGrow(0);
        types.setAllRowsVisible(true);
        types.getElement().setAttribute("aria-label", "Veranstaltungsarten");
        types.setEmptyStateText("Noch keine Veranstaltungsarten.");

        Button addSport = new Button("Neue Sportart", e -> openAdd(false));
        addSport.addThemeVariants(ButtonVariant.LUMO_PRIMARY);
        Button addType = new Button("Neue Veranstaltungsart", e -> openAdd(true));
        addType.addThemeVariants(ButtonVariant.LUMO_PRIMARY);

        add(new Paragraph("Diese Listen werden in der App und hier in allen Auswahlfeldern angeboten. Deaktivierte "
                        + "Einträge bleiben bei bestehenden Teams und Terminen erhalten, werden aber nicht mehr angeboten. "
                        + "Umbenennen ändert alle Einträge mit dem alten Namen."),
                new H2("Sportarten"), new HorizontalLayout(addSport), sports,
                new H2("Veranstaltungsarten"),
                new Paragraph("Das Verhalten legt fest, ob Termine dieser Art wie ein Training, wie ein Turnier oder "
                        + "wie eine Veranstaltung funktionieren. Es wird beim Anlegen gewählt und lässt sich danach "
                        + "nicht mehr ändern."),
                new HorizontalLayout(addType), types);
    }

    @Override
    protected void refresh() {
        ClubStore store = store();
        sportRows = store.sports();
        typeRows = store.eventTypes();
        sports.setItems(sportRows);
        types.setItems(typeRows);
    }

    private ClubStore store() {
        AdminSession admin = session();
        return new ClubStore(admin.db(), admin.userId());
    }

    private HorizontalLayout actions(String table, String id, String name, boolean active, List<String> order,
                                     Consumer<String> rename) {
        Button renameButton = GermanUi.label(new Button("Umbenennen", e -> openRename(name, rename)),
                name + " umbenennen");
        Button toggle = GermanUi.label(new Button(active ? "Deaktivieren" : "Aktivieren", e -> {
            if (attempt(active ? "Deaktivieren" : "Aktivieren", () -> store().setActive(table, id, !active))) {
                Announcer.success(name + (active ? " deaktiviert." : " aktiviert."));
                attempt("Laden", this::refresh);
            }
        }), name + (active ? " deaktivieren" : " aktivieren"));
        int index = order.indexOf(id);
        Button up = GermanUi.label(new Button("Nach oben", e -> move(table, order, index, -1, name)),
                name + " nach oben");
        Button down = GermanUi.label(new Button("Nach unten", e -> move(table, order, index, 1, name)),
                name + " nach unten");
        up.setEnabled(index > 0);
        down.setEnabled(index >= 0 && index < order.size() - 1);
        for (Button b : List.of(renameButton, toggle, up, down)) {
            b.addThemeVariants(ButtonVariant.LUMO_SMALL);
        }
        return new HorizontalLayout(renameButton, toggle, up, down);
    }

    private void move(String table, List<String> order, int index, int delta, String name) {
        List<String> ids = new ArrayList<>(order);
        int target = index + delta;
        if (index < 0 || target < 0 || target >= ids.size()) {
            return;
        }
        ids.add(target, ids.remove(index));
        if (attempt("Verschieben", () -> store().reorder(table, ids))) {
            Announcer.success(name + " ist jetzt an Position " + (target + 1) + " von " + ids.size() + ".");
            attempt("Laden", this::refresh);
        }
    }

    private void openRename(String current, Consumer<String> rename) {
        Dialog dialog = new Dialog();
        dialog.setHeaderTitle(current + " umbenennen");
        TextField name = new TextField("Neuer Name");
        name.setValue(current);
        name.setRequired(true);
        dialog.add(new FormLayout(name),
                new Paragraph("Alle Teams, Termine und Favoriten mit „" + current + "“ bekommen den neuen Namen."));
        Button save = new Button("Umbenennen", e -> {
            String cleaned = ClubStore.cleanName(name.getValue());
            if (cleaned.isEmpty()) {
                Announcer.error("Bitte einen Namen eingeben.");
                name.focus();
                return;
            }
            if (cleaned.equals(current)) {
                dialog.close();
                return;
            }
            if (attempt("Umbenennen", () -> rename.accept(cleaned))) {
                dialog.close();
                Announcer.success(current + " heißt jetzt " + cleaned + ".");
                attempt("Laden", this::refresh);
            }
        });
        save.addThemeVariants(ButtonVariant.LUMO_PRIMARY);
        dialog.getFooter().add(new Button("Abbrechen", e -> dialog.close()), save);
        dialog.addOpenedChangeListener(e -> name.focus());
        dialog.open();
    }

    private void openAdd(boolean eventType) {
        Dialog dialog = new Dialog();
        dialog.setHeaderTitle(eventType ? "Neue Veranstaltungsart" : "Neue Sportart");
        TextField name = new TextField("Name");
        name.setRequired(true);
        Select<String> behavior = new Select<>();
        behavior.setLabel("Verhalten");
        behavior.setItems("training", "tournament", "event");
        behavior.setItemLabelGenerator(b -> ClubModels.BEHAVIORS.getOrDefault(b, b));
        behavior.setValue("event");
        FormLayout form = eventType ? new FormLayout(name, behavior) : new FormLayout(name);
        dialog.add(form);
        Button save = new Button("Hinzufügen", e -> {
            String cleaned = ClubStore.cleanName(name.getValue());
            if (cleaned.isEmpty()) {
                Announcer.error("Bitte einen Namen eingeben.");
                name.focus();
                return;
            }
            int next = nextSortOrder(eventType ? typeRows.stream().map(EventType::sortOrder).toList()
                    : sportRows.stream().map(Sport::sortOrder).toList());
            if (attempt("Hinzufügen", () -> {
                if (eventType) {
                    store().addEventType(cleaned, behavior.getValue(), next);
                } else {
                    store().addSport(cleaned, next);
                }
            })) {
                dialog.close();
                Announcer.success(cleaned + " hinzugefügt.");
                attempt("Laden", this::refresh);
            }
        });
        save.addThemeVariants(ButtonVariant.LUMO_PRIMARY);
        dialog.getFooter().add(new Button("Abbrechen", e -> dialog.close()), save);
        dialog.addOpenedChangeListener(e -> name.focus());
        dialog.open();
    }

    /** Next free sort_order after the given ones (10, 20, …), like the app. */
    static int nextSortOrder(List<Integer> orders) {
        int max = orders.stream().mapToInt(Integer::intValue).max().orElse(0);
        return (max / 10 + 1) * 10;
    }
}
