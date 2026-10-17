package it.a11y.blindensport.webadmin.ui;

import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.checkbox.Checkbox;
import com.vaadin.flow.component.dialog.Dialog;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.orderedlayout.FlexComponent;
import com.vaadin.flow.component.orderedlayout.HorizontalLayout;
import com.vaadin.flow.component.orderedlayout.VerticalLayout;
import com.vaadin.flow.component.textfield.IntegerField;
import it.a11y.blindensport.webadmin.club.ClubModels.Attendance;
import it.a11y.blindensport.webadmin.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webadmin.club.ClubModels.Membership;
import it.a11y.blindensport.webadmin.club.ClubStore;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.Function;
import java.util.function.Supplier;

/**
 * Roll call for one training or tournament, like the app's
 * AttendanceRollCallView: one checkbox per person of the event's teams
 * (each person once), saved immediately; coaches and assistants who
 * attended get a PRAE amount in €5 steps.
 */
class AttendanceDialog extends Dialog {
    private final Paragraph summary = new Paragraph();
    private final Map<String, Attendance> byMembership = new HashMap<>();
    private final List<Membership> roster;

    AttendanceDialog(ClubEvent event, List<Membership> allMemberships, Function<Membership, String> name,
                     Supplier<ClubStore> store, AdminView view) {
        setHeaderTitle("Anwesenheit: " + event.title());
        setWidth("min(40rem, 100vw)");
        roster = rosterAcrossTeams(event, allMemberships, name);
        List<Attendance> stored = view.attempt("Laden", () -> store.get().attendances(event.id()));
        if (stored != null) {
            stored.forEach(a -> byMembership.put(a.membershipId(), a));
        }
        summary.getElement().setAttribute("role", "status");

        VerticalLayout list = new VerticalLayout();
        list.setPadding(false);
        if (roster.isEmpty()) {
            list.add(new Paragraph("Diesem Eintrag ist kein Team zugewiesen – zuerst unter „Bearbeiten“ Teams auswählen."));
        }
        for (Membership m : roster) {
            Attendance current = byMembership.get(m.id());
            Checkbox present = new Checkbox(name.apply(m), current != null && current.attended());
            IntegerField prae = new IntegerField("PRAE (€) für " + name.apply(m));
            prae.setMin(0);
            prae.setMax(event.maxPrae());
            prae.setStep(5);
            prae.setStepButtonsVisible(true);
            prae.setHelperText("0–" + event.maxPrae() + " €, in 5-€-Schritten");
            prae.setValue(current != null && current.praeAmount() != null ? current.praeAmount().intValue() : 0);
            prae.setVisible(m.isHelper() && present.getValue());
            present.addValueChangeListener(e -> {
                if (!e.isFromClient()) {
                    return;
                }
                if (save(m, e.getValue(), prae.getValue(), event, store, view)) {
                    prae.setVisible(m.isHelper() && e.getValue());
                    Announcer.success(name.apply(m) + (e.getValue() ? " anwesend." : " abwesend."));
                } else {
                    present.setValue(!e.getValue());
                }
            });
            prae.addValueChangeListener(e -> {
                if (!e.isFromClient()) {
                    return;
                }
                int value = e.getValue() == null ? 0 : Math.max(0, Math.min(event.maxPrae(), e.getValue()));
                value = Math.round(value / 5f) * 5;
                if (value != (e.getValue() == null ? 0 : e.getValue())) {
                    prae.setValue(value);
                }
                if (save(m, true, value, event, store, view)) {
                    Announcer.success("PRAE für " + name.apply(m) + ": " + value + " €");
                }
            });
            HorizontalLayout row = new HorizontalLayout(present, prae);
            row.setDefaultVerticalComponentAlignment(FlexComponent.Alignment.BASELINE);
            row.setWrap(true);
            list.add(row);
        }
        updateSummary();
        add(summary, list);
        getFooter().add(new Button("Schließen", e -> close()));
    }

    private boolean save(Membership m, boolean attended, Integer praeEuro, ClubEvent event, Supplier<ClubStore> store,
                         AdminView view) {
        Attendance old = byMembership.get(m.id());
        Attendance updated = new Attendance(old == null ? ClubStore.newId() : old.id(), event.id(), m.id(), attended,
                m.isHelper() && attended && praeEuro != null && praeEuro > 0 ? BigDecimal.valueOf(praeEuro) : null);
        if (view.attempt("Anwesenheit speichern", () -> store.get().saveAttendance(updated))) {
            byMembership.put(m.id(), updated);
            updateSummary();
            return true;
        }
        return false;
    }

    private void updateSummary() {
        long present = roster.stream().filter(m -> byMembership.containsKey(m.id()) && byMembership.get(m.id()).attended()).count();
        summary.setText(present + " von " + roster.size() + " anwesend");
    }

    /** Memberships of the event's teams, each person once, sorted by name (SportEvent.rosterAcrossTeams). */
    static List<Membership> rosterAcrossTeams(ClubEvent event, List<Membership> all, Function<Membership, String> name) {
        Set<String> seen = new HashSet<>();
        List<Membership> result = new ArrayList<>();
        for (String teamId : event.teamIds()) {
            for (Membership m : all) {
                if (!m.teamId().equals(teamId)) {
                    continue;
                }
                String key = m.userId() != null ? m.userId() : m.memberId() != null ? m.memberId() : m.id();
                if (seen.add(key)) {
                    result.add(m);
                }
            }
        }
        result.sort(java.util.Comparator.comparing(name));
        return result;
    }
}
