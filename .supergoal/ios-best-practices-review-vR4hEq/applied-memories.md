# Applied memories

Claude memory index (`/Users/franz/.claude/projects/-Users-franz-dev-BlindensportGraz/memory/MEMORY.md`)
is empty — no prior Claude-memory entries exist for this project yet. This is the first Supergoal run
here, so there are no memory hits to apply.

Project-local knowledge (not Claude memory, but functionally equivalent — consulted and applied):

- `.wolf/cerebrum.md` — read in full. Key facts folded into THINKING.md:
  - User relies on VoiceOver as their primary way of operating their own phone (cannot test with it
    off) — accessibility findings must be considered from a VoiceOver-first lens, not a generic a11y
    checklist, and the report must not suggest "just test with VoiceOver off."
  - Deployment target is iOS 26.0, chosen deliberately to use SwiftData `@Model` class inheritance —
    not an oversight to "fix."
  - `User.testAdminEmail = "franz.kager@gmx.net"` (the user's own email) is a documented TEST-ONLY
    admin-role backdoor added 2026-07-19, explicitly marked "remove once testing is done" — still
    present in code as of this run (2026-08-19, one month later). Flagged as a live finding, not
    re-discovered from scratch.
  - CloudKit's public database uses `.changedKeys` last-write-wins with no real conflict resolution,
    by deliberate design tradeoff (documented rationale in CloudKitSync.swift) — the report should
    note this as an accepted tradeoff, not "discover" it as an unknown bug, but should still flag the
    security implication (client-side-only role enforcement) which the existing docs treat as a
    separate, still-open "recommended" hardening step (RootCLI/README.md's CloudKit Security Roles
    section).
- `.wolf/anatomy.md` — read in full, used to avoid re-reading files already summarized there and to
  build the file inventory for recon instead of a blind `find`.

After this run, the final phase must write a `project_blindensportgraz.md` Claude-memory entry so a
future Supergoal run on this project starts warmer than this one did.
