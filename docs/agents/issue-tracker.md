# Issue tracker: GitHub

Issues and PRDs for this repository live in GitHub Issues. Use the `gh` CLI for all operations. Infer `rmarinsky/AppCat` from the repository remote.

## Conventions

- Create: `gh issue create --title "..." --body "..."`
- Read: `gh issue view <number> --comments`
- List: `gh issue list --state open --json number,title,body,labels,comments`
- Comment: `gh issue comment <number> --body "..."`
- Add or remove labels: `gh issue edit <number> --add-label "..."` or `--remove-label "..."`
- Close: `gh issue close <number> --comment "..."`

## Pull requests as a triage surface

External pull requests are not a request or triage surface. The `triage` skill processes GitHub Issues only.

GitHub shares one number space between issues and pull requests. If a referenced number is ambiguous, try `gh pr view <number>` and then `gh issue view <number>`.

## Skill terminology

When a skill says “publish to the issue tracker,” create a GitHub issue.

When a skill says “fetch the relevant ticket,” run:

`gh issue view <number> --comments`

## Wayfinding

The `wayfinder` skill represents a map as one GitHub issue and its tickets as child issues.

- Map label: `wayfinder:map`
- Ticket labels: `wayfinder:research`, `wayfinder:prototype`, `wayfinder:grilling`, or `wayfinder:task`
- Prefer GitHub sub-issues and native dependencies.
- If unavailable, use task lists, `Part of #<map>`, and `Blocked by: #<issue>` references.
- Claim work with `gh issue edit <number> --add-assignee @me`.
- Resolve by commenting with the result and closing the issue.
