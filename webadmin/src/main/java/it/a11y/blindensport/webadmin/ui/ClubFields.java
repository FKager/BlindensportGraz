package it.a11y.blindensport.webadmin.ui;

import com.vaadin.flow.component.combobox.ComboBox;
import com.vaadin.flow.component.combobox.MultiSelectComboBox;
import it.a11y.blindensport.webadmin.club.ClubModels;
import it.a11y.blindensport.webadmin.club.ClubModels.Team;

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

    /** Sport: the known sports, but free text stays possible (like the app). */
    static ComboBox<String> sport(String value) {
        ComboBox<String> sport = new ComboBox<>("Sportart");
        List<String> items = new ArrayList<>(ClubModels.SPORTS);
        if (value != null && !value.isBlank() && !items.contains(value)) {
            items.add(value);
        }
        sport.setItems(items);
        sport.setAllowCustomValue(true);
        sport.addCustomValueSetListener(e -> {
            List<String> extended = new ArrayList<>(items);
            extended.add(e.getDetail());
            sport.setItems(extended);
            sport.setValue(e.getDetail());
        });
        sport.setHelperText("Auswählen oder eigene Sportart eintippen");
        sport.setValue(value == null || value.isBlank() ? null : value);
        return sport;
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
