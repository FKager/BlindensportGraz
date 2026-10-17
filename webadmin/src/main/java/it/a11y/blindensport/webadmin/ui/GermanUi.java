package it.a11y.blindensport.webadmin.ui;

import com.vaadin.flow.component.Component;
import com.vaadin.flow.component.confirmdialog.ConfirmDialog;
import com.vaadin.flow.component.datepicker.DatePicker;
import com.vaadin.flow.component.datetimepicker.DateTimePicker;
import com.vaadin.flow.component.upload.UploadI18N;

import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Locale;

/** German texts and formats for Vaadin's built-in components (their defaults are English). */
public final class GermanUi {
    public static final Locale LOCALE = Locale.GERMANY;
    public static final DateTimeFormatter DAY = DateTimeFormatter.ofPattern("dd.MM.yyyy", LOCALE);
    public static final DateTimeFormatter DAY_TIME = DateTimeFormatter.ofPattern("dd.MM.yyyy, HH:mm", LOCALE);

    private GermanUi() {
    }

    public static DatePicker.DatePickerI18n datePickerI18n() {
        return new DatePicker.DatePickerI18n()
                .setMonthNames(List.of("Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August",
                        "September", "Oktober", "November", "Dezember"))
                .setWeekdays(List.of("Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"))
                .setWeekdaysShort(List.of("So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"))
                .setFirstDayOfWeek(1)
                .setToday("Heute")
                .setCancel("Abbrechen")
                .setDateFormat("dd.MM.yyyy");
    }

    /** A date field in German (dd.MM.yyyy, Monday first). */
    public static DatePicker datePicker(String label) {
        DatePicker picker = new DatePicker(label);
        picker.setLocale(LOCALE);
        picker.setI18n(datePickerI18n());
        picker.setClearButtonVisible(true);
        picker.setHelperText("Format TT.MM.JJJJ");
        return picker;
    }

    public static DateTimePicker dateTimePicker(String label) {
        DateTimePicker picker = new DateTimePicker(label);
        picker.setLocale(LOCALE);
        picker.setDatePickerI18n(datePickerI18n());
        picker.setDateAriaLabel(label + " – Datum");
        picker.setTimeAriaLabel(label + " – Uhrzeit");
        return picker;
    }

    public static UploadI18N uploadI18n(String addFiles, String dropFiles) {
        UploadI18N i18n = new UploadI18N();
        i18n.setAddFiles(new UploadI18N.AddFiles().setOne(addFiles).setMany(addFiles));
        i18n.setDropFiles(new UploadI18N.DropFiles().setOne(dropFiles).setMany(dropFiles));
        i18n.setError(new UploadI18N.Error()
                .setTooManyFiles("Bitte nur eine Datei.")
                .setFileIsTooBig("Die Datei ist zu groß.")
                .setIncorrectFileType("Falscher Dateityp."));
        i18n.setUploading(new UploadI18N.Uploading()
                .setStatus(new UploadI18N.Uploading.Status()
                        .setConnecting("Verbinde …").setStalled("Angehalten").setProcessing("Verarbeite …")
                        .setHeld("Wartet"))
                .setRemainingTime(new UploadI18N.Uploading.RemainingTime()
                        .setPrefix("Verbleibend: ").setUnknown("Restzeit unbekannt"))
                .setError(new UploadI18N.Uploading.Error()
                        .setServerUnavailable("Server nicht erreichbar")
                        .setUnexpectedServerError("Serverfehler")
                        .setForbidden("Nicht erlaubt")));
        i18n.setUnits(new UploadI18N.Units(List.of("B", "kB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB")));
        return i18n;
    }

    /**
     * "Really do X?" — the confirm button names the action. Cancel has focus
     * first, so Enter never deletes by accident.
     */
    public static void confirm(String header, String text, String confirmLabel, Runnable onConfirm) {
        ConfirmDialog dialog = new ConfirmDialog();
        dialog.setHeader(header);
        dialog.setText(text);
        dialog.setCancelable(true);
        dialog.setCancelText("Abbrechen");
        dialog.setConfirmText(confirmLabel);
        dialog.setConfirmButtonTheme("error primary");
        dialog.addConfirmListener(e -> onConfirm.run());
        dialog.open();
    }

    /** aria-label for icon-free buttons that repeat in every row ("Bearbeiten" → "Anna Muster bearbeiten"). */
    public static <T extends Component> T label(T component, String ariaLabel) {
        component.getElement().setAttribute("aria-label", ariaLabel);
        return component;
    }
}
