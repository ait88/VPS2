# Quick Reference for Claude & Codex Agents

> **Start here!** Fast navigation to all project documentation.

**Read time:** 3-5 minutes

---

## Quick Start Paths

### "I need to work on an issue"
1. Find work: `gh issue list --label "agent-ready"`
2. Claim it: `/claim-issue <number>`
3. Implement: Follow coding conventions below
4. Submit: `/submit-pr`

### "I need to understand the codebase"
1. Architecture: [AGENTS.md](../AGENTS.md) (comprehensive guide)
2. File navigation: [CODEBASE-MAP.md](CODEBASE-MAP.md)
3. Common questions: [FAQ-AGENTS.md](FAQ-AGENTS.md)

### "I need to implement a feature"
1. Check [FAQ-AGENTS.md](FAQ-AGENTS.md) first
2. Find relevant files in [CODEBASE-MAP.md](CODEBASE-MAP.md)
3. Follow coding conventions below
4. Run tests: `shellcheck *.sh`

---

## Documentation Index

| Document | What's Inside | When to Read |
|----------|---------------|--------------|
| [AGENTS.md](../AGENTS.md) | Complete system architecture | Deep understanding |
| [FAQ-AGENTS.md](FAQ-AGENTS.md) | Common questions pre-answered | Before reading longer docs |
| [CODEBASE-MAP.md](CODEBASE-MAP.md) | File navigation guide | Finding code |
| [.claude/skills/README.md](../.claude/skills/README.md) | Workflow skills (mirrored at `.codex/skills`) | Using skills |

---

## Common Tasks Quick Finder

### Workflow Tasks
- **Claim an issue:** `/claim-issue <number>`
- **Validate workflow:** `/check-workflow`
- **Submit PR:** `/submit-pr`
- **Check labels:** `gh issue view $ISSUE --json labels`

### Development Tasks
- **Run tests:** `shellcheck *.sh`
- **Check code style:** `shellcheck *.sh`
- **Find files:** Use [CODEBASE-MAP.md](CODEBASE-MAP.md)

---

## Pre-Flight Checklists

### Before Every Commit
- [ ] Tests pass: `shellcheck *.sh`
- [ ] Code style: `shellcheck *.sh`
- [ ] Conventional commit message format

### Before Creating PR
- [ ] `/check-workflow` passes
- [ ] All tests passing
- [ ] Documentation updated if needed

---

## Coding Conventions

### Bash Script Standards
- **Shebang:** `#!/usr/bin/env bash`
- **Strict mode:** `set -euo pipefail`
- **Indentation:** 4 spaces
- **Line endings:** LF (Unix)

### Naming Conventions
- **Scripts:** `kebab-case.sh`
- **Functions:** `snake_case`
- **Variables:** `SCREAMING_SNAKE_CASE`
- **Local vars:** `lower_snake_case`

### Commit Message Format
```
<type>(<scope>): <description> (#<issue>)
```

**Types:** `feat`, `fix`, `docs`, `refactor`, `test`, `chore`

**Examples:**
```
feat(backup): add retention pinning (#35)
fix(nginx): handle null values (#42)
docs(readme): update installation steps (#18)
```

---

## When You're Stuck

1. Check [FAQ-AGENTS.md](FAQ-AGENTS.md)
2. Use [CODEBASE-MAP.md](CODEBASE-MAP.md) to find related files
3. Read existing similar code for patterns
4. If still stuck, ask for clarification in the issue

---

**Last updated:** 2026-01-12
