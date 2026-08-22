SUPERGOAL_PHASE_START
Phase: 3 of 6 — Security & account administration audit
Task: Audit BlindensportGraz's authentication, role/account administration, and data-handling security; produce report/03-security.md
Type: brownfield, review
Mandatory commands: grep -n "testAdminEmail" BlindensportGraz/Models.swift ; grep -rln "elevateIfDesignatedRoot\|elevateIfTestAdmin" BlindensportGrazTests
Acceptance criteria: 5
Evidence required: command outputs, report finding count, full testAdminEmail finding text
Depends on phases: 2 (read report/02-swiftdata-cloudkit.md first)

## Why

User account administration and role-based access are core CLAUDE.md requirements, the user explicitly
named "security & account admin" as a focus area, and this app stores real people's SVNR/IBAN
(Austrian social-security/bank data) on Sport Austria paperwork — the stakes for getting this right are
real, not hypothetical.

## Work

- Read `report/02-swiftdata-cloudkit.md` first (this phase depends on it — cross-reference its CloudKit
  public-DB findings rather than re-deriving them from scratch).
- Read `BlindensportGraz/Models.swift`'s `User` extension (the `elevateIfDesignatedRoot`/
  `elevateIfTestAdmin` methods and their doc comments — already partially read during recon, re-read
  in full here).
- Read `BlindensportGraz/RootView.swift` (account resolution / login flow) and
  `BlindensportGraz/AccountView.swift` (role editing UI, `UserListView`).
- Read `RootCLI/README.md`'s "Restrict write access" / Security Roles section, and
  `RootCLI/Sources/clubmembersapi/Auth.swift` + `Configure.swift`.
- Grep `.wolf/cerebrum.md` for "root" and "isRoot" for the full history of bug-173 and related fixes.
- Audit and write findings for:
  - **`User.testAdminEmail` hardcoded TEST-ONLY admin grant** (`Models.swift`) — this is the single
    most important finding in the whole report. It hardcodes a specific real email address
    (`franz.kager@gmx.net`) that automatically gets `role = "admin"` on login/registration/email-edit,
    added 2026-07-19 with an explicit "remove this whole block... once testing is done" comment, and
    is still present a month later as of this review. Write this finding with `Severity: High`, cite
    the exact line, quote the removal-intent comment, and give an explicit, actionable recommendation:
    remove the block (and its 4 call sites) before any release beyond the current single tester, or at
    minimum wrap it in a `#if DEBUG` compile-time guard so it can never ship in a Release/TestFlight
    build. Make sure this finding is unmistakably prominent — not buried among lower-severity items.
  - **CloudKit public-DB access control** — cross-reference phase 2's CloudKit findings. The default
    "World" CloudKit role is read/write for everyone with any iCloud account; app-side role checks (34
    call sites of `role == "admin"` / `isRoot`, confirmed via earlier recon) are 100% client-side.
    `RootCLI/README.md` documents CloudKit "Security Roles" hardening as a **recommended, manual,
    optional** step, and only names `UserIdentity` and `ClubMember` as record types worth locking down
    — not the other 9 record types (Team, TeamMembership, SportEvent/Tournament/Training, EventImage,
    TrainingAttendance, TrainingFavorite, etc.). Without confirming this was actually applied in the
    Production CloudKit environment (not just Development), any iCloud user could in principle write a
    forged `UserIdentity` CKRecord setting their own `role`/`isGrazerVSCMember`, or tamper with any
    other record type's data directly, bypassing every client-side check. Recommend the user confirm
    Security Roles are applied to ALL record types in Production, not just the two named ones.
  - **Zero test coverage on role-escalation logic** — use the mandatory grep (expect empty output) to
    confirm `elevateIfDesignatedRoot`/`elevateIfTestAdmin` have no unit tests, despite this exact logic
    having a documented multi-session bug history (bug-173 and the surrounding 2026-07-19/2026-08-02
    cerebrum.md entries — cite them). Recommend specific test cases: designated-root match requires all
    three fields (first/last/email) together; test-admin grant requires only email; neither
    self-elevates on partial match; case-insensitivity of the match.
  - **No email-format validation** — check `RegisterView`/`EditAccountView` for any `TextField`
    accepting email with no format check before it's stored/used as a matching key for the
    root-escalation logic above. A malformed or accidentally-mistyped email in the designated-root
    field would simply never match (safe), but for the test-admin/general email use, no validation
    means garbage data flows straight into the CloudKit-synced `UserIdentity` record.
  - **No IBAN/SVNR format validation** — `Member.iban`/`Member.svnr` (Models.swift) are free-form
    strings with no validation, despite being exported on official PRAE/KostZ forms submitted to a
    real sports federation. Check `PraeExport.swift`/`KostZExport.swift` for any validation before
    export — expect none. Recommend at minimum a format sanity check (IBAN checksum, SVNR's known
    Austrian digit pattern) with a non-blocking warning, not a hard block (since this data may be
    imported from messy source spreadsheets, per cerebrum.md's 2026-07-30 entry about `Person-Others.
    json` having malformed data).
  - **Sensitive data in logs** — check whether `print()` statements anywhere in `CloudKitSync.swift`,
    `PraeExport.swift`, `KostZExport.swift`, or `MemberImportExport.swift` ever interpolate a `Member`
    or `User` object's full field set (which would leak SVNR/IBAN/email into Console logs) vs. only
    an id/record-type. Cite what you find either way.
  - **RootCLI transport security** — `clubmembersapi`'s HTTP Basic Auth (`Auth.swift`) is
    constant-time-compared (already correctly implemented, cite as a positive finding) but Basic Auth
    over plain HTTP would leak credentials in transit. Confirm this is deployment-configuration
    dependent (not something the Vapor app code itself enforces) and recommend documenting a
    TLS-required deployment note if one doesn't already exist in `RootCLI/README.md`.
- Tag each finding `Severity: High/Medium/Low` and `Effort: S/M/L`.
- Write `report/03-security.md` in the same format as prior phases, with the `testAdminEmail` finding
  first/most prominent regardless of alphabetical or file order.

## Acceptance criteria (all must pass — verify each in transcript)

- At least 8 concrete findings, each with a `file:line` citation.
- Explicitly covers all seven bullets under Work's "Audit and write findings for" list above.
- The `testAdminEmail` finding is present, tagged `Severity: High`, and is the first/most prominent
  finding in the report file.
- Every finding tagged with both Severity and Effort.
- Cross-references `report/02-swiftdata-cloudkit.md`'s CloudKit findings rather than re-deriving them
  from scratch (a short "see phase 2 finding N" reference is sufficient where findings overlap).

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `grep -n "testAdminEmail" BlindensportGraz/Models.swift`
- `grep -rln "elevateIfDesignatedRoot\|elevateIfTestAdmin" BlindensportGrazTests` (expect no output —
  confirms zero test coverage; if this DOES return a file, adjust the finding accordingly rather than
  reporting a false gap)

## Evidence required in transcript

- Both command outputs above, pasted verbatim.
- `report/03-security.md`'s total finding count.
- The full `testAdminEmail` finding text printed into the transcript (not just its one-line summary).

## Notes

No code changes — do not remove `testAdminEmail` or edit any `.swift` file, even though the
recommendation is to remove it. This phase reports; it does not fix. Be factual and specific about
severity — this finding is genuinely High severity (a live privilege-escalation backdoor tied to one
person's real email address, in a shared-CloudKit-container app), not something to soften.
