package it.a11y.blindensport.webui.club;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;

class ClubFunctionsTest {
    @Test
    void theFourFunctionsAreShownInBoardOrder() {
        assertEquals(List.of("Obmann", "Obmann Stellvertreter", "Kassier", "Schriftführer"),
                List.copyOf(ClubFunctions.LABELS.values()));
    }

    @Test
    void theKeysAreTheDatabaseValues() {
        assertEquals(List.of("obmann", "obmann_stellvertreter", "kassier", "schriftfuehrer"),
                List.copyOf(ClubFunctions.LABELS.keySet()));
    }
}
