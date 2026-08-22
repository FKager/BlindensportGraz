# Tools detected this session

- Context7: not detected in tool list — not available.
- WebSearch / WebFetch: available via ToolSearch (deferred tools) — usable if needed to check
  current Swift/SwiftUI/SwiftData/CloudKit best-practice guidance beyond training-cutoff knowledge.
- xcode MCP server: listed as "still connecting" at session start — may become available; if so,
  it can be used to actually build the project for a real diagnostics pass. Do NOT rely on this;
  proceed via static analysis regardless of its availability.
- No project skills specifically relevant to a static code-quality/security audit were found beyond
  the generic `security-review` and `code-review` skills (not invoked directly — this run's deliverable
  is a broader best-practices + feature-enhancement report, not a diff review).
- Project-local knowledge base already available and consulted: `.wolf/anatomy.md` (file map) and
  `.wolf/cerebrum.md` (accumulated project learnings, user preferences, decision log, do-not-repeat
  list) — this is NOT the Claude memory system but is authoritative project history and was read in
  full before recon.

## Known environment constraint (from .wolf/cerebrum.md Do-Not-Repeat, 2026-07-15/08-05)

`xcodebuild`/`codesign` hit a sandbox-level block (`errSecInternalComponent`, "User interaction is
not allowed") when run from this coding session's own Bash tool — this is NOT fixable by retrying or
keychain ACL changes. **Phase specs in this run deliberately do NOT require `xcodebuild build` as a
mandatory command** — this review is static-analysis-based. Do not attempt to "verify" findings by
running a real build in this sandbox; it will predictably fail for sandbox reasons unrelated to code
correctness and waste retry budget.
