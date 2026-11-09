package it.a11y.blindensport.webui.ui;

import com.github.mvysny.kaributesting.v10.MockVaadin;
import com.vaadin.flow.component.Component;
import com.vaadin.flow.component.HasText;
import com.vaadin.flow.component.UI;
import com.vaadin.flow.component.checkbox.Checkbox;
import com.vaadin.flow.component.checkbox.CheckboxGroup;
import com.vaadin.flow.component.grid.Grid;
import com.vaadin.flow.component.html.Anchor;
import com.vaadin.flow.component.html.Paragraph;
import com.vaadin.flow.component.radiobutton.RadioButtonGroup;
import com.vaadin.flow.component.select.Select;
import com.vaadin.flow.server.VaadinSession;
import io.quarkus.test.common.QuarkusTestResource;
import io.quarkus.test.junit.QuarkusTest;
import it.a11y.blindensport.webui.api.ReportsFixture;
import it.a11y.blindensport.webui.api.SupabaseMock;
import it.a11y.blindensport.webui.auth.AdminSessions;
import jakarta.inject.Inject;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** The Abrechnung page, driven server-side (Karibu) against the mocked Supabase of {@link ReportsFixture}. */
@QuarkusTest
@QuarkusTestResource(SupabaseMock.class)
class ReportsViewTest {
    private static final AtomicInteger CLIENT = new AtomicInteger();

    @Inject
    AdminSessions sessions;

    @BeforeEach
    void setUp() {
        ReportsFixture.stub(SupabaseMock.server);
        MockVaadin.setup();
    }

    @AfterEach
    void tearDown() {
        MockVaadin.tearDown();
    }

    private ReportsView open(String email) {
        String token = sessions.signIn(email, "richtig", "10.8.0." + CLIENT.incrementAndGet());
        VaadinSession.getCurrent().setAttribute(UiSession.class.getName() + ".token", token);
        ReportsView view = new ReportsView(sessions);
        UI.getCurrent().add(view);
        view.refresh();
        return view;
    }

    private static Stream<Component> all(Component root) {
        return Stream.concat(Stream.of(root), root.getChildren().flatMap(ReportsViewTest::all));
    }

    private static List<String> texts(Component root, Class<? extends HasText> type) {
        List<String> result = new ArrayList<>();
        all(root).filter(type::isInstance).filter(Component::isVisible)
                .forEach(c -> result.add(((HasText) c).getText()));
        return result;
    }

    @SuppressWarnings("unchecked")
    private static <T extends Component> T find(Component root, Class<T> type, String label) {
        return (T) all(root).filter(type::isInstance)
                .filter(c -> label.equals(c.getElement().getProperty("label")))
                .findFirst().orElseThrow(() -> new AssertionError("no " + label));
    }

    @Test
    void monthShowsHonorariaAndForms() {
        ReportsView view = open("admin@example.org");
        find(view, Select.class, "Jahr").setValue(2026);
        find(view, Select.class, "Monat").setValue(3);

        List<String> paragraphs = texts(view, Paragraph.class);
        assertTrue(paragraphs.contains("Betrifft: Torball. Zeitraum: 03.03.2026 bis 03.03.2026 (1 Training). Ort: Graz."),
                paragraphs.toString());
        assertTrue(paragraphs.stream().anyMatch(p -> p.startsWith("Gesamt: ") && p.endsWith("45,00 · 1 Person")),
                paragraphs.toString());
        assertEquals(List.of("KostZ-Formular herunterladen",
                        "Alle PRAE-Formulare mit Darstellung herunterladen (ZIP, 1 Formular)",
                        "Sammelabrechnung herunterladen (ZIP)"), texts(view, Anchor.class));
        Grid<?> grid = all(view).filter(Grid.class::isInstance).map(Grid.class::cast).findFirst().orElseThrow();
        assertEquals(1, grid.getGenericDataView().getItems().count());
        assertEquals(4, grid.getColumns().size(), "Name, Betrag, Hinweise and the PRAE link per person");
        assertFalse(find(view, Checkbox.class, "TeilnehmerInnenliste Sportler").isVisible(),
                "trainings file no TeilnehmerInnenliste");
    }

    @Test
    void tournamentShowsBothParticipantLists() {
        ReportsView view = open("admin@example.org");
        @SuppressWarnings("unchecked")
        RadioButtonGroup<String> scope = find(view, RadioButtonGroup.class, "Abrechnen für");
        scope.setValue(ReportsView.TOURNAMENT);

        List<String> paragraphs = texts(view, Paragraph.class);
        assertTrue(paragraphs.contains("Betrifft: Cup/Prag. Zeitraum: 29.05.2026 bis 30.05.2026 (2 Tage). "
                + "Ort: Prag, Tschechien."), paragraphs.toString());
        List<String> anchors = texts(view, Anchor.class);
        assertTrue(anchors.contains("TeilnehmerInnenliste Sportler herunterladen (1 Person)"), anchors.toString());
        assertTrue(anchors.contains("TeilnehmerInnenliste Helfer herunterladen (1 Person)"), anchors.toString());
        CheckboxGroup<?> prae = find(view, CheckboxGroup.class, "PRAE (Formular + Darstellung)");
        assertEquals(1, prae.getValue().size(), "everyone is preselected");
    }

    @Test
    void withoutPrivateReadThereAreNoPraeFiles() {
        ReportsView view = open("kassa@example.org");
        find(view, Select.class, "Jahr").setValue(2026);
        find(view, Select.class, "Monat").setValue(3);

        List<String> anchors = texts(view, Anchor.class);
        assertTrue(anchors.stream().noneMatch(a -> a.contains("PRAE")), anchors.toString());
        assertTrue(texts(view, Paragraph.class).stream().anyMatch(p -> p.startsWith("PRAE-Formulare enthalten SVNR")));
        assertFalse(find(view, CheckboxGroup.class, "PRAE (Formular + Darstellung)").isVisible());
    }
}
