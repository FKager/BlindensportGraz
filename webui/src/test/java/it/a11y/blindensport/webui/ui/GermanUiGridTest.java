package it.a11y.blindensport.webui.ui;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

/** Screen readers read the grid sorters as "Sort by Name" without this (axe check). */
class GermanUiGridTest {
    @Test
    void gridScreenReaderTextsAreGerman() {
        var i18n = GermanUi.gridI18n();
        assertEquals("Sortieren nach {column}", i18n.getSorter());
        assertEquals("Alle auswählen", i18n.getSelectAll());
        assertEquals("Zeile auswählen", i18n.getSelectRow());
    }
}
