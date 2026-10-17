package it.a11y.blindensport.webadmin.ui;

import com.vaadin.flow.component.html.H2;
import com.vaadin.flow.component.html.ListItem;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.html.UnorderedList;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import it.a11y.blindensport.webadmin.accounts.AccountService;
import it.a11y.blindensport.webadmin.auth.AdminSession;
import it.a11y.blindensport.webadmin.auth.AdminSessions;
import it.a11y.blindensport.webadmin.auth.Permission;
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

    @Inject
    public RoleLogView(AdminSessions sessions) {
        super(sessions, "Rollen-Protokoll");
        add(new H2("Rollenänderungen"), roleChanges, new H2("Gesperrte und gelöschte Konten"), adminActions);
    }

    @Override
    protected void refresh() {
        AdminSession admin = session();
        AccountService service = new AccountService(admin.db());
        Map<UUID, String> names = new HashMap<>();
        if (admin.can(Permission.USERS_APPROVE)) {
            service.all(false).forEach(a -> names.put(a.id(), a.displayName()));
        }
        roleChanges.removeAll();
        var changes = service.roleChanges(200);
        changes.forEach(c -> roleChanges.add(new ListItem(name(names, c.userId()) + ": "
                + AccountsView.roleLabel(c.oldRole()) + " → " + AccountsView.roleLabel(c.newRole())
                + " – geändert von " + actor(names, c.changedBy()) + " am " + format(c.changedAt()))));
        if (changes.isEmpty()) {
            roleChanges.add(new ListItem(new Paragraph("Noch keine Rollenänderungen.")));
        }
        adminActions.removeAll();
        var actions = service.adminActions(200);
        actions.forEach(a -> adminActions.add(new ListItem(
                (a.targetName().isBlank() ? a.targetEmail() : a.targetName() + " (" + a.targetEmail() + ")")
                        + ": " + ACTIONS.getOrDefault(a.action(), a.action())
                        + " – von " + actor(names, a.actor()) + " am " + format(a.at()))));
        if (actions.isEmpty()) {
            adminActions.add(new ListItem(new Paragraph("Noch keine Einträge.")));
        }
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
