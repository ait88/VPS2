# Frequently Asked Questions for Agents

> **Quick answers to common questions**
>
> Read time: 5-10 minutes

---

## 1. What are my workflow steps?

**Short answer:**
1. Claim issue: `/claim-issue <number>`
2. Implement: Write code, tests, documentation
3. Validate: `/check-workflow`
4. Submit: `/submit-pr`

**Full details:** See [.claude/skills/README.md](../.claude/skills/README.md) (mirrored at `.codex/skills`)

---

## 2. How do I run tests?

**Short answer:**
```bash
shellcheck *.sh
shellcheck wordpress-mgmt/lib/*.sh
```

---

## 3. How do I check code style?

**Short answer:**
```bash
shellcheck *.sh
```

---

## 4. Where are files located?

See [CODEBASE-MAP.md](CODEBASE-MAP.md) for complete file navigation.

**Quick reference:**
- Main scripts: `/` (root)
- Module libraries: `wordpress-mgmt/lib/`
- Documentation: `docs/`
- Agent skills: `.claude/skills/`

---

## 5. What commit message format should I use?

**Format:**
```
<type>(<scope>): <description> (#<issue>)
```

**Types:**
- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation
- `refactor` - Code refactoring
- `test` - Adding tests
- `chore` - Maintenance

**Example:**
```
feat(backup): add encryption support (#42)
```

---

## 6. How do I handle blocked issues?

1. Add `blocked` label:
   ```bash
   gh issue edit $ISSUE --add-label "blocked"
   ```

2. Leave explanatory comment:
   ```bash
   gh issue comment $ISSUE --body "Blocked because: [reason]"
   ```

3. Keep `in-progress` label (you're still assigned)

---

## 7. What labels are used?

| Label | Meaning | When Set |
|-------|---------|----------|
| `agent-ready` | Available for work | By maintainer |
| `in-progress` | Agent working on it | By `/claim-issue` |
| `needs-review` | PR created | By `/submit-pr` |
| `blocked` | Waiting on something | Manually when stuck |

---

## 8. How do I update documentation?

Update docs **in the same PR** as code changes when:
- Adding new features
- Changing existing behavior
- Adding new patterns

**Don't** create new documentation files unless specifically requested.

---

## 9. What if my PR has conflicts?

```bash
git fetch origin main
git rebase origin/main
# Resolve conflicts
git push --force-with-lease
```

---

## 10. How do I know if tests are required?

**Always write tests for:**
- New features
- Bug fixes (regression tests)
- Public API changes

**Skip tests for:**
- Documentation-only changes
- Configuration changes
- Comment-only changes

---

## 11. What are the key security rules for this project?

See `.claude/SECURITY-CHECKLIST.md` for complete checklist.

**Critical rules:**
- Always use `set -euo pipefail`
- Quote all variables
- Never use `eval` with user input
- No hardcoded credentials
- Validate all file paths

---

## 12. How do I modify permissions in this project?

**NEVER modify permissions directly.** Use the `enforce_standard_permissions()` function in `lib/utils.sh`.

Standard model:
- `644` - Regular files
- `755` - Directories and executables
- `640` - Sensitive config (wp-config.php)
- `2775` - Writable directories (uploads)

---

## 13. How do I add a new module?

1. Create `lib/new-feature.sh` following standard structure
2. Add source line to `setup-wordpress.sh` module loading
3. Add state variables (e.g., `NEW_FEATURE_CONFIGURED`)
4. Add menu option if needed
5. Update AGENTS.md with new module details

---

## Didn't Find Your Question?

1. Check [CODEBASE-MAP.md](CODEBASE-MAP.md) for file locations
2. Check [QUICK-REFERENCE.md](QUICK-REFERENCE.md) for navigation
3. Read [AGENTS.md](../AGENTS.md) for architecture details
4. Read existing code for patterns

---

**Contributing to this FAQ:**

If you had a question that took time to answer, consider adding it here!

---

**Last updated:** 2026-01-12
