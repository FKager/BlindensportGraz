package it.a11y.blindensport.webui.ui;

import com.vaadin.flow.component.button.Button;
import com.vaadin.flow.component.button.ButtonVariant;
import com.vaadin.flow.component.checkbox.Checkbox;
import com.vaadin.flow.component.dialog.Dialog;
import com.vaadin.flow.component.grid.Grid;
import com.vaadin.flow.component.html.ListItem;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.html.UnorderedList;
import com.vaadin.flow.component.orderedlayout.HorizontalLayout;
import com.vaadin.flow.router.PageTitle;
import com.vaadin.flow.router.Route;
import it.a11y.blindensport.webui.auth.AdminSession;
import it.a11y.blindensport.webui.auth.AdminSessions;
import it.a11y.blindensport.webui.auth.Permission;
import it.a11y.blindensport.webui.members.ChangeRequestStore;
import it.a11y.blindensport.webui.members.ChangeRequestStore.ChangeRequest;
import it.a11y.blindensport.webui.members.MemberApplication;
import it.a11y.blindensport.webui.members.MemberHealth;
import it.a11y.blindensport.webui.members.MemberPrivate;
import it.a11y.blindensport.webui.members.MemberRecord;
import it.a11y.blindensport.webui.members.MemberStore;
import jakarta.inject.Inject;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.function.Function;
import java.util.stream.Collectors;

/** Review members' proposed changes to their own entry (Annehmen / Ablehnen), like the app's Änderungsanträge. */
@Route(value = "aenderungsantraege", layout = MainLayout.class)
@PageTitle("Änderungsanträge – Blindensport Graz")
@RequiresPermission(Permission.MEMBERS_MANAGE)
public class ChangeRequestsView extends AdminView {
    private static final Map<String, String> STATUS = Map.of(
            ChangeRequestStore.PENDING, "Offen", ChangeRequestStore.APPROVED, "Angenommen",
            ChangeRequestStore.REJECTED, "Abgelehnt");

    private final Grid<ChangeRequest> grid = new Grid<>();
    private final Checkbox showDecided = new Checkbox("Auch entschiedene Anträge zeigen");
    private Map<String, MemberRecord> members = Map.of();
    private List<ChangeRequest> requests = List.of();

    @Inject
    public ChangeRequestsView(AdminSessions sessions) {
        super(sessions, "Änderungsanträge");
        setSizeFull();
        showDecided.addValueChangeListener(e -> applyFilter());

        grid.addColumn(r -> memberName(r.memberId())).setHeader("Mitglied").setRowHeader(true).setAutoWidth(true);
        grid.addColumn(r -> format(r.requestedAt())).setHeader("Beantragt am").setAutoWidth(true);
        grid.addColumn(r -> STATUS.getOrDefault(r.status(), r.status())).setHeader("Status").setAutoWidth(true);
        grid.addComponentColumn(r -> GermanUi.label(new Button("Ansehen", e -> openDetail(r)),
                "Antrag von " + memberName(r.memberId()) + " ansehen")).setHeader("Aktionen").setAutoWidth(true);
        grid.setEmptyStateText("Keine offenen Änderungsanträge.");
        grid.getElement().setAttribute("aria-label", "Änderungsanträge");
        grid.setSizeFull();
        add(new Paragraph("Mitglieder können in der App Änderungen ihrer eigenen Daten beantragen."), showDecided, grid);
        setFlexGrow(1, grid);
    }

    @Override
    protected void refresh() {
        AdminSession admin = session();
        members = new MemberStore(admin.db()).all(admin.can(Permission.MEMBERS_PRIVATE_READ)).stream()
                .collect(Collectors.toMap(MemberRecord::id, Function.identity()));
        requests = new ChangeRequestStore(admin.db()).all();
        applyFilter();
    }

    private void applyFilter() {
        grid.setItems(showDecided.getValue() ? requests : requests.stream().filter(ChangeRequest::isPending).toList());
    }

    private String memberName(String memberId) {
        MemberRecord m = members.get(memberId);
        return m == null ? "(gelöschtes Mitglied)" : m.fullName();
    }

    private void openDetail(ChangeRequest request) {
        AdminSession admin = session();
        MemberRecord member = members.get(request.memberId());
        boolean canPrivate = admin.can(Permission.MEMBERS_PRIVATE_WRITE);
        Optional<MemberPrivate> proposal = request.isPending() && canPrivate
                ? Optional.ofNullable(attempt("Laden", () -> new ChangeRequestStore(admin.db())
                        .privateProposal(request.memberId()).orElse(null)))
                : Optional.empty();
        MemberHealth healthProposal = proposal.isPresent()
                ? attempt("Laden", () -> new ChangeRequestStore(admin.db())
                        .healthProposal(request.memberId()).orElse(null))
                : null;
        MemberApplication application = member == null ? MemberApplication.EMPTY
                : Objects.requireNonNullElse(
                        attempt("Laden", () -> new MemberStore(admin.db()).application(request.memberId())),
                        MemberApplication.EMPTY);
        MemberHealth health = healthProposal == null ? MemberHealth.EMPTY
                : Objects.requireNonNullElse(
                        attempt("Laden", () -> new MemberStore(admin.db()).health(request.memberId())),
                        MemberHealth.EMPTY);

        Dialog dialog = new Dialog();
        dialog.setHeaderTitle("Änderungsantrag: " + memberName(request.memberId()));
        dialog.setWidth("min(40rem, 100vw)");
        if (member == null) {
            dialog.add(new Paragraph("Zugehöriges Mitglied nicht gefunden – vermutlich zwischenzeitlich gelöscht."));
        } else {
            List<String> changes = diffs(member, application, request, proposal.orElse(null));
            if (healthProposal != null) {
                changes = new ArrayList<>(changes);
                changes.addAll(healthDiffs(health, healthProposal));
            }
            if (changes.isEmpty()) {
                dialog.add(new Paragraph("Keine Unterschiede mehr zu den aktuellen Vereinsdaten."));
            } else {
                UnorderedList list = new UnorderedList();
                changes.forEach(c -> list.add(new ListItem(c)));
                dialog.add(new Paragraph("Änderungen:"), list);
            }
        }
        dialog.add(new Paragraph("Beantragt am " + format(request.requestedAt())
                + (request.reviewedAt() != null ? " · entschieden am " + format(request.reviewedAt()) : "")));
        if (!request.isPending()) {
            dialog.add(new Paragraph("Status: " + STATUS.getOrDefault(request.status(), request.status())));
        }

        Button close = new Button("Schließen", e -> dialog.close());
        HorizontalLayout footer = new HorizontalLayout(close);
        if (request.isPending() && member != null) {
            Button approve = new Button("Annehmen", e -> {
                if (attempt("Annehmen", () -> new ChangeRequestStore(session().db())
                        .approve(request, proposal.isPresent(), session().userId()))) {
                    dialog.close();
                    Announcer.success("Antrag von " + member.fullName() + " angenommen.");
                    attempt("Laden", this::refresh);
                }
            });
            approve.addThemeVariants(ButtonVariant.LUMO_PRIMARY, ButtonVariant.LUMO_SUCCESS);
            Button reject = new Button("Ablehnen", e -> {
                if (attempt("Ablehnen", () -> new ChangeRequestStore(session().db())
                        .reject(request, canPrivate, session().userId()))) {
                    dialog.close();
                    Announcer.success("Antrag von " + member.fullName() + " abgelehnt.");
                    attempt("Laden", this::refresh);
                }
            });
            reject.addThemeVariants(ButtonVariant.LUMO_ERROR);
            footer.add(reject, approve);
        }
        dialog.getFooter().add(footer);
        dialog.open();
    }

    /** "Ort: von Graz zu Wien" lines, like the app's diff (spoken that way by VoiceOver too). */
    static List<String> diffs(MemberRecord m, MemberApplication application, ChangeRequest r, MemberPrivate proposal) {
        Map<String, String> current = new java.util.HashMap<>(Map.ofEntries(
                Map.entry("first_name", m.firstName()), Map.entry("last_name", m.lastName()),
                Map.entry("title", m.title()), Map.entry("gender", m.gender()), Map.entry("street", m.street()),
                Map.entry("zip", m.zip()), Map.entry("city", m.city()), Map.entry("country", m.country()),
                Map.entry("email", m.email()), Map.entry("phone", m.phone()), Map.entry("sport_id", m.sportId())));
        current.putAll(application.columns());
        List<String> out = new ArrayList<>();
        ChangeRequestStore.FIELD_LABELS.forEach((key, label) -> {
            String old = current.getOrDefault(key, "");
            String proposed = r.fields().getOrDefault(key, "");
            if ("membership_type".equals(key)) {
                old = MemberApplication.membershipTypeLabel(old);
                proposed = MemberApplication.membershipTypeLabel(proposed);
            }
            add(out, label, old, proposed);
        });
        if (proposal != null) {
            MemberPrivate stored = m.privateData();
            add(out, "SVNR", stored.svnr(), proposal.svnr());
            add(out, "IBAN", stored.iban(), proposal.iban());
            add(out, "Geburtsdatum", day(stored.birthDate()), day(proposal.birthDate()));
            add(out, "Letzte sportärztl. Untersuchung", day(stored.lastMedicalExamination()),
                    day(proposal.lastMedicalExamination()));
        }
        return out;
    }

    /** Disability/consent lines of a protected proposal. */
    static List<String> healthDiffs(MemberHealth stored, MemberHealth proposal) {
        List<String> out = new ArrayList<>();
        add(out, "Art der Behinderung", stored.disabilityType(), proposal.disabilityType());
        add(out, "Behinderungsklasse", stored.disabilityClass(), proposal.disabilityClass());
        add(out, "Behinderung durch", stored.disabilityCause(), proposal.disabilityCause());
        add(out, "Datenweitergabe", MemberHealth.consentLabel(stored.consentDataTransfer()),
                MemberHealth.consentLabel(proposal.consentDataTransfer()));
        add(out, "Foto/Video", MemberHealth.consentLabel(stored.consentPhotos()),
                MemberHealth.consentLabel(proposal.consentPhotos()));
        return out;
    }

    private static void add(List<String> out, String label, String oldValue, String newValue) {
        if (!Objects.equals(oldValue, newValue)) {
            out.add(label + ": von " + (oldValue.isEmpty() ? "–" : oldValue) + " zu " + (newValue.isEmpty() ? "–" : newValue));
        }
    }

    private static String day(Instant instant) {
        return instant == null ? "" : GermanUi.DAY.format(LocalDate.ofInstant(instant, ZoneOffset.UTC));
    }

    private static String format(Instant instant) {
        return instant == null ? "–" : GermanUi.DAY_TIME.format(instant.atZone(ZoneId.of("Europe/Vienna")));
    }
}
