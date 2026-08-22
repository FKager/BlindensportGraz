SUPERGOAL_PHASE_START
Phase: 6 of 6 — Report compilation, polish & publish
Task: Merge, de-duplicate, spot-check, and publish the final BlindensportGraz best-practices review as one Artifact
Type: brownfield, review, ui, polish
Mandatory commands: grep -c "^\*\*Finding\|^\*\*Suggestion" report/REPORT.md ; wc -l report/REPORT.md
Acceptance criteria: 7
Evidence required: executive summary, citation spot-check results, published Artifact URL, final line/finding counts
Depends on phases: 1, 2, 3, 4, 5 (all five prior report files must exist)

## Why

This is the Polish & Harden phase for a report-only deliverable — it's how "every aspect is perfect"
gets enforced when the output is a document, not code: cross-referenced, de-duplicated, prioritized,
evidence-checked, and actually handed to the user in a genuinely usable form, not five loose files.

## Work

- Read all five prior report files in full: `report/01-architecture.md`, `report/02-swiftdata-cloudkit.md`,
  `report/03-security.md`, `report/04-accessibility.md`, `report/05-enhancements.md`.
- **Merge & de-duplicate:** write `report/REPORT.md` with this structure:
  1. Title + one-paragraph intro (what was reviewed, scope, method — static analysis, no code changes,
     no build attempted per the sandbox constraint noted in tools.md).
  2. **Executive summary** — the top 5 findings across ALL areas, ranked by severity/impact, each one
     sentence with a pointer to its full writeup later in the document. The `testAdminEmail` finding
     from phase 3 MUST be #1.
  3. One section per audit area (Architecture, SwiftData & CloudKit Sync, Security & Account Admin,
     Accessibility), each containing that phase's findings, renumbered continuously across the whole
     document (not restarting at 1 per section) so cross-references stay unambiguous.
  4. Enhancements & new-feature backlog section (phase 5's content), grouped by priority (P0 first).
  5. A short closing "How to use this report" note (e.g. suggesting the user triage P0/High items
     first, and specifically calling out that the `testAdminEmail` finding should be addressed before
     any wider distribution).
  - Where a finding appears in more than one section (e.g. a security-flavored finding also touched
    in architecture), merge them into one entry in the more specific section and leave a one-line
    cross-reference in the other, rather than duplicating the full writeup.
- **Citation spot-check:** pick at least 6 findings at random spread across different sections, open
  the cited file at the cited line, and confirm the finding's claim actually holds. Print a table in
  the transcript: finding # / file:line / pass or fail. If any citation fails, correct it in
  `report/REPORT.md` (fix the line number, or soften/correct the claim) before proceeding — do not
  leave a known-wrong citation in the published version.
- **Consistency check:** confirm no two findings contradict each other, and re-grep `.wolf/cerebrum.md`
  for any enhancement-backlog item's topic to confirm phase 5's own settled-decision check actually
  held (spot-check at least 2 of the enhancement suggestions this way).
- **Copy pass:** consistent Severity/Effort/Priority vocabulary throughout, no leftover template
  placeholders, no broken cross-references (every "see finding N" / "see report/0X" reference must
  resolve to something that actually exists in the merged document).
- **Total finding count sanity check:** run the mandatory `grep -c` command against the finished
  `report/REPORT.md`. Expect roughly 32-44 findings (4 areas × ~8 minimum each) plus 10+ enhancement
  suggestions — call this out explicitly in the transcript; if far outside that range, explain why
  (e.g. some findings were merged during de-duplication) rather than silently padding or truncating.
- **Publish:** call the `Skill` tool with `artifact-design` first (required before any Artifact
  publish per that tool's own instructions), then use the `Artifact` tool to publish `report/REPORT.md`
  as a Markdown artifact — pick a distinctive title (not generic, e.g. "BlindensportGraz Code Review"
  rather than just "Report"), a one-sentence description, and a favicon emoji (e.g. 🔍 or 🛡️). Capture
  the resulting URL.
- Update `STATE.md`: mark all 6 phases complete, set `Status: COMPLETE`.
- **Memory writeback:** write a `project_blindensportgraz.md` Claude-memory entry (per PROTOCOL.md's
  final-phase rule) pointing at this project (location `/Users/franz/dev/BlindensportGraz`, stack
  SwiftUI/SwiftData/CloudKit, status: best-practices review completed 2026-08-19, link to this run's
  `ROADMAP.md` and the published Artifact URL) so a future Supergoal run on this project starts warm.
  Also consider (only if genuinely non-obvious and likely useful to a future run, per the memory
  writeback rules in PROTOCOL.md) a `feedback_`-type memory noting the user prefers report-only runs
  to stay code-change-free when asked, and that this codebase's `.wolf/cerebrum.md` is a rich existing
  project-history source worth reading before any future audit/review task here.

## Acceptance criteria (all must pass — verify each in transcript)

- `report/REPORT.md` exists, contains an executive summary with exactly 5 top findings, and the
  `testAdminEmail` finding is #1 in that summary.
- All findings from the 4 audit reports and all suggestions from the enhancement report are present in
  the merged document (no silent drops beyond legitimate de-duplication, which must be noted).
- Citation spot-check: at least 6 findings checked, results printed as a pass/fail table, any failures
  corrected before publish.
- No unresolved `{{...}}` template artifacts, no broken internal cross-references.
- Total finding/suggestion count sanity-checked and explained in transcript.
- The report is published as an Artifact and the URL is printed into the transcript.
- `STATE.md` updated to `Status: COMPLETE` with all 6 phases marked complete.

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `grep -c "^\*\*Finding\|^\*\*Suggestion" report/REPORT.md`
- `wc -l report/REPORT.md`

## Evidence required in transcript

- The full executive summary (top 5 findings) printed into the transcript.
- The citation spot-check pass/fail table (at least 6 rows).
- The published Artifact URL.
- Final `report/REPORT.md` line count and total finding/suggestion count, with the sanity-check
  explanation if outside the expected range.
- `MEMORY_SAVED: project_blindensportgraz` (or the memory writeback rules' "none" form, though a
  final-phase project memory is expected per PROTOCOL.md's own rule).

## Notes

This phase is the deliverable. Do not rush the citation spot-check — a report whose citations don't
hold up undermines the whole exercise. After publishing, print a short (5-10 line) plain-text summary
of the review's headline findings into the transcript as well, not just the Artifact link, so the
value is visible even to someone who doesn't click through.
