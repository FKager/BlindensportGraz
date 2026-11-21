package it.a11y.blindensport.webui.xlsx;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

/** Cell text must stay valid XML, or Excel refuses the whole report. */
class XlsxPatchEscapeTest {
    @Test
    void escapesMarkup() {
        assertEquals("Müller &amp; Söhne &lt;Graz&gt;", XlsxPatch.escape("Müller & Söhne <Graz>"));
    }

    @Test
    void dropsControlCharactersXmlForbids() {
        assertEquals("AnnaMaria", XlsxPatch.escape("Anna\u000BMaria\u0000"));
    }

    @Test
    void keepsTabsLineBreaksAndEmoji() {
        assertEquals("a\tb\nc\r⚽️", XlsxPatch.escape("a\tb\nc\r⚽️"));
    }
}
