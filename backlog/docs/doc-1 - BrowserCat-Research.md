---
id: doc-1
title: BrowserCat Research
type: guide
created_date: '2026-07-02 10:28'
tags:
  - research
  - browsercat
  - macos
  - release
---
# BrowserCat Research

> Note: The product referenced throughout this document as "BrowserCat" was later renamed **AppCat**. Historical naming below is left intact for fidelity to the original research; this doc now lives in the AppCat repo's backlog.

## Summary

BrowserCat is a mature Swift/SwiftUI macOS app with release automation, Sparkle appcast, MIT license, README, and XCTest coverage.

## Current State

- Repo: `git@github.com:rmarinsky/BrowserCat.git`
- Local path: `diduny_co/BrowserCat`
- Last detected tag in audit: `v1.7.3`
- Distribution: GitHub Releases/Sparkle and Homebrew cask path documented.
- Known review areas include picker animation, Electron URL passing, custom Firefox profile detection, and release metadata drift.

## Linked Tasks

- `TASK-36` Capture screenshots for BrowserCat current UI
- `TASK-37` Review BrowserCat future TODOs and park non-now items

> Ported into this repo's backlog as `TASK-1` (Capture screenshots for BrowserCat current UI) and `TASK-2` (Review BrowserCat future TODOs and park non-now items), labeled `hosted-audit-origin`.

## Evidence

- `_audit/code/01-repo-inventory.md`
- `_audit/code/02a-engineering.md`
- `_audit/vault/01-vault-inventory.md`
- `diduny_co/BrowserCat/README.md`

Confidence: `confirmed` for local repo evidence.
