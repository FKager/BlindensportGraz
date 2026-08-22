SUPERGOAL_PHASE_START
Phase: 4 of 19 — CloudKit access-control hardening & docs
Task: Rewrite RootCLI's Security Roles docs to cover all 11 record types, add a TLS deployment note, and add rate limiting to clubmembersapi's Basic Auth.
Type: brownfield, security, docs
Mandatory commands: cd RootCLI && swift build
Acceptance criteria: 6
Evidence required: README diff, rate-limiting code, swift build output
Depends on phases: none

## Why

audit.md's Security Finding 2 (CloudKit's public DB defaults to World read/write; 34+ role checks are
entirely client-side; the existing hardening doc only names 2 of 11 record types), Finding 8 (TLS is a
deployment responsibility the docs don't call out), and Finding 9 (no rate limiting/lockout on
clubmembersapi auth attempts) — grouped as the same "access-control hardening" theme.

## Work

- Check `.wolf/anatomy.md` for `RootCLI/README.md`'s current content summary before reading the whole
  file; read it in full since this phase rewrites a significant section of it.
- Read `Models.swift` and `CloudKitSync.swift` to confirm the full list of 11 CKRecord types (Team,
  TeamMembership, SportEvent, Tournament, Training, EventImage, TrainingAttendance,
  TournamentAttendance, TrainingFavorite, UserIdentity, Member/ClubMember — verify names against the
  real code, not audit.md's paraphrase).
- Rewrite `RootCLI/README.md`'s "Security Roles" section (currently lines ~66-93 per audit.md, confirm
  actual current line numbers) to give explicit recommended role configuration for all 11 record types,
  not just UserIdentity/ClubMember — for each, state whether World read/write should be restricted and
  to what (e.g. "Authenticated Users: read/write" vs "Creator: write, World: read" — reason about each
  type's actual access pattern: e.g. TrainingFavorite is personal/per-user, most others are
  club-shared).
- Add explicit language that Development and Production CloudKit environments are configured
  separately in the Dashboard and both need this hardening applied — cite that this app's data has
  historically only been verified/discussed for one environment.
- Add a new "Deployment / TLS" note to `RootCLI/README.md` stating `clubmembersapi` must be deployed
  behind a TLS-terminating reverse proxy or load balancer, not run as an unencrypted origin server.
- Add basic rate limiting/lockout to `RootCLI/Sources/clubmembersapi/Auth.swift`/`Configure.swift`: an
  in-memory sliding-window or fixed-window limiter keyed by client IP (or by attempted username, both
  are defensible — pick one and document the choice in a code comment) that returns 429 after N failed
  attempts within a time window. Keep it simple — this is a small internal tool, not a public API; don't
  add a database or external dependency for this.
- Confirm valid-credential requests are completely unaffected by the new limiter.

## Acceptance criteria (all must pass — verify each in transcript)

- [ ] README's Security Roles section lists all 11 record types with recommended role configuration for
      each
- [ ] README explicitly states Dev/Prod are configured separately and both need hardening applied
- [ ] A new "Deployment / TLS" note exists stating TLS termination is required, not optional
- [ ] `clubmembersapi` returns 429 (or closes the connection) after N failed auth attempts from the same
      client within a time window — verified via `swift build` passing and a code-level walkthrough of
      the middleware wiring (no live server run required to satisfy this criterion)
- [ ] Valid-credential requests are unaffected by the new limiter (code review confirms the success path
      doesn't touch the failure counter, or resets it)
- [ ] `swift build` passes for RootCLI with the new middleware

## Mandatory commands (run each, surface last ~10 lines + exit code)

- `cd RootCLI && swift build`

## Evidence required in transcript

- README diff showing all 11 record types and the new TLS note
- The rate-limiting middleware code + description of its window/threshold choice
- `swift build` output with exit code

## Notes

This phase cannot apply the CloudKit Dashboard Security Roles configuration itself — no CLI/API for it
was found in prior sessions (cktool has schema import/export but no Security Roles subcommand, per
cerebrum.md's 2026-07-16 entry). This phase's job is the documentation + the parts that ARE code
(clubmembersapi rate limiting). Note the manual Dashboard step clearly so Phase 19 can compile it into
the final follow-ups list.

---

The agent will, during execution, print SUPERGOAL_PHASE_START (above),
do the work, then print SUPERGOAL_PHASE_VERIFY, MEMORY_SAVED, and
SUPERGOAL_PHASE_DONE in order. On failure, the agent follows the
3-strike recovery protocol in PROTOCOL.md without further instruction needed here.
