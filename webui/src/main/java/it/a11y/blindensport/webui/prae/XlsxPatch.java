package it.a11y.blindensport.webui.prae;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Fills blank cells of a real .xlsx template's sheet XML — port of the app's
 * XLSXCellPatch.swift. A pristine template's target cells are self-closing
 * ({@code <c r="C3" s="65"/>}); the style attributes stay.
 */
final class XlsxPatch {
    private XlsxPatch() {
    }

    static String setText(String xml, String ref, String value) {
        return replaceBlankCell(xml, ref, attrs -> "<c r=\"" + ref + "\"" + attrs + " t=\"inlineStr\"><is><t>"
                + escape(value) + "</t></is></c>");
    }

    static String setNumber(String xml, String ref, double value) {
        return replaceBlankCell(xml, ref, attrs -> "<c r=\"" + ref + "\"" + attrs + "><v>" + value + "</v></c>");
    }

    /** Only the cached {@code <v>} of a formula cell, for viewers that don't recalculate. */
    static String setFormulaCachedValue(String xml, String ref, double value) {
        Matcher cell = Pattern.compile("<c r=\"" + ref + "\"[^>]*>.*?<v>[^<]*</v>", Pattern.DOTALL).matcher(xml);
        if (!cell.find()) {
            return xml;
        }
        String updated = cell.group().replaceFirst("<v>[^<]*</v>", "<v>" + value + "</v>");
        return xml.substring(0, cell.start()) + updated + xml.substring(cell.end());
    }

    static String escape(String value) {
        return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
    }

    private static String replaceBlankCell(String xml, String ref, java.util.function.UnaryOperator<String> build) {
        Matcher cell = Pattern.compile("<c r=\"" + ref + "\"([^>]*)/>").matcher(xml);
        if (!cell.find()) {
            return xml;
        }
        return xml.substring(0, cell.start()) + build.apply(cell.group(1)) + xml.substring(cell.end());
    }
}
