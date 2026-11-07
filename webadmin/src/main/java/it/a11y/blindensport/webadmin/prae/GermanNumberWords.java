package it.a11y.blindensport.webadmin.prae;

/** Euro amounts in German words for the form's "in Worten:" field — port of the app's GermanNumberWords. */
final class GermanNumberWords {
    private static final String[] ONES = {"null", "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun"};
    private static final String[] ONES_PREFIX = {"", "ein", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun"};
    private static final String[] TEENS = {"zehn", "elf", "zwölf", "dreizehn", "vierzehn", "fünfzehn", "sechzehn",
            "siebzehn", "achtzehn", "neunzehn"};
    private static final String[] TENS = {"", "", "zwanzig", "dreißig", "vierzig", "fünfzig", "sechzig", "siebzig",
            "achtzig", "neunzig"};

    private GermanNumberWords() {
    }

    static String spellOut(int n) {
        if (n < 0) {
            return "minus " + spellOut(-n);
        }
        if (n < 10) {
            return ONES[n];
        }
        if (n < 20) {
            return TEENS[n - 10];
        }
        if (n < 100) {
            int ones = n % 10;
            return ones == 0 ? TENS[n / 10] : ONES_PREFIX[ones] + "und" + TENS[n / 10];
        }
        if (n < 1000) {
            int rest = n % 100;
            String prefix = (n / 100 == 1 ? "ein" : ONES[n / 100]) + "hundert";
            return rest == 0 ? prefix : prefix + spellOut(rest);
        }
        if (n < 1_000_000) {
            int rest = n % 1000;
            String prefix = (n / 1000 == 1 ? "ein" : spellOut(n / 1000)) + "tausend";
            return rest == 0 ? prefix : prefix + spellOut(rest);
        }
        return String.valueOf(n);
    }

    static String euroAmount(double amount) {
        int totalCents = (int) Math.rint(amount * 100);
        int euros = totalCents / 100;
        int cents = Math.abs(totalCents % 100);
        String words = spellOut(euros);
        String clause = words.substring(0, 1).toUpperCase(java.util.Locale.GERMAN) + words.substring(1) + " Euro";
        return cents == 0 ? clause : clause + " und " + spellOut(cents) + " Cent";
    }
}
