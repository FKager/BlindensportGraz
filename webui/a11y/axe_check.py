"""Accessibility check of the web UI with axe-core (WCAG 2.1 A + AA).

Opens every page in a headless Chromium, signed out and then signed in as
the local root from supabase/seed.sql (with sample-data.sql loaded, so
tables and reports have rows), and runs axe on it. Fails on every
violation not listed in accepted.txt (one "rule-id route" per line, with a
reason as a comment). CI: .github/workflows/webui-a11y.yml.

    python axe_check.py http://127.0.0.1:8080 root@example.test localroot123
"""
import pathlib
import sys

from axe_playwright_python.sync_playwright import Axe
from playwright.sync_api import sync_playwright

PUBLIC = ["", "login", "registrieren", "passwort-vergessen"]
SIGNED_IN = ["uebersicht", "termine", "teams", "mitglieder", "aenderungsantraege", "konten",
             "rollen", "protokoll", "sportarten", "budget", "abrechnung", "trainingsfrequenzliste",
             "favoriten", "willkommen", "mcp-tokens"]
TAGS = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]


def accepted() -> set[tuple[str, str]]:
    path = pathlib.Path(__file__).with_name("accepted.txt")
    pairs = set()
    for line in path.read_text().splitlines() if path.exists() else []:
        line = line.split("#", 1)[0].strip()
        if line:
            rule, route = line.split()
            pairs.add((rule, "" if route == "/" else route))
    return pairs


def check(page, axe, route: str) -> list[tuple[str, str, str]]:
    page.wait_for_load_state("networkidle")
    page.wait_for_timeout(500)  # Vaadin renders after the first response
    result = axe.run(page, options={"runOnly": {"type": "tag", "values": TAGS}})
    found = []
    for violation in result.response["violations"]:
        targets = "; ".join(" ".join(map(str, node["target"])) for node in violation["nodes"][:3])
        found.append((violation["id"], route, f'{violation["impact"]}: {violation["help"]} [{len(violation["nodes"])}x] {targets}'))
    return found


def main() -> int:
    base, email, password = sys.argv[1].rstrip("/"), sys.argv[2], sys.argv[3]
    axe = Axe()
    findings = []
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(locale="de-AT")
        for route in PUBLIC:
            page.goto(f"{base}/{route}")
            findings += check(page, axe, route)
        page.goto(f"{base}/login")
        page.get_by_label("E-Mail").fill(email)
        page.get_by_label("Passwort").fill(password)
        page.get_by_role("button", name="Anmelden").click()
        page.wait_for_url(lambda url: "/login" not in url, timeout=15_000)
        for route in SIGNED_IN:
            page.goto(f"{base}/{route}")
            if "/login" in page.url:
                findings.append(("not-signed-in", route, "redirected to /login"))
                continue
            findings += check(page, axe, route)
        browser.close()
    allowed = accepted()
    new = [f for f in findings if (f[0], f[1]) not in allowed]
    for rule, route, detail in findings:
        mark = "accepted" if (rule, route) in allowed else "FAIL"
        print(f"{mark:8} /{route:24} {rule:28} {detail}")
    print(f"{len(findings)} findings, {len(new)} not accepted")
    return 1 if new else 0


if __name__ == "__main__":
    sys.exit(main())
