---
id: TASK-3
title: >-
  BrowserCat UI redesign — net-new unified window + marmalade rebrand (Rebrand
  2026-06)
status: To Do
assignee: []
created_date: '2026-07-02 11:38'
labels:
  - browsercat
  - design
  - redesign
  - hosted-live-origin
dependencies: []
references:
  - mac apps/redesign-briefs/04-IMPLEMENTATION-PLAN.md
  - mac apps/redesign-briefs/02-BROWSERCAT-UI-BRIEF.md
  - mac apps/redesign-briefs/00-SHARED-DESIGN-SYSTEM.md
  - >-
    https://www.figma.com/design/k9MZms9PhgOQ33G1xWzsYq/mac-apps?node-id=131-2&m=dev
priority: medium
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Build the unified 1000x680 main window from scratch (none exists — only MenuBarExtra + Settings 620x620) and rebrand coral #FF8853 -> marmalade #F57B17 per Figma page 131:2. SECOND in sequence — start after Papuga ships.

Execution: phases B1-B7 in redesign-briefs/04-IMPLEMENTATION-PLAN.md §4; kickoff prompt in §8. XcodeGen: ./generate_project.sh after adding files.

Key risks: picker floating panel is load-bearing (keyboard nav, vibrancy, canBecomeKey) — restyle LAST and restyle-only; every new window root must repeat .environment(\.locale, ...) (uk default / en). Est. 3-4 sessions.

(Migrated from vatra utilities LIVE backlog TASK-43; live status: Inbox -> To Do. Live created 2026-06-11.)
<!-- SECTION:DESCRIPTION:END -->
