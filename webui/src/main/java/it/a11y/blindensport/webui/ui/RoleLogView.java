package it.a11y.blindensport.webui.ui;

import com.vaadin.flow.component.html.H2;
import com.vaadin.flow.component.html.ListItem;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.html.UnorderedList;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.router.RouterLink;
import it.a11y.blindensport.webui.accounts.AccountService;
import it.a11y.blindensport.webui.auth.AdminSession;
import it.a11y.blindensport.webui.club.ClubFunctions;
import it.a11y.blindensport.webui.auth.AdminSessions;
import it.a11y.blindensport.webui.auth.Permission;
import jakarta.inject.Inject;

import java.time.Instant;
import java.time.ZoneId;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/** Audit trail: role changes and block/unblock/delete of accounts (rolelog.read), like the app's RoleChangeLogView. */
@Route(value = "protokoll", layout = MainLayout.class)
@PageTitle("Rollen-Protokoll – Blindensport Graz")
@RequiresPermission(Permission.ROLELOG_READ)
public class RoleLogView extends AdminView {
    private static final Map<String, String> ACTIONS = Map.of("block", "gesperrt", "unblock", "entsperrt", "delete", "gelöscht");

    private final UnorderedList roleChanges = new UnorderedList();
    private final UnorderedList adminActions = new UnorderedList();
    private final UnorderedList functionChanges = new UnorderedList();

    @Inject
    public RoleLogView(AdminSessions sessions) {
        super(sessions, "Rollen-Protokoll");
        add(new RouterLink("Zurück zu Rollen", RolesView.class), new H2("Rollenänderungen"), roleChanges,
                new H2("Vereinsfunktionen"), functionChanges, new H2("Gesperrte und gelöschte Konten"), adminActions);
    }

    @Override
    protected void refresh() {
        AdminSession admin = session();
        AccountService service = new AccountService(admin.db());
        Map<UUID, String> names = new HashMap<>();
        if (admin.can(Permission.USERS_APPROVE)) {
            service.all(false).forEach(a -> names.put(a.id(), a.displayName()));
        }
        var actions = service.adminActions(200);
        // Deleted accounts are gone from profiles; the admin log kept their names.
        actions.forEach(a -> names.putIfAbsent(a.target(), a.targetName().isBlank() ? a.targetEmail() : a.targetName()));
        roleChanges.removeAll();
        var changes = service.roleChanges(200);
        changes.forEach(c -> roleChanges.add(new ListItem(name(names, c.userId()) + ": "
                + AccountsView.roleLabel(c.oldRole()) + " → " + AccountsView.roleLabel(c.newRole())
                + " – geändert von " + actor(names, c.changedBy()) + " am " + format(c.changedAt()))));
        if (changes.isEmpty()) {
            roleChanges.add(new ListItem(new Paragraph("Noch keine Rollenänderungen.")));
        }
        functionChanges.removeAll();
        var functions = new ClubFunctions(admin.db()).log(200);
        functions.forEach(f -> functionChanges.add(new ListItem(ClubFunctions.LABELS.getOrDefault(f.function(), f.function()) + ": "
                + person(f.oldName()) + " → " + person(f.newName())
                + " – geändert von " + actor(names, f.changedBy()) + " am " + format(f.changedAt()))));
        if (functions.isEmpty()) {
            functionChanges.add(new ListItem(new Paragraph("Noch keine Einträge.")));
        }
        adminActions.removeAll();
        actions.forEach(a -> adminActions.add(new ListItem(
                (a.targetName().isBlank() ? a.targetEmail() : a.targetName() + " (" + a.targetEmail() + ")")
                        + ": " + ACTIONS.getOrDefault(a.action(), a.action())
                        + " – von " + actor(names, a.actor()) + " am " + format(a.at()))));
        if (actions.isEmpty()) {
            adminActions.add(new ListItem(new Paragraph("Noch keine Einträge.")));
        }
    }

    private static String person(String name) {
        return name.isBlank() ? "nicht besetzt" : name;
    }

    private static String name(Map<UUID, String> names, UUID id) {
        return id == null ? "Unbekannt" : names.getOrDefault(id, "Konto " + id.toString().substring(0, 8));
    }

    private static String actor(Map<UUID, String> names, UUID id) {
        return id == null ? "System" : name(names, id);
    }

    private static String format(Instant instant) {
        return instant == null ? "–" : GermanUi.DAY_TIME.format(instant.atZone(ZoneId.of("Europe/Vienna")));
    }
}
