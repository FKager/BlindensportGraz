package it.a11y.blindensport.webadmin.ui;

import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.button.ButtonVariant;
import com.vaadin.flow.component.combobox.ComboBox;
import com.vaadin.flow.component.datepicker.DatePicker;
import com.vaadin.flow.component.dialog.Dialog;
import com.vaadin.flow.component.formlayout.FormLayout;
import com.vaadin.flow.component.grid.Grid;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.orderedlayout.FlexComponent;
import com.vaadin.flow.component.orderedlayout.HorizontalLayout;
import com.vaadin.flow.component.select.Select;
import com.vaadin.flow.component.textfield.BigDecimalField;
import com.vaadin.flow.component.textfield.TextField;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import it.a11y.blindensport.webadmin.auth.AdminSession;
import it.a11y.blindensport.webadmin.auth.AdminSessions;
import it.a11y.blindensport.webadmin.auth.Permission;
import it.a11y.blindensport.webadmin.club.ClubModels;
import it.a11y.blindensport.webadmin.club.ClubModels.BudgetEntry;
import it.a11y.blindensport.webadmin.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webadmin.club.ClubStore;
import jakarta.inject.Inject;

import java.math.BigDecimal;
import java.text.NumberFormat;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

import static it.a11y.blindensport.webadmin.members.Dates.CLUB_ZONE;

/** Club budget ("Vereinsbudget"): income and expenses per year, with balance. */
@Route(value = "budget", layout = MainLayout.class)
@PageTitle("Vereinsbudget – Blindensport Graz")
@RequiresPermission(Permission.BUDGET_MANAGE)
public class BudgetView extends AdminView {
    private static final NumberFormat EURO = NumberFormat.getCurrencyInstance(GermanUi.LOCALE);
    private static final List<String> CATEGORIES = List.of("fixedSubsidy", "donation", "eventCost", "otherExpense");

    private final Grid<BudgetEntry> grid = new Grid<>();
    private final Select<Integer> year = new Select<>();
    private final Paragraph totals = new Paragraph();
    private List<BudgetEntry> entries = List.of();
    private List<ClubEvent> events = List.of();
    private Map<String, ClubEvent> eventsById = Map.of();

    @Inject
    public BudgetView(AdminSessions sessions) {
        super(sessions, "Vereinsbudget");
        setSizeFull();
        year.setLabel("Jahr");
        year.addValueChangeListener(e -> applyFilter());
        Button add = new Button("Neuer Eintrag", e -> open(null));
        add.addThemeVariants(ButtonVariant.LUMO_PRIMARY);
        HorizontalLayout toolbar = new HorizontalLayout(year, add);
        toolbar.setDefaultVerticalComponentAlignment(FlexComponent.Alignment.BASELINE);
        totals.getElement().setAttribute("role", "status");
        totals.getStyle().set("font-weight", "600");

        grid.addColumn(b -> GermanUi.DAY.format(b.date().atZone(CLUB_ZONE))).setHeader("Datum").setAutoWidth(true)
                .setSortable(true).setComparator(BudgetEntry::date);
        grid.addColumn(b -> ClubModels.BUDGET_CATEGORIES.getOrDefault(b.category(), b.category()))
                .setHeader("Kategorie").setAutoWidth(true);
        grid.addColumn(b -> (b.isIncome() ? "+ " : "− ") + EURO.format(b.amount())).setHeader("Betrag")
                .setAutoWidth(true).setTextAlign(com.vaadin.flow.component.grid.ColumnTextAlign.END);
        grid.addColumn(BudgetEntry::note).setHeader("Notiz").setFlexGrow(1).setRowHeader(true);
        grid.addColumn(b -> b.eventId() != null && eventsById.containsKey(b.eventId()) ? eventsById.get(b.eventId()).title() : "")
                .setHeader("Termin").setFlexGrow(1);
        grid.addComponentColumn(b -> {
            String what = ClubModels.BUDGET_CATEGORIES.getOrDefault(b.category(), b.category()) + " vom "
                    + GermanUi.DAY.format(b.date().atZone(CLUB_ZONE));
            Button edit = GermanUi.label(new Button("Bearbeiten", e -> open(b)), what + " bearbeiten");
            Button delete = GermanUi.label(new Button("Löschen", e -> GermanUi.confirm(what + " löschen?",
                    "Der Eintrag wird gelöscht.", "Löschen", () -> {
                        if (attempt("Löschen", () -> store().deleteBudget(b.id()))) {
                            Announcer.success("Eintrag gelöscht.");
                            attempt("Laden", this::refresh);
                        }
                    })), what + " löschen");
            edit.addThemeVariants(ButtonVariant.LUMO_SMALL);
            delete.addThemeVariants(ButtonVariant.LUMO_SMALL, ButtonVariant.LUMO_ERROR);
            return new HorizontalLayout(edit, delete);
        }).setHeader("Aktionen").setAutoWidth(true).setFlexGrow(0).setFrozenToEnd(true);
        grid.setEmptyStateText("Keine Einträge in diesem Jahr.");
        grid.getElement().setAttribute("aria-label", "Budgeteinträge");
        grid.setSizeFull();
        add(toolbar, totals, grid);
        setFlexGrow(1, grid);
    }

    @Override
    protected void refresh() {
        ClubStore store = store();
        entries = store.budget();
        events = store.events();
        eventsById = events.stream().collect(Collectors.toMap(ClubEvent::id, Function.identity()));
        int current = LocalDate.now(CLUB_ZONE).getYear();
        List<Integer> years = java.util.stream.Stream.concat(java.util.stream.Stream.of(current),
                        entries.stream().map(b -> b.date().atZone(CLUB_ZONE).getYear()))
                .distinct().sorted(java.util.Comparator.reverseOrder()).toList();
        Integer selected = year.getValue();
        year.setItems(years);
        year.setValue(selected != null && years.contains(selected) ? selected : current);
        applyFilter();
    }

    private ClubStore store() {
        AdminSession admin = session();
        return new ClubStore(admin.db(), admin.userId());
    }

    private void applyFilter() {
        Integer y = year.getValue();
        List<BudgetEntry> shown = entries.stream()
                .filter(b -> y == null || b.date().atZone(CLUB_ZONE).getYear() == y).toList();
        grid.setItems(shown);
        BigDecimal income = shown.stream().filter(BudgetEntry::isIncome).map(BudgetEntry::amount)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
        BigDecimal expenses = shown.stream().filter(b -> !b.isIncome()).map(BudgetEntry::amount)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
        totals.setText("Einnahmen " + EURO.format(income) + " · Ausgaben " + EURO.format(expenses)
                + " · Saldo " + EURO.format(income.subtract(expenses)));
    }

    private void open(BudgetEntry b) {
        Dialog dialog = new Dialog();
        dialog.setHeaderTitle(b == null ? "Neuer Eintrag" : "Eintrag bearbeiten");
        dialog.setWidth("min(40rem, 100vw)");
        Select<String> category = new Select<>();
        category.setLabel("Kategorie");
        category.setItems(CATEGORIES);
        category.setItemLabelGenerator(c -> ClubModels.BUDGET_CATEGORIES.getOrDefault(c, c)
                + ("fixedSubsidy".equals(c) || "donation".equals(c) ? " (Einnahme)" : " (Ausgabe)"));
        BigDecimalField amount = new BigDecimalField("Betrag (€)");
        amount.setHelperText("Immer positiv – Einnahme oder Ausgabe ergibt sich aus der Kategorie");
        DatePicker date = GermanUi.datePicker("Datum");
        TextField note = new TextField("Notiz");
        ComboBox<ClubEvent> event = new ComboBox<>("Termin (optional)");
        event.setItems(events);
        event.setItemLabelGenerator(e -> e.title() + " (" + GermanUi.DAY.format(e.startDate().atZone(CLUB_ZONE)) + ")");
        event.setClearButtonVisible(true);
        if (b == null) {
            category.setValue("eventCost");
            date.setValue(LocalDate.now(CLUB_ZONE));
        } else {
            category.setValue(CATEGORIES.contains(b.category()) ? b.category() : "otherExpense");
            amount.setValue(b.amount());
            date.setValue(LocalDate.ofInstant(b.date(), CLUB_ZONE));
            note.setValue(b.note());
            if (b.eventId() != null) {
                event.setValue(eventsById.get(b.eventId()));
            }
        }
        FormLayout form = new FormLayout(category, amount, date, note, event);
        form.setColspan(event, 2);
        dialog.add(form);
        Button save = new Button("Speichern", e -> {
            if (amount.getValue() == null || amount.getValue().signum() == 0 || date.getValue() == null) {
                Announcer.error("Bitte Betrag und Datum angeben.");
                amount.focus();
                return;
            }
            BudgetEntry saved = new BudgetEntry(b == null ? ClubStore.newId() : b.id(), category.getValue(),
                    amount.getValue().abs(), EventDialog.dayInstant(date.getValue(), b == null ? null : b.date(),
                    java.time.LocalTime.NOON), note.getValue(),
                    event.getValue() == null ? null : event.getValue().id(),
                    b == null ? store().createdBy() : b.createdBy());
            if (attempt("Speichern", () -> store().saveBudget(saved))) {
                dialog.close();
                Announcer.success("Eintrag gespeichert.");
                attempt("Laden", this::refresh);
            }
        });
        save.addThemeVariants(ButtonVariant.LUMO_PRIMARY);
        dialog.getFooter().add(new Button("Abbrechen", e -> dialog.close()), save);
        dialog.open();
    }
}
