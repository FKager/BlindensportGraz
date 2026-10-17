package it.a11y.blindensport.webadmin.ui;

import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.button.ButtonVariant;
import com.vaadin.flow.component.combobox.ComboBox;
import com.vaadin.flow.component.dialog.Dialog;
import com.vaadin.flow.component.html.H3;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.orderedlayout.FlexComponent;
import com.vaadin.flow.component.orderedlayout.HorizontalLayout;
import com.vaadin.flow.component.orderedlayout.VerticalLayout;
import com.vaadin.flow.component.select.Select;
import it.a11y.blindensport.webadmin.accounts.AccountService;
import it.a11y.blindensport.webadmin.accounts.AccountService.Account;
import it.a11y.blindensport.webadmin.auth.AdminSession;
import it.a11y.blindensport.webadmin.auth.Permission;
import it.a11y.blindensport.webadmin.members.MemberRecord;

import java.util.List;

/**
 * Everything an admin can do with one account, as plainly labelled buttons
 * grouped under headings (Freigabe, Rolle, Konto) — easier with a screen
 * reader than nested menus.
 */
class AccountDialog extends Dialog {
    AccountDialog(Account account, String status, List<MemberRecord> roster, AdminSession admin, AccountsView view) {
        setHeaderTitle(account.displayName());
        setWidth("min(42rem, 100vw)");
        boolean self = account.id().equals(admin.userId());
        boolean isRoot = "root".equals(account.role());

        VerticalLayout content = new VerticalLayout();
        content.setPadding(false);
        content.add(new Paragraph(account.email() + " · Rolle: " + AccountsView.roleLabel(account.role())
                + (account.createdAt() == null ? "" : " · Konto seit "
                + GermanUi.DAY.format(account.createdAt().atZone(java.time.ZoneId.of("Europe/Vienna"))))));
        content.add(new Paragraph(status));

        if (admin.can(Permission.USERS_APPROVE)) {
            content.add(heading("Freigabe"));
            if (account.approval() != null) {
                Button revoke = new Button("Freigabe entziehen", e -> GermanUi.confirm(
                        "Freigabe von " + account.displayName() + " entziehen?",
                        "Das Konto sieht danach nur noch die Termine, bis es wieder freigegeben wird.",
                        "Freigabe entziehen", () -> {
                            if (view.perform("Freigabe entziehen", "Freigabe entzogen.",
                                    () -> view.service().revokeApproval(account.id()))) {
                                close();
                            }
                        }));
                revoke.addThemeVariants(ButtonVariant.LUMO_ERROR);
                content.add(revoke);
            } else {
                var suggestion = AccountService.suggest(account, roster);
                suggestion.ifPresent(s -> {
                    Button approveSuggested = new Button("Freigeben als " + s.member().fullName(), e -> {
                        if (view.perform("Freigeben", account.displayName() + " freigegeben.",
                                () -> view.service().approve(account.id(), s.member().id()))) {
                            close();
                        }
                    });
                    approveSuggested.addThemeVariants(ButtonVariant.LUMO_PRIMARY);
                    content.add(approveSuggested);
                });
                ComboBox<MemberRecord> member = new ComboBox<>("Anderes Mitglied auswählen");
                member.setItems(roster);
                member.setItemLabelGenerator(m -> m.lastName() + ", " + m.firstName()
                        + (m.email().isBlank() ? "" : " (" + m.email() + ")"));
                member.setWidth("24rem");
                Button approvePicked = new Button("Als ausgewähltes Mitglied freigeben", e -> {
                    if (member.getValue() == null) {
                        Announcer.error("Bitte zuerst ein Mitglied auswählen.");
                        member.focus();
                        return;
                    }
                    if (view.perform("Freigeben", account.displayName() + " freigegeben als "
                            + member.getValue().fullName() + ".",
                            () -> view.service().approve(account.id(), member.getValue().id()))) {
                        close();
                    }
                });
                HorizontalLayout pick = new HorizontalLayout(member, approvePicked);
                pick.setDefaultVerticalComponentAlignment(FlexComponent.Alignment.BASELINE);
                pick.setWrap(true);
                Button code = new Button("Aktivierungscode erstellen", e -> {
                    String memberId = suggestion.map(s -> s.member().id()).orElse(null);
                    String created = view.attempt("Aktivierungscode erstellen",
                            () -> view.service().createActivationCode(account.id(), memberId));
                    if (created != null) {
                        showCode(account, created);
                    }
                });
                content.add(pick, code);
            }
        }

        if (admin.can(Permission.ROLES_ASSIGN) && !self) {
            content.add(heading("Rolle"));
            Select<String> role = new Select<>();
            role.setLabel("Rolle");
            role.setItems(AccountService.ROLES);
            role.setItemLabelGenerator(AccountsView::roleLabel);
            role.setValue(account.role());
            Button saveRole = new Button("Rolle speichern", e -> {
                if (role.getValue() == null || role.getValue().equals(account.role())) {
                    Announcer.error("Bitte eine andere Rolle auswählen.");
                    return;
                }
                if (view.perform("Rolle ändern", "Rolle von " + account.displayName() + " ist jetzt "
                        + AccountsView.roleLabel(role.getValue()) + ".",
                        () -> view.service().setRole(account.id(), role.getValue()))) {
                    close();
                }
            });
            HorizontalLayout roleRow = new HorizontalLayout(role, saveRole);
            roleRow.setDefaultVerticalComponentAlignment(FlexComponent.Alignment.BASELINE);
            content.add(roleRow);

            content.add(heading("Konto"));
            if (isRoot) {
                content.add(new Paragraph("Root-Konten können nicht gesperrt oder gelöscht werden – zuerst die Rolle ändern."));
            } else {
                Button block = account.blocked()
                        ? new Button("Entsperren", e -> {
                            if (view.perform("Entsperren", account.displayName() + " entsperrt.",
                                    () -> view.service().setBlocked(account.id(), false))) {
                                close();
                            }
                        })
                        : new Button("Sperren …", e -> GermanUi.confirm(account.displayName() + " sperren?",
                                "Das Konto wird auf allen Geräten abgemeldet und kann sich nicht mehr anmelden, bis "
                                        + "es entsperrt wird. Der Kalender-Link wird ungültig.",
                                "Sperren", () -> {
                                    if (view.perform("Sperren", account.displayName() + " gesperrt.",
                                            () -> view.service().setBlocked(account.id(), true))) {
                                        close();
                                    }
                                }));
                Button delete = new Button("Konto löschen …", e -> GermanUi.confirm(
                        account.displayName() + " endgültig löschen?",
                        "Das App-Konto, seine Rolle, Freigabe, Teilnahmen und Teamzuordnungen werden gelöscht. "
                                + "Das kann nicht rückgängig gemacht werden. Der Eintrag in der Mitgliederliste bleibt.",
                        "Konto löschen", () -> {
                            if (view.perform("Löschen", account.displayName() + " gelöscht.",
                                    () -> view.service().delete(account.id()))) {
                                close();
                            }
                        }));
                delete.addThemeVariants(ButtonVariant.LUMO_ERROR);
                content.add(new HorizontalLayout(block, delete));
            }
        } else if (self) {
            content.add(new Paragraph("Das ist Ihr eigenes Konto – Rolle, Sperre und Löschen gehen nur über ein anderes Root-Konto."));
        }

        add(content);
        getFooter().add(new Button("Schließen", e -> close()));
    }

    private static H3 heading(String text) {
        H3 h = new H3(text);
        h.getStyle().set("margin", "var(--lumo-space-m) 0 0");
        return h;
    }

    /** Shown once; the database only keeps a hash. */
    private void showCode(Account account, String code) {
        Dialog dialog = new Dialog();
        dialog.setHeaderTitle("Aktivierungscode");
        Paragraph text = new Paragraph("Code für " + account.displayName() + ": " + code);
        text.getStyle().set("font-size", "var(--lumo-font-size-xl)").set("font-family", "monospace");
        dialog.add(text, new Paragraph("Bitte persönlich weitergeben. Der Code wird nur jetzt angezeigt, gilt 14 Tage "
                + "und kann nur in diesem Konto eingelöst werden (App: Account → Aktivierungscode einlösen)."));
        dialog.getFooter().add(new Button("Schließen", e -> dialog.close()));
        dialog.open();
    }
}
