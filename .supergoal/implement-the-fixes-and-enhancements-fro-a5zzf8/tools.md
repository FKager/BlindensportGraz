# Tools detected this session

- **WebSearch / WebFetch** — available as deferred tools (via ToolSearch). Usable for verifying
  current Swift/SwiftData/CloudKit/Accessibility API details against training-cutoff knowledge if a
  phase needs it.
- **Context7** — not detected in the tool list. Skip; rely on training-cutoff Swift/SwiftUI/SwiftData
  knowledge, called out explicitly as an assumption where it matters (e.g. SwiftData migration APIs).
- **xcode MCP server** — present (`mcp__xcode__*` per system instructions: "Request Xcode perform the
  action you specify"). Can be used for local build/test orchestration if Bash's own `xcodebuild`
  remains blocked; try Bash first per existing project convention (cerebrum.md), fall back to this MCP
  only if Bash confirms the same sandbox block recurs.
- **Project skills relevant to this run:**
  - `deploy` — deploys BlindensportGraz to the physical iPhone via the self-hosted GitHub Actions
    workflow; use for final device-level verification, never local Xcode/devicectl.
  - `iOS-APP-developer` — XcodeGen/SwiftUI/SPM development, signing, CI/CD; relevant background for any
    phase touching `project.yml`, new targets, or signing.
  - `run` — launches/screenshots the app to confirm a change works; may not apply well here (no local
    device/simulator run confirmed working in this sandbox beyond `xcodebuild test`), evaluate per
    phase.
  - `security-review` — could be invoked for an extra pass over the security-related phases if useful,
    not required (the phases themselves already carry explicit security acceptance criteria from
    audit.md).
- **RootCLI** (`rootcli` Swift CLI in this repo, not an external tool) — used directly during Phase 1
  to grant `franz.kager@gmx.net` real admin before removing the `testAdminEmail` backdoor, per user's
  confirmed answer.
