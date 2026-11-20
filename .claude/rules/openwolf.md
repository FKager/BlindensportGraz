---
description: OpenWolf protocol enforcement — active on all files
globs: **/*
---

- Check .wolf/anatomy.md before reading any project file
- Check .wolf/cerebrum.md Do-Not-Repeat list before generating code
- After receiving a user correction, update .wolf/cerebrum.md immediately (Preferences, Learnings, or Do-Not-Repeat)
- Add conventions, user preferences and project patterns you discover to .wolf/cerebrum.md
- BEFORE fixing any bug or error: read .wolf/buglog.json for known fixes
- After fixing a bug, failed test, failed build or user-reported problem, log it to .wolf/buglog.json with error_message, root_cause, fix, and tags
- When the user asks to check/evaluate UI design: run `openwolf designqc` to capture screenshots, then read them from .wolf/designqc-captures/
