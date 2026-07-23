# Domain docs

AppCat uses a single-context domain layout.

## Before exploring

Read these when they exist and are relevant:

- `CONTEXT.md` at the repository root
- ADRs under `docs/adr/`

If either is absent, proceed silently. Domain-modeling skills create them lazily when terminology or architectural decisions are resolved.

## Layout

```text
/
├── CONTEXT.md
├── docs/
│   └── adr/
└── AppCat/
```

## Vocabulary

Use domain concepts as defined in `CONTEXT.md` in issue titles, hypotheses, tests, refactoring proposals, and implementation notes.

Avoid introducing synonyms that conflict with the glossary. If a required concept is missing, reconsider whether it is established product language or record the gap for domain modeling.

## Architectural decisions

Read relevant ADRs before proposing architectural changes.

If a proposal contradicts an ADR, identify the conflict explicitly instead of silently overriding the decision.
