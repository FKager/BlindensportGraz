package it.a11y.blindensport.webadmin.ui;

import com.vaadin.flow.component.Component;
import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.button.ButtonVariant;
import com.vaadin.flow.component.combobox.ComboBox;
import com.vaadin.flow.component.combobox.MultiSelectComboBox;
import com.vaadin.flow.component.datepicker.DatePicker;
import com.vaadin.flow.component.datetimepicker.DateTimePicker;
import com.vaadin.flow.component.dialog.Dialog;
import com.vaadin.flow.component.formlayout.FormLayout;
import com.vaadin.flow.component.select.Select;
import com.vaadin.flow.component.textfield.IntegerField;
import com.vaadin.flow.component.textfield.TextArea;
import com.vaadin.flow.component.textfield.TextField;
import it.a11y.blindensport.webadmin.club.ClubModels;
import it.a11y.blindensport.webadmin.club.ClubModels.ClubEvent;
import it.a11y.blindensport.webadmin.club.ClubModels.Team;
import it.a11y.blindensport.webadmin.club.ClubStore;

import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.List;
import java.util.Map;
import java.util.function.Consumer;

import static it.a11y.blindensport.webadmin.members.Dates.CLUB_ZONE;

/**
 * Create / edit a training, tournament or event. Trainings: start + duration
 * (end follows); tournaments: days only, like the app; events: start and end.
 */
class EventDialog extends Dialog {
    private final ClubEvent existing;
    private final String kind;
    private final TextField title = new TextField("Titel");
    private final ComboBox<String> sport;
    private final DateTimePicker start = GermanUi.dateTimePicker("Beginn");
    private final DateTimePicker end = GermanUi.dateTimePicker("Ende");
    private final DatePicker startDay = GermanUi.datePicker("Erster Tag");
    private final DatePicker endDay = GermanUi.datePicker("Letzter Tag");
    private final IntegerField duration = new IntegerField("Dauer (Minuten)");
    private final TextField focusArea = new TextField("Schwerpunkt");
    private final IntegerField maxTeams = new IntegerField("Max. Teams");
    private final Select<String> status = new Select<>();
    private final TextField location = new TextField("Ort / Halle");
    private final TextField street = new TextField("Straße");
    private final TextField zip = new TextField("PLZ");
    private final TextField city = new TextField("Stadt");
    private final TextField country = new TextField("Land");
    private final TextArea notes = new TextArea("Notizen");
    private final MultiSelectComboBox<Team> teams;

    EventDialog(String kind, ClubEvent existing, List<Team> allTeams, String createdBy, Consumer<ClubEvent> onSave) {
        this.existing = existing;
        this.kind = existing != null ? existing.kind() : kind;
        String label = ClubModels.KINDS.getOrDefault(this.kind, "Event");
        setHeaderTitle(existing == null ? ("tournament".equals(this.kind) ? "Neues Turnier" : "Neues " + label)
                : label + " bearbeiten: " + existing.title());
        setWidth("min(52rem, 100vw)");
        setCloseOnOutsideClick(false);
        sport = ClubFields.sport(existing == null ? "" : existing.sport());
        teams = ClubFields.teams(allTeams, existing == null ? List.of() : existing.teamIds());
        title.setRequired(true);
        duration.setMin(1);
        duration.setStepButtonsVisible(true);
        duration.setStep(15);
        maxTeams.setMin(1);
        maxTeams.setStepButtonsVisible(true);
        status.setLabel("Status");
        Map<String, String> statuses = "tournament".equals(this.kind) ? ClubModels.TOURNAMENT_STATUS
                : "training".equals(this.kind) ? ClubModels.TRAINING_STATUS : Map.of();
        if (!statuses.isEmpty()) {
            List<String> order = "tournament".equals(this.kind) ? List.of("planned", "ongoing", "finished")
                    : List.of("open", "held", "cancelled");
            status.setItems(order);
            status.setItemLabelGenerator(s -> statuses.getOrDefault(s, s));
        }

        FormLayout form = new FormLayout();
        form.setResponsiveSteps(new FormLayout.ResponsiveStep("0", 1), new FormLayout.ResponsiveStep("32rem", 2));
        form.add(title, sport);
        switch (this.kind) {
            case "training" -> form.add(start, duration, focusArea, status);
            case "tournament" -> form.add(startDay, endDay, maxTeams, status);
            default -> form.add(start, end);
        }
        form.add(teams, location, street, zip, city, country, notes);
        form.setColspan(notes, 2);
        form.setColspan(teams, 2);
        add(form);
        fill();

        Button save = new Button("Speichern", e -> {
            ClubEvent event = build(createdBy);
            if (event != null) {
                onSave.accept(event);
            }
        });
        save.addThemeVariants(ButtonVariant.LUMO_PRIMARY);
        getFooter().add(new Button("Abbrechen", e -> close()), save);
        addOpenedChangeListener(e -> {
            if (e.isOpened()) {
                title.focus();
            }
        });
    }

    private void fill() {
        LocalDateTime defaultStart = LocalDate.now(CLUB_ZONE).plusDays(1).atTime(18, 0);
        if (existing == null) {
            start.setValue(defaultStart);
            end.setValue(defaultStart.plusHours(2));
            startDay.setValue(defaultStart.toLocalDate());
            endDay.setValue(defaultStart.toLocalDate());
            duration.setValue(90);
            maxTeams.setValue(8);
            status.setValue("tournament".equals(kind) ? "planned" : "training".equals(kind) ? "open" : null);
            country.setValue("Österreich");
            return;
        }
        title.setValue(existing.title());
        start.setValue(local(existing.startDate()));
        end.setValue(local(existing.endDate()));
        startDay.setValue(local(existing.startDate()).toLocalDate());
        endDay.setValue(local(existing.endDate()).toLocalDate());
        duration.setValue(existing.durationMinutes() != null ? existing.durationMinutes()
                : (int) java.time.Duration.between(existing.startDate(), existing.endDate()).toMinutes());
        focusArea.setValue(existing.focusArea() == null ? "" : existing.focusArea());
        maxTeams.setValue(existing.maxTeams());
        if (!existing.status().isBlank()) {
            status.setValue(existing.status());
        }
        location.setValue(existing.location());
        street.setValue(existing.street());
        zip.setValue(existing.zip());
        city.setValue(existing.city());
        country.setValue(existing.country());
        notes.setValue(existing.notes());
    }

    /** The edited event, or null (with an announced reason) if a required field is missing. */
    private ClubEvent build(String createdBy) {
        if (title.getValue().isBlank()) {
            return invalid("Bitte einen Titel eingeben.", title);
        }
        Instant startAt;
        Instant endAt;
        switch (kind) {
            case "training" -> {
                if (start.getValue() == null || duration.getValue() == null || duration.getValue() < 1) {
                    return invalid("Bitte Beginn und Dauer angeben.", start);
                }
                startAt = start.getValue().atZone(CLUB_ZONE).toInstant();
                endAt = startAt.plusSeconds(duration.getValue() * 60L);
            }
            case "tournament" -> {
                if (startDay.getValue() == null || endDay.getValue() == null) {
                    return invalid("Bitte ersten und letzten Tag angeben.", startDay);
                }
                if (endDay.getValue().isBefore(startDay.getValue())) {
                    return invalid("Der letzte Tag liegt vor dem ersten.", endDay);
                }
                startAt = dayInstant(startDay.getValue(), existing == null ? null : existing.startDate(), LocalTime.of(9, 0));
                endAt = dayInstant(endDay.getValue(), existing == null ? null : existing.endDate(), LocalTime.of(18, 0));
            }
            default -> {
                if (start.getValue() == null || end.getValue() == null) {
                    return invalid("Bitte Beginn und Ende angeben.", start);
                }
                startAt = start.getValue().atZone(CLUB_ZONE).toInstant();
                endAt = end.getValue().atZone(CLUB_ZONE).toInstant();
                if (endAt.isBefore(startAt)) {
                    return invalid("Das Ende liegt vor dem Beginn.", end);
                }
            }
        }
        return new ClubEvent(
                existing == null ? ClubStore.newId() : existing.id(), kind, title.getValue(),
                ClubFields.sportValue(sport), location.getValue(), street.getValue(), zip.getValue(), city.getValue(),
                country.getValue(), startAt, endAt, notes.getValue(),
                status.getValue() == null ? (existing == null ? "" : existing.status()) : status.getValue(),
                "training".equals(kind) ? duration.getValue() : existing == null ? null : existing.durationMinutes(),
                "training".equals(kind) ? focusArea.getValue() : existing == null ? null : existing.focusArea(),
                "tournament".equals(kind) ? maxTeams.getValue() : existing == null ? null : existing.maxTeams(),
                ClubFields.teamIds(teams),
                existing == null ? createdBy : existing.createdBy());
    }

    private ClubEvent invalid(String message, Component field) {
        Announcer.error(message);
        if (field instanceof com.vaadin.flow.component.Focusable<?> focusable) {
            focusable.focus();
        }
        return null;
    }

    /** Same day as stored → keep the stored time; otherwise a sensible default time in Vienna. */
    static Instant dayInstant(LocalDate day, Instant previous, LocalTime defaultTime) {
        if (previous != null && LocalDate.ofInstant(previous, CLUB_ZONE).equals(day)) {
            return previous;
        }
        return day.atTime(defaultTime).atZone(CLUB_ZONE).toInstant();
    }

    private static LocalDateTime local(Instant instant) {
        return LocalDateTime.ofInstant(instant, CLUB_ZONE);
    }
}
