package it.a11y.blindensport.webui.club;

import org.junit.jupiter.api.Test;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class TournamentDocumentsTest {
    @Test
    void contentTypesFollowTheExtensionLikeTheApp() {
        assertEquals("application/pdf", TournamentDocuments.contentType("Einladung.PDF"));
        assertEquals("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                TournamentDocuments.contentType("Spielplan.xlsx"));
        assertEquals("image/jpeg", TournamentDocuments.contentType("Halle.jpeg"));
        assertThrows(IllegalArgumentException.class, () -> TournamentDocuments.contentType("tool.exe"));
        assertThrows(IllegalArgumentException.class, () -> TournamentDocuments.contentType("ohne-endung"));
    }

    @Test
    void onlyTheBareFileNameIsKept() {
        assertEquals("Einladung.pdf", TournamentDocuments.cleanName("C:\\Users\\x\\Einladung.pdf"));
        assertEquals("plan.xlsx", TournamentDocuments.cleanName("../../plan.xlsx"));
        assertThrows(IllegalArgumentException.class, () -> TournamentDocuments.cleanName("  "));
        assertThrows(IllegalArgumentException.class, () -> TournamentDocuments.cleanName("dir/.pdf"));
    }

    @Test
    void wordTextKeepsParagraphs() throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (ZipOutputStream zip = new ZipOutputStream(bytes)) {
            zip.putNextEntry(new ZipEntry("word/document.xml"));
            zip.write(("<w:document><w:body><w:p><w:r><w:t>Einladung</w:t></w:r></w:p>"
                    + "<w:p><w:r><w:t xml:space=\"preserve\">Alpencup &amp; </w:t></w:r><w:r><w:t>Graz</w:t></w:r></w:p>"
                    + "</w:body></w:document>").getBytes(StandardCharsets.UTF_8));
        }
        assertEquals("Einladung\nAlpencup & Graz", DocumentText.of("a.docx", bytes.toByteArray()).orElseThrow());
    }

    @Test
    void imagesHaveNoText() {
        assertTrue(DocumentText.of("a.png", new byte[]{1, 2, 3}).isEmpty());
        assertTrue(DocumentText.of("a.pdf", "kein pdf".getBytes(StandardCharsets.UTF_8)).isEmpty());
    }
}
