package it.a11y.blindensport.webadmin.ui;

import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.button.ButtonVariant;
import com.vaadin.flow.component.combobox.ComboBox;
import com.vaadin.flow.component.dialog.Dialog;
import com.vaadin.flow.component.formlayout.FormLayout;
import com.vaadin.flow.component.grid.Grid;
import com.vaadin.flow.component.html.H3;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.orderedlayout.FlexComponent;
import com.vaadin.flow.component.orderedlayout.HorizontalLayout;
import com.vaadin.flow.component.select.Select;
import com.vaadin.flow.component.textfield.TextArea;
import com.vaadin.flow.component.textfield.TextField;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import it.a11y.blindensport.webadmin.auth.AdminSession;
import it.a11y.blindensport.webadmin.auth.AdminSessions;
import it.a11y.blindensport.webadmin.auth.Permission;
import it.a11y.blindensport.webadmin.club.ClubModels;
import it.a11y.blindensport.webadmin.club.ClubModels.Membership;
import it.a11y.blindensport.webadmin.club.ClubModels.Team;
import it.a11y.blindensport.webadmin.club.ClubStore;
import it.a11y.blindensport.webadmin.members.MemberRecord;
import it.a11y.blindensport.webadmin.members.MemberStore;
import jakarta.inject.Inject;

import java.time.Instant;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

/** Teams and who plays / coaches in them. */
@Route(value = "teams", layout = MainLayout.class)
@PageTitle("Teams – Blindensport Graz")
@RequiresPermission(Permission.TEAMS_MANAGE)
public class TeamsView extends AdminView {
    private final Grid<Team> grid = new Grid<>();
    private List<Membership> memberships = List.of();
    private Map<String, MemberRecord> members = Map.of();
    private List<MemberRecord> roster = List.of();
    private Map<String, String> accountNames = Map.of();

    @Inject
    public TeamsView(AdminSessions sessions) {
        super(sessions, "Teams");
        setSizeFull();
        Button add = new Button("Neues Team", e -> openTeam(null));
        add.addThemeVariants(ButtonVariant.LUMO_PRIMARY);

        grid.addColumn(Team::name).setHeader("Name").setRowHeader(true).setAutoWidth(true).setSortable(true);
        grid.addColumn(Team::sport).setHeader("Sportart").setAutoWidth(true);
        grid.addColumn(t -> memberships.stream().filter(m -> m.teamId().equals(t.id())).count())
                .setHeader("Mitglieder").setAutoWidth(true).setFlexGrow(0);
        grid.addColumn(Team::description).setHeader("Beschreibung").setFlexGrow(1);
        grid.addComponentColumn(t -> {
            Button edit = GermanUi.label(new Button("Bearbeiten", e -> openTeam(t)), "Team " + t.name() + " bearbeiten");
            Button people = GermanUi.label(new Button("Mitglieder", e -> openMemberships(t)),
                    "Mitglieder von " + t.name());
            Button delete = GermanUi.label(new Button("Löschen", e -> confirmDelete(t)), "Team " + t.name() + " löschen");
            delete.addThemeVariants(ButtonVariant.LUMO_ERROR);
            for (Button b : List.of(edit, people, delete)) {
                b.addThemeVariants(ButtonVariant.LUMO_SMALL);
            }
            return new HorizontalLayout(edit, people, delete);
        }).setHeader("Aktionen").setAutoWidth(true).setFlexGrow(0).setFrozenToEnd(true);
        grid.setEmptyStateText("Noch keine Teams.");
        grid.getElement().setAttribute("aria-label", "Teams");
        grid.setSizeFull();
        add(new HorizontalLayout(add), grid);
        setFlexGrow(1, grid);
    }

    @Override
    protected void refresh() {
        AdminSession admin = session();
        ClubStore store = store();
        memberships = store.memberships();
        roster = new MemberStore(admin.db()).all(false);
        members = roster.stream().collect(Collectors.toMap(m -> m.id().toLowerCase(Locale.ROOT), Function.identity(),
                (a, b) -> a));
        accountNames = store.accountNames();
        grid.setItems(store.teams());
    }

    private ClubStore store() {
        AdminSession admin = session();
        return new ClubStore(admin.db(), admin.userId());
    }

    String personName(Membership m) {
        if (m.userId() != null && accountNames.containsKey(m.userId())) {
            return accountNames.get(m.userId());
        }
        MemberRecord member = m.memberId() == null ? null : members.get(m.memberId());
        return member != null ? member.fullName() : "?";
    }

    private void openTeam(Team team) {
        Dialog dialog = new Dialog();
        dialog.setHeaderTitle(team == null ? "Neues Team" : "Team " + team.name() + " bearbeiten");
        dialog.setWidth("min(36rem, 100vw)");
        TextField name = new TextField("Name");
        name.setRequired(true);
        ComboBox<String> sport = ClubFields.sport(team == null ? "" : team.sport());
        TextArea description = new TextArea("Beschreibung");
        if (team != null) {
            name.setValue(team.name());
            description.setValue(team.description());
        }
        FormLayout form = new FormLayout(name, sport, description);
        form.setColspan(description, 2);
        dialog.add(form);
        Button save = new Button("Speichern", e -> {
            if (name.getValue().isBlank()) {
                Announcer.error("Bitte einen Namen eingeben.");
                name.focus();
                return;
            }
            Team saved = new Team(team == null ? ClubStore.newId() : team.id(), name.getValue(),
                    ClubFields.sportValue(sport), description.getValue());
            if (attempt("Speichern", () -> store().saveTeam(saved))) {
                dialog.close();
                Announcer.success("Team " + saved.name().trim() + " gespeichert.");
                attempt("Laden", this::refresh);
            }
        });
        save.addThemeVariants(ButtonVariant.LUMO_PRIMARY);
        dialog.getFooter().add(new Button("Abbrechen", e -> dialog.close()), save);
        dialog.addOpenedChangeListener(e -> name.focus());
        dialog.open();
    }

    private void confirmDelete(Team team) {
        GermanUi.confirm("Team " + team.name() + " löschen?",
                "Die Teamzuordnungen und ihre Anwesenheiten werden mitgelöscht. Termine bleiben erhalten, "
                        + "sind danach aber diesem Team nicht mehr zugeordnet.",
                "Löschen", () -> {
                    if (attempt("Löschen", () -> store().deleteTeam(team.id()))) {
                        Announcer.success("Team " + team.name() + " gelöscht.");
                        attempt("Laden", this::refresh);
                    }
                });
    }

    private void openMemberships(Team team) {
        Dialog dialog = new Dialog();
        dialog.setHeaderTitle("Mitglieder von " + team.name());
        dialog.setWidth("min(48rem, 100vw)");
        Grid<Membership> list = new Grid<>();
        list.addColumn(this::personName).setHeader("Name").setRowHeader(true).setAutoWidth(true);
        list.addComponentColumn(m -> {
            Select<String> role = roleSelect(m.role());
            role.setAriaLabel("Rolle von " + personName(m));
            role.addValueChangeListener(e -> {
                if (e.isFromClient() && attempt("Rolle ändern", () -> store().saveMembership(
                        new Membership(m.id(), m.teamId(), m.memberId(), m.userId(), e.getValue(), m.joinedAt())))) {
                    Announcer.success(personName(m) + ": " + ClubModels.MEMBERSHIP_ROLES.getOrDefault(e.getValue(), e.getValue()));
                    attempt("Laden", this::refresh);
                }
            });
            return role;
        }).setHeader("Rolle").setAutoWidth(true);
        list.addComponentColumn(m -> {
            Button remove = GermanUi.label(new Button("Entfernen", e -> {
                if (attempt("Entfernen", () -> store().deleteMembership(m.id()))) {
                    Announcer.success(personName(m) + " aus " + team.name() + " entfernt.");
                    attempt("Laden", this::refresh);
                    fillMemberships(list, team);
                }
            }), personName(m) + " aus dem Team entfernen");
            remove.addThemeVariants(ButtonVariant.LUMO_SMALL, ButtonVariant.LUMO_ERROR);
            return remove;
        }).setHeader("Aktionen").setAutoWidth(true).setFlexGrow(0);
        list.setEmptyStateText("Noch niemand in diesem Team.");
        list.setAllRowsVisible(true);
        list.getElement().setAttribute("aria-label", "Mitglieder von " + team.name());
        fillMemberships(list, team);

        ComboBox<MemberRecord> person = new ComboBox<>("Mitglied hinzufügen");
        person.setItems(roster);
        person.setItemLabelGenerator(m -> m.lastName() + ", " + m.firstName());
        person.setWidth("20rem");
        Select<String> role = roleSelect("player");
        Button add = new Button("Hinzufügen", e -> {
            if (person.getValue() == null) {
                Announcer.error("Bitte zuerst ein Mitglied auswählen.");
                person.focus();
                return;
            }
            String memberId = person.getValue().id().toLowerCase(Locale.ROOT);
            boolean already = memberships.stream().anyMatch(m -> m.teamId().equals(team.id()) && memberId.equals(m.memberId()));
            if (already) {
                Announcer.error(person.getValue().fullName() + " ist schon in diesem Team.");
                return;
            }
            Membership created = new Membership(ClubStore.newId(), team.id(), memberId, null, role.getValue(), Instant.now());
            if (attempt("Hinzufügen", () -> store().saveMembership(created))) {
                Announcer.success(person.getValue().fullName() + " zu " + team.name() + " hinzugefügt.");
                person.clear();
                attempt("Laden", this::refresh);
                fillMemberships(list, team);
                person.focus();
            }
        });
        add.addThemeVariants(ButtonVariant.LUMO_PRIMARY);
        HorizontalLayout addRow = new HorizontalLayout(person, role, add);
        addRow.setDefaultVerticalComponentAlignment(FlexComponent.Alignment.BASELINE);
        addRow.setWrap(true);
        dialog.add(list, new H3("Hinzufügen"), addRow,
                new Paragraph("App-Konten treten Teams in der App selbst bei; hier werden Einträge der Mitgliederliste zugeordnet."));
        dialog.getFooter().add(new Button("Schließen", e -> dialog.close()));
        dialog.open();
    }

    private void fillMemberships(Grid<Membership> list, Team team) {
        list.setItems(memberships.stream().filter(m -> m.teamId().equals(team.id()))
                .sorted(Comparator.comparing(this::personName)).toList());
    }

    private static Select<String> roleSelect(String value) {
        Select<String> role = new Select<>();
        role.setLabel("Rolle");
        role.setItems("player", "coach", "assistant");
        role.setItemLabelGenerator(r -> ClubModels.MEMBERSHIP_ROLES.getOrDefault(r, r));
        role.setValue(ClubModels.MEMBERSHIP_ROLES.containsKey(value) ? value : "player");
        return role;
    }
}
