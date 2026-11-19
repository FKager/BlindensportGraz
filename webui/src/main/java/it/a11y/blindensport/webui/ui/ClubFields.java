package it.a11y.blindensport.webui.ui;

import com.vaadin.flow.component.combobox.ComboBox;
import com.vaadin.flow.component.combobox.MultiSelectComboBox;
import it.a11y.blindensport.webui.club.ClubModels;
import it.a11y.blindensport.webui.club.ClubStore;
import it.a11y.blindensport.webui.club.ClubModels.Team;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;

/** Form fields shared by the club-data dialogs. */
final class ClubFields {
    private ClubFields() {
    }

    /**
     * Sport from the club's list ({@link ClubStore#sportNames()}). A stored
     * value that's no longer offered (deactivated, or free text from older
     * builds) stays selectable, so editing never changes it unasked.
     */
    static ComboBox<String> sport(String value, List<String> options) {
        ComboBox<String> sport = new ComboBox<>("Sportart");
        sport.setItems(withCurrent(options, value));
        sport.setClearButtonVisible(true);
        sport.setHelperText("Neue Sportarten: Seite „Sportarten und Veranstaltungsarten“");
        sport.setValue(value == null || value.isBlank() ? null : value);
        return sport;
    }

    /** Event type from the club's list for one behaviour; same rule for stored values. */
    static ComboBox<String> eventType(String value, List<String> options) {
        ComboBox<String> type = new ComboBox<>("Art der Veranstaltung");
        type.setItems(withCurrent(options, value));
        type.setHelperText("Neue Arten: Seite „Sportarten und Veranstaltungsarten“");
        type.setValue(value == null || value.isBlank() ? null : value);
        return type;
    }

    static List<String> withCurrent(List<String> options, String value) {
        List<String> items = new ArrayList<>(options);
        if (value != null && !value.isBlank() && !items.contains(value)) {
            items.add(value);
        }
        return items;
    }

    static String sportValue(ComboBox<String> sport) {
        return sport.getValue() == null ? "" : sport.getValue().trim();
    }

    /** Teams an entry is for; empty = visible to everyone. */
    static MultiSelectComboBox<Team> teams(List<Team> all, List<String> selectedIds) {
        MultiSelectComboBox<Team> teams = new MultiSelectComboBox<>("Teams");
        teams.setItems(all);
        teams.setItemLabelGenerator(t -> t.sport().isBlank() ? t.name() : t.name() + " (" + t.sport() + ")");
        Map<String, Team> byId = all.stream().collect(Collectors.toMap(Team::id, Function.identity()));
        Set<Team> selected = new LinkedHashSet<>();
        selectedIds.forEach(id -> {
            if (byId.containsKey(id)) {
                selected.add(byId.get(id));
            }
        });
        teams.setValue(selected);
        teams.setHelperText("Leer lassen = für alle sichtbar");
        return teams;
    }

    static List<String> teamIds(MultiSelectComboBox<Team> teams) {
        return teams.getValue().stream().map(Team::id).toList();
    }

    static String teamNames(List<String> ids, Map<String, Team> byId) {
        if (ids.isEmpty()) {
            return "Alle";
        }
        return ids.stream().map(id -> byId.containsKey(id) ? byId.get(id).name() : "(gelöscht)")
                .collect(Collectors.joining(", "));
    }
}
