package it.a11y.blindensport.webui.club;

import org.apache.pdfbox.Loader;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.text.PDFTextStripper;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

/**
 * Plain text of an uploaded document, so an MCP client can read an invitation:
 * PDF (PDFBox), Word .docx (its document.xml) and .txt. Other types (images,
 * Excel, old .doc) have none here — the client gets the download link.
 */
public final class DocumentText {
    /** Longest text returned; the rest is cut off. */
    public static final int MAX_CHARS = 60_000;
    private static final Pattern DOCX_TOKEN = Pattern.compile("<w:t(?:\\s[^>]*)?>([^<]*)</w:t>|</w:p>|<w:tab/>|<w:br/>");

    private DocumentText() {
    }

    public static Optional<String> of(String fileName, byte[] content) {
        try {
            String text = switch (TournamentDocuments.extension(fileName)) {
                case "pdf" -> pdf(content);
                case "docx" -> docx(content);
                case "txt" -> new String(content, StandardCharsets.UTF_8);
                default -> null;
            };
            if (text == null || text.isBlank()) {
                return Optional.empty();
            }
            text = text.strip();
            return Optional.of(text.length() > MAX_CHARS ? text.substring(0, MAX_CHARS) + "\n[… gekürzt]" : text);
        } catch (IOException | RuntimeException e) {
            return Optional.empty();
        }
    }

    private static String pdf(byte[] content) throws IOException {
        try (PDDocument document = Loader.loadPDF(content)) {
            return new PDFTextStripper().getText(document);
        }
    }

    static String docx(byte[] content) throws IOException {
        try (ZipInputStream zip = new ZipInputStream(new ByteArrayInputStream(content))) {
            for (ZipEntry entry; (entry = zip.getNextEntry()) != null; ) {
                if (!"word/document.xml".equals(entry.getName())) {
                    continue;
                }
                String xml = new String(zip.readNBytes(32 * 1024 * 1024), StandardCharsets.UTF_8);
                StringBuilder text = new StringBuilder();
                Matcher m = DOCX_TOKEN.matcher(xml);
                while (m.find()) {
                    if (m.group(1) != null) {
                        text.append(unescape(m.group(1)));
                    } else if (m.group().equals("<w:tab/>")) {
                        text.append('\t');
                    } else {
                        text.append('\n');
                    }
                }
                return text.toString().replaceAll("\n{3,}", "\n\n");
            }
        }
        return null;
    }

    private static String unescape(String s) {
        return s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"")
                .replace("&apos;", "'").replace("&amp;", "&");
    }
}
