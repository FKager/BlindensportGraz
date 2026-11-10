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

/** The Trainingsfrequenzliste page, driven server-side (Karibu) against the mocked Supabase of {@link ReportsFixture}. */
@QuarkusTest
@QuarkusTestResource(SupabaseMock.class)
class TrainingsfrequenzlisteViewTest {
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

    private TrainingsfrequenzlisteView open(String email) {
        String token = sessions.signIn(email, "richtig", "10.8.0." + CLIENT.incrementAndGet());
        VaadinSession.getCurrent().setAttribute(UiSession.class.getName() + ".token", token);
        TrainingsfrequenzlisteView view = new TrainingsfrequenzlisteView(sessions);
        UI.getCurrent().add(view);
        view.refresh();
        return view;
    }

    private static Stream<Component> all(Component root) {
        return Stream.concat(Stream.of(root), root.getChildren().flatMap(TrainingsfrequenzlisteViewTest::all));
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
    void firstHalfShowsRosterAndDownload() {
        TrainingsfrequenzlisteView view = open("kassa@example.org");
        assertEquals("Torball", find(view, Select.class, "Sportart").getValue());
        find(view, Select.class, "Jahr").setValue(2026);
        find(view, Select.class, "Zeitraum").setValue(1);

        List<String> paragraphs = texts(view, Paragraph.class);
        assertTrue(paragraphs.contains("1 Trainingstag · 2 Personen · Teams: Torball Damen"), paragraphs.toString());
        assertEquals(List.of("Trainingsfrequenzliste herunterladen"), texts(view, Anchor.class));
        Grid<?> grid = all(view).filter(Grid.class::isInstance).map(Grid.class::cast).findFirst().orElseThrow();
        assertEquals(2, grid.getGenericDataView().getItems().count());
    }

    @Test
    void secondHalfHasNoTrainings() {
        TrainingsfrequenzlisteView view = open("admin@example.org");
        find(view, Select.class, "Jahr").setValue(2026);
        find(view, Select.class, "Zeitraum").setValue(2);

        assertTrue(texts(view, Paragraph.class).contains("Keine Trainings in diesem Zeitraum für diese Sportart."));
        assertTrue(texts(view, Anchor.class).isEmpty());
        assertFalse(all(view).anyMatch(Grid.class::isInstance));
    }
}
