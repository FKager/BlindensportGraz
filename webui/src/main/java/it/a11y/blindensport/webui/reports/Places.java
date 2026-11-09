package it.a11y.blindensport.webui.reports;

/** Place names in reports — the app's PlaceFormat.swift. */
public final class Places {
    private Places() {
    }

    /**
     * "Linz" stays "Linz"; "Prag" + "Tschechien" becomes "Prag, Tschechien".
     * The country is left out when empty or "Österreich", and stands alone
     * when the place is empty.
     */
    public static String withForeignCountry(String place, String country) {
        String safePlace = place == null ? "" : place;
        String trimmedCountry = country == null ? "" : country.strip();
        if (trimmedCountry.isEmpty() || trimmedCountry.equals("Österreich")) {
            return safePlace;
        }
        String trimmedPlace = safePlace.strip();
        return trimmedPlace.isEmpty() ? trimmedCountry : trimmedPlace + ", " + trimmedCountry;
    }
}
