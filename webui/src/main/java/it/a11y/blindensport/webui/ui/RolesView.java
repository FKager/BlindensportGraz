package it.a11y.blindensport.webui.ui;

import com.vaadin.flow.component.Text;
import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.html.H2;
import com.vaadin.flow.component.html.ListItem;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.html.UnorderedList;
import com.vaadin.flow.component.orderedlayout.FlexComponent;
import com.vaadin.flow.component.orderedlayout.HorizontalLayout;
import com.vaadin.flow.component.orderedlayout.VerticalLayout;
import com.vaadin.flow.component.select.Select;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import com.vaadin.flow.router.RouterLink;
import it.a11y.blindensport.webui.accounts.AccountService;
import it.a11y.blindensport.webui.auth.AdminSession;
import it.a11y.blindensport.webui.auth.AdminSessions;
import it.a11y.blindensport.webui.auth.Permission;
import it.a11y.blindensport.webui.club.ClubFunctions;
import it.a11y.blindensport.webui.members.MemberRecord;
import it.a11y.blindensport.webui.members.MemberStatus;
import it.a11y.blindensport.webui.members.MemberStore;
import jakarta.inject.Inject;

import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Who holds which position: the Vereinsfunktionen (admin and root change them,
 * they give no rights) and the Admin and Root accounts (only root changes
 * those, and they can have several people).
 */
@Route(value = "rollen", layout = MainLayout.class)
@PageTitle("Rollen – Blindensport Graz")
@RequiresPermission(Permission.CLUB_MANAGE)
public class RolesView extends AdminView {
    private static final String VACANT = "";

    private final VerticalLayout content = new VerticalLayout();

    @Inject
    public RolesView(AdminSessions sessions) {
        super(sessions, "Rollen");
        content.setPadding(false);
        add(content);
    }

    @Override
    protected void refresh() {
        AdminSession admin = session();
        content.removeAll();
        content.add(new H2("Vereinsfunktionen"),
                new Paragraph("Halten fest, wer welche Funktion hat. Sie geben keine zusätzlichen Rechte."));
        functions(admin);
        accounts(admin);
        if (admin.can(Permission.ROLELOG_READ)) {
            content.add(new H2("Protokoll"), new RouterLink("Rollenänderungen", RoleLogView.class));
        }
    }

    private void functions(AdminSession admin) {
        Map<String, String> names = new LinkedHashMap<>();
        names.put(VACANT, "Nicht besetzt");
        new MemberStore(admin.db()).all(false).stream()
                .filter(m -> !MemberStatus.DELETE.equals(m.status()))
                .sorted(Comparator.comparing(MemberRecord::lastName).thenComparing(MemberRecord::firstName))
                .forEach(m -> names.put(m.id().toLowerCase(java.util.Locale.ROOT), m.lastName() + ", " + m.firstName()));
        ClubFunctions functions = new ClubFunctions(admin.db());
        Map<String, String> holders = functions.holders();
        ClubFunctions.LABELS.forEach((key, label) -> {
            Select<String> holder = new Select<>();
            holder.setLabel(label);
            holder.setWidth("24rem");
            holder.setItems(List.copyOf(names.keySet()));
            holder.setItemLabelGenerator(id -> names.getOrDefault(id, id));
            String current = holders.getOrDefault(key, VACANT);
            // A holder marked for deletion isn't offered, but stays shown until replaced.
            holder.setValue(names.containsKey(current) ? current : VACANT);
            holder.addValueChangeListener(e -> {
                if (!e.isFromClient()) {
                    return;
                }
                String value = e.getValue();
                if (attempt("Speichern", () -> functions.set(key, value == null || value.isEmpty() ? null : value))) {
                    Announcer.success(label + ": " + names.get(value == null ? VACANT : value));
                } else {
                    attempt("Laden", this::refresh);
                }
            });
            content.add(holder);
        });
    }

    private void accounts(AdminSession admin) {
        AccountService service = new AccountService(admin.db());
        List<AccountService.Account> accounts = service.all(false);
        boolean canChange = admin.can(Permission.ROLES_ASSIGN);
        section("Admin", "admin", accounts, canChange, admin, service);
        section("Root", "root", accounts, canChange, admin, service);
        content.add(new Paragraph(canChange
                ? "Admin und Root gelten für App-Konten. Mitglieder ohne Konto können sie nicht bekommen."
                : "Admin und Root kann nur Root ändern."));
    }

    private void section(String label, String role, List<AccountService.Account> accounts, boolean canChange,
                         AdminSession admin, AccountService service) {
        content.add(new H2(label));
        UnorderedList list = new UnorderedList();
        List<AccountService.Account> holders = accounts.stream().filter(a -> role.equals(a.role())).toList();
        for (AccountService.Account account : holders) {
            ListItem item = new ListItem(new Text(account.displayName() + " (" + account.email() + ") "));
            if (canChange && !account.id().equals(admin.userId())) {
                item.add(GermanUi.label(new Button("Entfernen", e -> remove(label, account, service)),
                        account.displayName() + " als " + label + " entfernen"));
            }
            list.add(item);
        }
        if (holders.isEmpty()) {
            list.add(new ListItem("Niemand."));
        }
        content.add(list);
        if (canChange) {
            Select<AccountService.Account> add = new Select<>();
            add.setLabel(label + " hinzufügen");
            add.setWidth("24rem");
            add.setItems(accounts.stream().filter(a -> !role.equals(a.role()) && !a.id().equals(admin.userId())).toList());
            add.setItemLabelGenerator(a -> a.displayName() + " (" + a.email() + ")");
            Button save = GermanUi.label(new Button("Hinzufügen", e -> {
                if (add.getValue() == null) {
                    Announcer.error("Bitte ein Konto auswählen.");
                } else if (attempt("Speichern", () -> service.setRole(add.getValue().id(), role))) {
                    Announcer.success(add.getValue().displayName() + " ist jetzt " + label + ".");
                    attempt("Laden", this::refresh);
                }
            }), label + " hinzufügen");
            HorizontalLayout row = new HorizontalLayout(add, save);
            row.setDefaultVerticalComponentAlignment(FlexComponent.Alignment.BASELINE);
            content.add(row);
        }
    }

    /** Back to plain member; the account itself stays. The database protects the last root. */
    private void remove(String label, AccountService.Account account, AccountService service) {
        GermanUi.confirm(account.displayName() + " als " + label + " entfernen?", "Das Konto wird zu einem normalen Mitglied.",
                "Entfernen", () -> {
                    if (attempt("Speichern", () -> service.setRole(account.id(), "member"))) {
                        Announcer.success(account.displayName() + " ist nicht mehr " + label + ".");
                        attempt("Laden", this::refresh);
                    }
                });
    }
}
