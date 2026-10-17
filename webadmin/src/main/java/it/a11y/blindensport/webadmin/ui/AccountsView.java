package it.a11y.blindensport.webadmin.ui;

import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.grid.Grid;
import com.vaadin.flow.component.grid.GridVariant;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.orderedlayout.FlexComponent;
import com.vaadin.flow.component.orderedlayout.HorizontalLayout;
import com.vaadin.flow.component.select.Select;
import com.vaadin.flow.component.textfield.TextField;
import com.vaadin.flow.data.value.ValueChangeMode;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import it.a11y.blindensport.webadmin.accounts.AccountService;
import it.a11y.blindensport.webadmin.accounts.AccountService.Account;
import it.a11y.blindensport.webadmin.auth.AdminSession;
import it.a11y.blindensport.webadmin.auth.AdminSessions;
import it.a11y.blindensport.webadmin.auth.Permission;
import it.a11y.blindensport.webadmin.members.MemberRecord;
import it.a11y.blindensport.webadmin.members.MemberStore;
import jakarta.inject.Inject;

import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;
import java.util.stream.Stream;

/**
 * "App-Konten": approve accounts and link them to their roster entry,
 * activation codes; with roles.assign (root) also roles, blocking and
 * deleting. Mirrors the app's UserListView.
 */
@Route(value = "konten", layout = MainLayout.class)
@PageTitle("App-Konten – Blindensport Graz")
@RequiresPermission({Permission.USERS_APPROVE, Permission.ROLES_ASSIGN})
public class AccountsView extends AdminView {
    static final String ALL = "Alle Konten";
    static final String PENDING = "Nicht freigegeben";
    static final String BLOCKED = "Gesperrt";

    private final Grid<Account> grid = new Grid<>();
    private final TextField search = new TextField("Suchen");
    private final Select<String> filter = new Select<>();
    private final Paragraph count = new Paragraph();
    private List<Account> accounts = List.of();
    private List<MemberRecord> roster = List.of();
    private Map<String, MemberRecord> membersById = Map.of();

    @Inject
    public AccountsView(AdminSessions sessions) {
        super(sessions, "App-Konten");
        setSizeFull();

        search.setPlaceholder("Name oder E-Mail");
        search.setClearButtonVisible(true);
        search.setValueChangeMode(ValueChangeMode.LAZY);
        search.addValueChangeListener(e -> applyFilter());
        filter.setLabel("Anzeigen");
        filter.setItems(ALL, PENDING, BLOCKED);
        filter.setValue(ALL);
        filter.addValueChangeListener(e -> applyFilter());
        Button reload = new Button("Neu laden", e -> attempt("Laden", this::refresh));
        HorizontalLayout toolbar = new HorizontalLayout(search, filter, reload);
        toolbar.setDefaultVerticalComponentAlignment(FlexComponent.Alignment.BASELINE);
        toolbar.setWrap(true);
        count.getElement().setAttribute("role", "status");

        grid.addColumn(Account::displayName).setHeader("Name").setRowHeader(true).setAutoWidth(true).setSortable(true);
        grid.addColumn(Account::email).setHeader("E-Mail").setFlexGrow(1);
        grid.addColumn(a -> roleLabel(a.role())).setHeader("Rolle").setAutoWidth(true).setFlexGrow(0);
        grid.addColumn(this::status).setHeader("Freigabe").setFlexGrow(1);
        grid.addComponentColumn(a -> GermanUi.label(new Button("Verwalten", e -> openDialog(a)),
                a.displayName() + " verwalten")).setHeader("Aktionen").setAutoWidth(true).setFlexGrow(0)
                .setFrozenToEnd(true);
        grid.addThemeVariants(GridVariant.LUMO_ROW_STRIPES);
        grid.setEmptyStateText("Keine Konten gefunden.");
        grid.getElement().setAttribute("aria-label", "App-Konten");
        grid.addItemDoubleClickListener(e -> openDialog(e.getItem()));
        grid.setSizeFull();

        add(new Paragraph("Neue Konten sehen nur die Termine, bis sie freigegeben und mit ihrem Eintrag in der "
                + "Mitgliederliste verknüpft sind."), toolbar, count, grid);
        setFlexGrow(1, grid);
    }

    @Override
    protected void refresh() {
        AdminSession admin = session();
        roster = new MemberStore(admin.db()).all(false);
        membersById = roster.stream().collect(Collectors.toMap(MemberRecord::id, Function.identity(), (a, b) -> a));
        accounts = new AccountService(admin.db()).all(admin.can(Permission.ROLES_ASSIGN));
        filter.setItems(admin.can(Permission.ROLES_ASSIGN) ? List.of(ALL, PENDING, BLOCKED) : List.of(ALL, PENDING));
        if (filter.getValue() == null) {
            filter.setValue(ALL);
        }
        applyFilter();
    }

    private void applyFilter() {
        String q = search.getValue().trim().toLowerCase(Locale.ROOT);
        String mode = filter.getValue() == null ? ALL : filter.getValue();
        List<Account> shown = accounts.stream()
                .filter(a -> q.isEmpty() || Stream.of(a.firstName(), a.lastName(), a.email())
                        .anyMatch(s -> s.toLowerCase(Locale.ROOT).contains(q)))
                .filter(a -> switch (mode) {
                    case PENDING -> a.approval() == null && !a.hasFullAccess();
                    case BLOCKED -> a.blocked();
                    default -> true;
                })
                .toList();
        grid.setItems(shown);
        count.setText(shown.size() == accounts.size() ? accounts.size() + " Konten"
                : shown.size() + " von " + accounts.size() + " Konten");
    }

    static String roleLabel(String role) {
        return role == null ? "– (ausstehend)" : Permission.ROLE_NAMES.getOrDefault(role, role);
    }

    /** Status line, same wording as the app's UserApprovalControls. */
    String status(Account a) {
        String prefix = a.blocked() ? "Gesperrt · " : "";
        String access = a.hasFullAccess() ? "Voller Zugriff als " + roleLabel(a.role()) + " · " : "";
        if (a.approval() != null) {
            MemberRecord m = membersById.get(a.approval().memberId());
            return prefix + access + (m != null ? "Freigegeben: " + m.fullName()
                    : "Freigegeben (Eintrag in der Mitgliederliste fehlt)");
        }
        var suggestion = AccountService.suggest(a, roster);
        if (suggestion.isPresent()) {
            String how = suggestion.get().byEmail() ? "E-Mail" : "Name";
            return prefix + access + (a.hasFullAccess() ? "Kein Eintrag verknüpft" : "Nicht freigegeben")
                    + " – Vorschlag: " + suggestion.get().member().fullName() + " (" + how + ")";
        }
        return prefix + access + (a.hasFullAccess() ? "Kein Eintrag in der Mitgliederliste verknüpft"
                : "Nicht freigegeben – nur Termine sichtbar");
    }

    private void openDialog(Account account) {
        AdminSession admin = session();
        new AccountDialog(account, status(account), roster, admin, this).open();
    }

    /** Runs an account action, announces the result and reloads; returns false on failure. */
    boolean perform(String action, String successMessage, Runnable work) {
        if (attempt(action, work)) {
            Announcer.success(successMessage);
            attempt("Laden", this::refresh);
            return true;
        }
        return false;
    }

    AccountService service() {
        return new AccountService(session().db());
    }
}
