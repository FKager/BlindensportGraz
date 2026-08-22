SUPERGOAL_PHASE_START
Phase: 19 of 19 — Polish & Harden
Task: Full regression sweep, security/accessibility spot-checks, one real-device smoke check, and a compiled manual-follow-ups checklist for the user.
Type: brownfield, polish, security, accessibility
Mandatory commands: xcodegen generate; xcodebuild build ...; xcodebuild test ...; cd RootCLI && swift build; grep testAdminEmail; grep accessibilityLabel count; git diff main --stat; deploy skill device trigger
Acceptance criteria: 9
Evidence required: final test summary, accessibility count, git diff stat, device-deploy result, manual-follow-ups checklist
Depends on phases: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18

## Why

Catch what earlier phases missed because they were focused on shipping behavior, and compile the manual
(non-automatable) follow-ups — CloudKit Dashboard Security Roles application, Production environment
schema sync for every new record type added this run — into one clear list for the user. This is how
"every aspect is perfect" gets enforced for a run this large.

## Work

- Check `.wolf/anatomy.md`/`.wolf/cerebrum.md`/`.wolf/buglog.json` first — confirm every phase actually
  updated them incrementally per the OpenWolf protocol; fix any gaps found (small, targeted, this pass
  doesn't rewrite history, it fills real gaps).
- Run the full local unit test suite one final time; confirm the only failure (if any) is the known
  pre-existing `MemberImportExportTests` CloudKit-entitlement crash (bug-202) — if any OTHER test fails,
  that's a real regression from one of the 18 prior phases and must be fixed here, not shrugged off.
- Re-verify Phase 1's backdoor removal is still gone (`grep -n "testAdminEmail"
  BlindensportGraz/*.swift` returns nothing) — confirm no later phase reintroduced anything like it.
- Re-verify Phase 3's input validation (email/IBAN/SVNR) still doesn't block legitimate malformed-but-real
  data from saving.
- Grep the full diff since `main` for any hardcoded secret/credential/API key any phase may have
  introduced — confirm none exists.
- Re-run `grep -rln "accessibilityLabel\|accessibilityHint" BlindensportGraz --include="*.swift" | wc -l`
  and confirm it's meaningfully higher than the original 4; spot-check 3 screens (pick screens touched
  by different phases, e.g. one from Phase 12, one from Phase 15's new Charts view, one from Phase 17's
  calendar action) by reading their code for correct label/hint presence.
- Re-check for `.sheet`-inside-`.sheet` nesting across the FULL cumulative diff from all 19 phases (not
  just Phase 12's own changes) — any new sheet-presenting UI added by Phases 14-18 needs this check too.
- Run `git diff main --stat` and review for stray debug `print()`/TODO/FIXME left behind by any phase;
  fix anything found inline, small and targeted.
- Run `cd RootCLI && swift build` to confirm RootCLI still builds cleanly with the cumulative changes
  (schema package from Phase 9, audit log from Phase 2, rate limiting from Phase 4).
- Trigger the one real device-level smoke check via the `deploy` skill (per `build_commands.md`'s
  documented flow: `gh workflow run "iOS Device Deploy"`, find the run, `gh run watch <run-id>
  --exit-status`) — this is the one thing genuinely unverifiable locally across the whole run. If this
  fails, treat it as a real FAILURE_PROBE, not something to route around.
- Compile the full manual-follow-ups checklist: CloudKit Dashboard Security Roles for all 11 record
  types in Production (Phase 4), confirming RoleChangeLog (Phase 2) and any receipt-attachment record
  type (Phase 18) exist in the Production schema with Security Roles configured, and any other manual
  step any phase's Notes section flagged along the way. Present this as a short, clear checklist, not
  buried in prose.

## Acceptance criteria (all must pass — verify each in transcript)

- [ ] Full local unit test suite passes with only the known pre-existing `MemberImportExportTests`
      failure (confirmed to be the SAME failure as before this run started, not a new one)
- [ ] `grep -n "testAdminEmail" BlindensportGraz/*.swift` returns no results
- [ ] Input validation from Phase 3 still doesn't block legitimate malformed-but-real data
- [ ] No hardcoded secret/credential is present anywhere in the cumulative diff since `main`
- [ ] Accessibility label/hint file coverage has risen meaningfully from the original 4-file baseline,
      confirmed by re-running the grep and spot-checking 3 screens from different phases
- [ ] No `.sheet`-inside-`.sheet` nesting exists anywhere in the cumulative diff
- [ ] `cd RootCLI && swift build` succeeds
- [ ] The device-level smoke check via the `deploy` skill completes successfully (build + install +
      launch on the user's physical iPhone)
- [ ] A complete, clearly-formatted manual-follow-ups checklist is printed for the user

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `xcodegen generate`
- `xcodebuild build -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `xcodebuild test -project BlindensportGraz.xcodeproj -scheme BlindensportGraz -destination "platform=iOS Simulator,name=<device from xcrun simctl list devices available>" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- `cd RootCLI && swift build`
- `grep -n "testAdminEmail" BlindensportGraz/*.swift`
- `grep -rln "accessibilityLabel\|accessibilityHint" BlindensportGraz --include="*.swift" | wc -l`
- `git diff main --stat`
- `gh workflow run "iOS Device Deploy"` then `gh run list --workflow "iOS Device Deploy" --limit 1` then
  `gh run watch <run-id> --exit-status`

## Evidence required in transcript

- Final test summary (pass count, the one known pre-existing failure named explicitly, confirmation no
  NEW failure exists)
- The accessibility before/after count (4 → final) plus the 3 spot-checked screens' results
- `git diff main --stat` output
- The device-deploy workflow run URL + result
- The final manual-follow-ups checklist, printed in full

## Notes

This is the last phase — after `AUDIT_COMPLETE` (per PROTOCOL.md's final-audit step, which runs after
this phase), the run prints `SUPERGOAL_RUN_COMPLETE`. Make the manual-follow-ups checklist genuinely
usable as a standalone artifact the user can act on later — it's the honest acknowledgment of what this
run could NOT verify or apply from this sandboxed environment (primarily: CloudKit Dashboard Security
Roles configuration in Production).

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in PROTOCOL.md without further instruction needed here.
