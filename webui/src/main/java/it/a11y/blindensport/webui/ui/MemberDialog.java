package it.a11y.blindensport.webui.ui;

import com.vaadin.flow.component.Component;
import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.button.ButtonVariant;
import com.vaadin.flow.component.checkbox.Checkbox;
import com.vaadin.flow.component.datepicker.DatePicker;
import com.vaadin.flow.component.dialog.Dialog;
import com.vaadin.flow.component.formlayout.FormLayout;
import com.vaadin.flow.component.html.H3;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.select.Select;
import com.vaadin.flow.component.textfield.EmailField;
import com.vaadin.flow.component.textfield.TextArea;
import com.vaadin.flow.component.textfield.TextField;
import it.a11y.blindensport.webui.members.MemberApplication;
import it.a11y.blindensport.webui.members.MemberHealth;
import it.a11y.blindensport.webui.members.MemberPrivate;
import it.a11y.blindensport.webui.members.MemberRecord;
import it.a11y.blindensport.webui.members.MemberStatus;
import it.a11y.blindensport.webui.members.Validation;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Create / edit one roster entry, laid out like the app's MemberDetailView.
 * Protected fields appear only with members.private.read and are editable
 * only with members.private.write.
 */
class MemberDialog extends Dialog {
    private static final Map<String, String> GENDERS = Map.of("", "–", "f", "weiblich", "m", "männlich");
    private static final Map<String, String> MEMBERSHIP_TYPES =
            Map.of("", "–", "active", "aktiv", "supporting", "fördernd");
    private static final Map<String, String> CONSENTS = Map.of("", "–", "true", "Ja", "false", "Nein");

    /** What "Speichern" hands back; {@code health} is null unless it must be written. */
    interface SaveHandler {
        void save(MemberRecord record, boolean writePrivate, MemberApplication application, MemberHealth health);
    }

    private final MemberRecord existing;
    private final boolean canReadPrivate;
    private final boolean canWritePrivate;

    private final TextField firstName = new TextField("Vorname");
    private final TextField lastName = new TextField("Nachname");
    private final TextField title = new TextField("Titel");
    private final Select<String> gender = new Select<>();
    private final TextField street = new TextField("Straße");
    private final TextField zip = new TextField("PLZ");
    private final TextField city = new TextField("Ort");
    private final TextField country = new TextField("Land");
    private final EmailField email = new EmailField("E-Mail");
    private final TextField phone = new TextField("Telefon");
    private final Select<String> status = new Select<>();
    private final Checkbox memberOfGVSC = new Checkbox("Mitglied des Grazer VSC");
    private final TextField memberNumber = new TextField("Mitgliedsnummer");
    private final DatePicker joinedAt = GermanUi.datePicker("Beigetreten");
    private final TextField sportId = new TextField("Sport-ID");
    private final TextField defaultFunction = new TextField("Standardfunktion");
    private final TextArea notes = new TextArea("Notizen");
    private final TextField svnr = new TextField("SVNR");
    private final TextField iban = new TextField("IBAN");
    private final DatePicker birthDate = GermanUi.datePicker("Geburtsdatum");
    private final DatePicker lastMedicalExamination = GermanUi.datePicker("Letzte sportärztl. Untersuchung");
    private final Select<String> membershipType = new Select<>();
    private final TextField citizenship = new TextField("Staatsbürgerschaft");
    private final TextField mobile = new TextField("Mobilnummer");
    private final TextField guardianFirstName = new TextField("Vorname");
    private final TextField guardianLastName = new TextField("Nachname");
    private final TextField guardianStreet = new TextField("Straße, Hausnummer");
    private final TextField guardianZip = new TextField("PLZ");
    private final TextField guardianCity = new TextField("Wohnort");
    private final TextField guardianPhone = new TextField("Telefon");
    private final TextField guardianMobile = new TextField("Mobilnummer");
    private final EmailField guardianEmail = new EmailField("E-Mail");
    private final TextField disabilityType = new TextField("Art der Behinderung");
    private final TextField disabilityClass = new TextField("Behinderungsklasse");
    private final TextField disabilityCause = new TextField("Behinderung durch (Arbeit, Freizeit)");
    private final Select<String> consentDataTransfer = new Select<>();
    private final Select<String> consentPhotos = new Select<>();
    private final MemberHealth existingHealth;

    /**
     * @param existing    null for a new entry
     * @param application the Beitrittserklärung contact fields (EMPTY for a new entry)
     * @param health      disability/consents (EMPTY unless members.private.read)
     */
    MemberDialog(MemberRecord existing, MemberApplication application, MemberHealth health,
                 boolean canReadPrivate, boolean canWritePrivate, SaveHandler onSave) {
        this.existing = existing;
        this.existingHealth = health;
        this.canReadPrivate = canReadPrivate;
        this.canWritePrivate = canReadPrivate && canWritePrivate;
        setHeaderTitle(existing == null ? "Neues Mitglied" : existing.fullName() + " bearbeiten");
        setWidth("min(56rem, 100vw)");
        setCloseOnOutsideClick(false);

        gender.setLabel("Geschlecht");
        gender.setItems("", "f", "m");
        gender.setItemLabelGenerator(GENDERS::get);
        firstName.setRequired(true);
        lastName.setRequired(true);
        notes.setMinRows(2);
        iban.addValueChangeListener(e -> iban.setHelperText(
                Validation.ibanChecksumIsValid(e.getValue()) ? null : "Achtung: IBAN-Prüfsumme ungültig"));
        svnr.addValueChangeListener(e -> svnr.setHelperText(
                Validation.isPlausibleAustrianSvnr(e.getValue()) ? null : "Achtung: SVNR-Format ungewöhnlich (10 Ziffern)"));
        iban.setValueChangeMode(com.vaadin.flow.data.value.ValueChangeMode.LAZY);
        svnr.setValueChangeMode(com.vaadin.flow.data.value.ValueChangeMode.LAZY);
        svnr.setAutocomplete(com.vaadin.flow.component.textfield.Autocomplete.OFF);
        iban.setAutocomplete(com.vaadin.flow.component.textfield.Autocomplete.OFF);

        FormLayout person = form(firstName, lastName, title, gender, street, zip, city, country);
        FormLayout contact = form(email, phone);
        status.setLabel("Status");
        status.setItems(MemberStatus.ALL);
        status.setItemLabelGenerator(MemberStatus::label);
        status.setHelperText("Gelöscht wird nur durch Root, und nur mit Status „Zum Löschen markiert“.");
        status.setValue(existing == null || existing.status() == null ? MemberStatus.NEW : existing.status());
        FormLayout membership = form(status, memberOfGVSC, memberNumber, joinedAt, sportId, defaultFunction);
        FormLayout notesForm = form(notes);
        notesForm.setColspan(notes, 2);
        add(section("Mitglied", person), section("Kontakt", contact), section("Mitgliedschaft", membership));
        if (existing != null && !existing.memberOfGVSC() && application.appliedAt() != null) {
            add(new Paragraph("Beitrittserklärung gesendet am "
                    + GermanUi.DAY.format(LocalDate.ofInstant(application.appliedAt(), java.time.ZoneId.of("Europe/Vienna")))
                    + " – nach Eingang der Unterschrift „Mitglied des Grazer VSC“ aktivieren."));
        }
        membershipType.setLabel("Mitgliedsart");
        membershipType.setItems("", "active", "supporting");
        membershipType.setItemLabelGenerator(MEMBERSHIP_TYPES::get);
        add(section("Beitrittserklärung Grazer VSC", form(membershipType, citizenship, mobile)),
                section("Gesetzliche:r Vertreter:in (nur bei Minderjährigen)", form(guardianFirstName, guardianLastName,
                        guardianStreet, guardianZip, guardianCity, guardianPhone, guardianMobile, guardianEmail)),
                section("Notizen", notesForm));
        if (canReadPrivate) {
            FormLayout privateForm = form(svnr, iban, birthDate, lastMedicalExamination);
            Paragraph hint = new Paragraph(this.canWritePrivate
                    ? "Nur für Berechtigte sichtbar, gespeichert getrennt von den übrigen Vereinsdaten."
                    : "Nur lesbar – zum Ändern fehlt die Berechtigung „Geschützte Daten ändern“.");
            hint.getStyle().set("font-size", "var(--lumo-font-size-s)");
            add(section("Geschützte Daten", hint, privateForm));
            for (Select<String> consent : List.of(consentDataTransfer, consentPhotos)) {
                consent.setItems("", "true", "false");
                consent.setItemLabelGenerator(CONSENTS::get);
            }
            consentDataTransfer.setLabel("Datenweitergabe an Fach-/Dachverbände");
            consentPhotos.setLabel("Foto- und Videoaufnahmen");
            add(section("Behinderung und Einwilligungen",
                    form(disabilityType, disabilityClass, disabilityCause, consentDataTransfer, consentPhotos)));
            for (Component field : new Component[] {svnr, iban, birthDate, lastMedicalExamination,
                    disabilityType, disabilityClass, disabilityCause, consentDataTransfer, consentPhotos}) {
                ((com.vaadin.flow.component.HasEnabled) field).setEnabled(this.canWritePrivate);
            }
        }

        fill(existing);
        fillApplication(application, health);

        Button save = new Button("Speichern", e -> {
            if (firstName.getValue().isBlank() || lastName.getValue().isBlank()) {
                Announcer.error("Vor- und Nachname sind Pflichtfelder.");
                (firstName.getValue().isBlank() ? firstName : lastName).focus();
                return;
            }
            MemberRecord record = record();
            MemberPrivate before = existing == null ? MemberPrivate.EMPTY : existing.privateData();
            boolean writePrivate = this.canWritePrivate && !record.privateData().equals(before);
            MemberHealth editedHealth = health();
            onSave.save(record, writePrivate, application(application.appliedAt()),
                    this.canWritePrivate && !editedHealth.equals(existingHealth) ? editedHealth : null);
        });
        save.addThemeVariants(ButtonVariant.LUMO_PRIMARY);
        Button cancel = new Button("Abbrechen", e -> close());
        getFooter().add(cancel, save);
        addOpenedChangeListener(e -> {
            if (e.isOpened()) {
                firstName.focus();
            }
        });
    }

    private static FormLayout form(Component... fields) {
        FormLayout form = new FormLayout(fields);
        form.setResponsiveSteps(new FormLayout.ResponsiveStep("0", 1), new FormLayout.ResponsiveStep("32rem", 2));
        return form;
    }

    private static Component section(String heading, Component... content) {
        var layout = new com.vaadin.flow.component.orderedlayout.VerticalLayout();
        layout.setPadding(false);
        layout.setSpacing(false);
        H3 h = new H3(heading);
        h.getStyle().set("margin", "var(--lumo-space-m) 0 var(--lumo-space-xs)");
        layout.add(h);
        layout.add(content);
        return layout;
    }

    private void fill(MemberRecord r) {
        if (r == null) {
            memberOfGVSC.setValue(true);
            joinedAt.setValue(LocalDate.now(java.time.ZoneId.of("Europe/Vienna")));
            gender.setValue("");
            return;
        }
        firstName.setValue(r.firstName());
        lastName.setValue(r.lastName());
        title.setValue(r.title());
        gender.setValue(GENDERS.containsKey(r.gender()) ? r.gender() : "");
        street.setValue(r.street());
        zip.setValue(r.zip());
        city.setValue(r.city());
        country.setValue(r.country());
        email.setValue(r.email());
        phone.setValue(r.phone());
        memberOfGVSC.setValue(r.memberOfGVSC());
        memberNumber.setValue(r.memberNumber());
        joinedAt.setValue(LocalDate.ofInstant(r.joinedAt(), java.time.ZoneId.of("Europe/Vienna")));
        sportId.setValue(r.sportId());
        defaultFunction.setValue(r.defaultFunction());
        notes.setValue(r.notes());
        if (canReadPrivate) {
            svnr.setValue(r.privateData().svnr());
            iban.setValue(r.privateData().iban());
            birthDate.setValue(day(r.privateData().birthDate()));
            lastMedicalExamination.setValue(day(r.privateData().lastMedicalExamination()));
        }
    }

    private MemberRecord record() {
        // Unknown gender values from imports are kept unless the field was changed.
        String genderValue = existing != null && !GENDERS.containsKey(existing.gender()) && "".equals(gender.getValue())
                ? existing.gender() : gender.getValue();
        Instant joined = joinedAt.getValue() == null
                ? (existing != null ? existing.joinedAt() : Instant.now())
                : keepTimeOfDay(joinedAt.getValue(), existing == null ? null : existing.joinedAt());
        MemberPrivate privateData = canWritePrivate
                ? new MemberPrivate(svnr.getValue().trim(), iban.getValue().trim(),
                        instant(birthDate.getValue()), instant(lastMedicalExamination.getValue()))
                : existing == null ? MemberPrivate.EMPTY : existing.privateData();
        return new MemberRecord(
                existing == null ? UUID.randomUUID().toString().toUpperCase() : existing.id(),
                firstName.getValue().trim(), lastName.getValue().trim(),
                street.getValue(), zip.getValue(), city.getValue(), country.getValue(),
                email.getValue(), phone.getValue(), memberNumber.getValue(), joined, notes.getValue(),
                genderValue, title.getValue(), sportId.getValue(), defaultFunction.getValue(),
                memberOfGVSC.getValue(), privateData, status.getValue());
    }

    private void fillApplication(MemberApplication a, MemberHealth h) {
        membershipType.setValue(MEMBERSHIP_TYPES.containsKey(a.membershipType()) ? a.membershipType() : "");
        citizenship.setValue(a.citizenship());
        mobile.setValue(a.mobile());
        guardianFirstName.setValue(a.guardianFirstName());
        guardianLastName.setValue(a.guardianLastName());
        guardianStreet.setValue(a.guardianStreet());
        guardianZip.setValue(a.guardianZip());
        guardianCity.setValue(a.guardianCity());
        guardianPhone.setValue(a.guardianPhone());
        guardianMobile.setValue(a.guardianMobile());
        guardianEmail.setValue(a.guardianEmail());
        disabilityType.setValue(h.disabilityType());
        disabilityClass.setValue(h.disabilityClass());
        disabilityCause.setValue(h.disabilityCause());
        consentDataTransfer.setValue(consentKey(h.consentDataTransfer()));
        consentPhotos.setValue(consentKey(h.consentPhotos()));
    }

    private MemberApplication application(Instant appliedAt) {
        return new MemberApplication(membershipType.getValue(), citizenship.getValue().trim(), mobile.getValue().trim(),
                guardianFirstName.getValue().trim(), guardianLastName.getValue().trim(),
                guardianStreet.getValue().trim(), guardianZip.getValue().trim(), guardianCity.getValue().trim(),
                guardianPhone.getValue().trim(), guardianMobile.getValue().trim(), guardianEmail.getValue().trim(),
                appliedAt);
    }

    private MemberHealth health() {
        return new MemberHealth(disabilityType.getValue().trim(), disabilityClass.getValue().trim(),
                disabilityCause.getValue().trim(), consent(consentDataTransfer.getValue()),
                consent(consentPhotos.getValue()));
    }

    private static String consentKey(Boolean consent) {
        return consent == null ? "" : consent.toString();
    }

    private static Boolean consent(String key) {
        return key == null || key.isEmpty() ? null : Boolean.valueOf(key);
    }

    /** Same day as before → keep the stored instant; otherwise midnight in Vienna. */
    private static Instant keepTimeOfDay(LocalDate day, Instant previous) {
        java.time.ZoneId vienna = java.time.ZoneId.of("Europe/Vienna");
        if (previous != null && LocalDate.ofInstant(previous, vienna).equals(day)) {
            return previous;
        }
        return day.atStartOfDay(vienna).toInstant();
    }

    /** Protected dates are days stored as midnight UTC (see MemberPrivate). */
    private static LocalDate day(Instant instant) {
        return instant == null ? null : LocalDate.ofInstant(instant, ZoneOffset.UTC);
    }

    private static Instant instant(LocalDate day) {
        return day == null ? null : day.atStartOfDay(ZoneOffset.UTC).toInstant();
    }
}
