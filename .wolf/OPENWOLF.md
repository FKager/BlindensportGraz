# OpenWolf Operating Protocol

You are working in an OpenWolf-managed project. These rules apply every turn.

## File Navigation

1. Check `.wolf/anatomy.md` BEFORE reading any file. It has a 2-3 line description and token estimate for every file in the project.
2. If the description in anatomy.md is sufficient for your task, do NOT read the full file.
3. If a file is not in anatomy.md, search with Grep/Glob, then update anatomy.md with the new entry.

## Code Generation

1. Before generating code, read `.wolf/cerebrum.md` and respect every entry.
2. Check the `## Do-Not-Repeat` section — these are past mistakes that must not recur.
3. Follow all conventions in `## Key Learnings` and `## User Preferences`.

## Cerebrum Learning

OpenWolf's value comes from learning across sessions: update `.wolf/cerebrum.md` when you learn something a later session would otherwise have to rediscover.

**Update `## User Preferences` when the user:**
- Corrects your approach ("no, do it this way instead")
- Expresses a style preference (naming, structure, formatting)
- Shows a preferred workflow or tool choice
- Rejects a suggestion — record what they preferred instead
- Asks for more/less detail, verbosity, explanation

**Update `## Key Learnings` when you discover:**
- A project convention not obvious from the code (e.g., "tests go in __tests__/ not test/")
- A framework-specific pattern this project uses
- An API behavior that surprised you
- A dependency quirk or version constraint
- How modules connect or data flows through the system

**Update `## Do-Not-Repeat` (with date) when:**
- The user corrects a mistake you made
- You try something that fails and find the right approach
- You discover a gotcha that would trip up a fresh session

**Update `## Decision Log` when:**
- A significant architectural or technical choice is made
- The user explains why they chose approach A over B
- A trade-off is explicitly discussed

Skip what the code, git history or an existing entry already records; cerebrum.md is read before every code change, so each entry costs every session.

## Bug Logging

**Log to `.wolf/buglog.json` when you fix a bug:** a failing build, test or command, a runtime/type/syntax error, a wrong dependency, or a problem the user reported. Refactors, new error handling and repeated edits on the way to a feature are not bugs.

**Before fixing:** Read `.wolf/buglog.json` first — the fix may already be known.

**After fixing:** append to `.wolf/buglog.json` with this structure:
```json
{
  "id": "bug-NNN",
  "timestamp": "ISO date",
  "error_message": "exact error or user complaint",
  "file": "file that was fixed",
  "root_cause": "why it broke",
  "fix": "what you changed to fix it",
  "tags": ["relevant", "keywords"],
  "related_bugs": [],
  "occurrences": 1,
  "last_seen": "ISO date"
}
```

## Token Discipline

- Never re-read a file already read this session unless it was modified since.
- Prefer anatomy.md descriptions over full file reads when possible.
- Prefer targeted Grep over full file reads when searching for specific code.
- If appending to a file, do not read the entire file first.

## Design QC

When the user asks you to check, evaluate, or improve the design/UI of their app:

1. Run `openwolf designqc --url <web UI URL>` via Bash to capture the web UI (this repository has no package.json, so auto-detection finds nothing; designqc does not cover the iOS app).
   - The command saves compressed JPEG screenshots to `.wolf/designqc-captures/`
   - Full pages are captured as sectioned viewport-height images (top, section2, ..., bottom)
2. Read the captured screenshot images from `.wolf/designqc-captures/` using the Read tool.
3. Evaluate the design against Apple's Human Interface Guidelines (iOS app) or Vaadin's components (web UI), accessibility first (VoiceOver/screen readers, Dynamic Type, WCAG contrast):
   - Spacing and whitespace consistency
   - Typography hierarchy and readability
   - Color contrast and accessibility (WCAG)
   - Visual hierarchy and focal points
   - Component consistency
   - Whether the design looks "dull" or "white-coded" (generic, no personality)
4. Provide specific, actionable feedback with fix suggestions.
5. If the user approves, implement the fixes directly in their code.
6. After fixes, re-run `openwolf designqc` to capture new screenshots and verify improvement.

**Token awareness:** Each screenshot costs ~2500 tokens. The command compresses images (JPEG quality 70, max width 1200px) to minimize cost. For large apps, use `--routes / /specific-page` to limit captures.

## Session End

Before ending or when asked to wrap up:

Review the session: did you learn anything? Did the user correct you? Did you fix a bug? If yes, update `.wolf/cerebrum.md` and/or `.wolf/buglog.json`.
