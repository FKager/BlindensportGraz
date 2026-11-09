package it.a11y.blindensport.webui.xlsx;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.function.UnaryOperator;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;

/**
 * Fills blank cells of a real .xlsx template's sheet XML — port of the app's
 * XLSXCellPatch.swift. A pristine template's target cells are self-closing
 * ({@code <c r="C3" s="65"/>}); the style attributes stay. Also copies a
 * template with patches and bundles finished files into one zip.
 */
public final class XlsxPatch {
    public static final String SHEET = "xl/worksheets/sheet1.xml";

    private XlsxPatch() {
    }

    public static String setText(String xml, String ref, String value) {
        return replaceBlankCell(xml, ref, attrs -> "<c r=\"" + ref + "\"" + attrs + " t=\"inlineStr\"><is><t>"
                + escape(value) + "</t></is></c>");
    }

    public static String setNumber(String xml, String ref, double value) {
        return replaceBlankCell(xml, ref, attrs -> "<c r=\"" + ref + "\"" + attrs + "><v>" + value + "</v></c>");
    }

    /** A whole number written as "3", not "3.0" (the app's TeilnehmerlisteExporter). */
    public static String setInteger(String xml, String ref, int value) {
        return replaceBlankCell(xml, ref, attrs -> "<c r=\"" + ref + "\"" + attrs + "><v>" + value + "</v></c>");
    }

    /** Only the cached {@code <v>} of a formula cell, for viewers that don't recalculate. */
    public static String setFormulaCachedValue(String xml, String ref, double value) {
        Matcher cell = Pattern.compile("<c r=\"" + ref + "\"[^>]*>.*?<v>[^<]*</v>", Pattern.DOTALL).matcher(xml);
        if (!cell.find()) {
            return xml;
        }
        String updated = cell.group().replaceFirst("<v>[^<]*</v>", "<v>" + value + "</v>");
        return xml.substring(0, cell.start()) + updated + xml.substring(cell.end());
    }

    public static String escape(String value) {
        return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
    }

    private static String replaceBlankCell(String xml, String ref, UnaryOperator<String> build) {
        Matcher cell = Pattern.compile("<c r=\"" + ref + "\"([^>]*)/>").matcher(xml);
        if (!cell.find()) {
            return xml;
        }
        return xml.substring(0, cell.start()) + build.apply(cell.group(1)) + xml.substring(cell.end());
    }

    /**
     * Copies the template zip on the class path, patching sheet1.xml and the
     * named entries; everything else stays byte for byte.
     */
    public static byte[] fillTemplate(String resource, Map<String, UnaryOperator<String>> entryPatches,
                                      UnaryOperator<String> sheetPatch) {
        try (InputStream template = XlsxPatch.class.getClassLoader().getResourceAsStream(resource)) {
            if (template == null) {
                throw new IllegalStateException("Formularvorlage fehlt: " + resource);
            }
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            try (ZipInputStream in = new ZipInputStream(template); ZipOutputStream zip = new ZipOutputStream(out)) {
                for (ZipEntry entry = in.getNextEntry(); entry != null; entry = in.getNextEntry()) {
                    byte[] data = in.readAllBytes();
                    UnaryOperator<String> patch = SHEET.equals(entry.getName()) ? sheetPatch
                            : entryPatches.get(entry.getName());
                    if (patch != null) {
                        data = patch.apply(new String(data, StandardCharsets.UTF_8)).getBytes(StandardCharsets.UTF_8);
                    }
                    zip.putNextEntry(new ZipEntry(entry.getName()));
                    zip.write(data);
                    zip.closeEntry();
                }
            }
            return out.toByteArray();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /** Several finished files as one zip, in the given order. */
    public static byte[] zip(Map<String, byte[]> files) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try (ZipOutputStream zip = new ZipOutputStream(out)) {
            for (Map.Entry<String, byte[]> file : files.entrySet()) {
                zip.putNextEntry(new ZipEntry(file.getKey()));
                zip.write(file.getValue());
                zip.closeEntry();
            }
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        return out.toByteArray();
    }

    /** Adds a file; a taken name gets "_2", "_3" … before ".xlsx" so nothing overwrites. */
    public static void addUnique(LinkedHashMap<String, byte[]> files, String name, byte[] content) {
        String unique = name;
        for (int i = 2; files.containsKey(unique); i++) {
            unique = name.replaceFirst("(\\.[A-Za-z0-9]+)?$", "_" + i + "$1");
        }
        files.put(unique, content);
    }
}
