# Agent Instructions

This project uses **JJ (Jujutsu)** for version control and **bd (Beads)** for issue tracking.

## Quick Reference

### Version Control (JJ)

```bash
jj status            # Check working copy status
jj log               # View commit history
jj new               # Start new change
jj describe -m "msg" # Describe current change
jj git push          # Push to remote
```

### Issue Tracking (Beads)

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Starting a Work Session

1. **Pull latest changes:**
   ```bash
   jj git fetch
   jj rebase -d main@origin
   ```

2. **Check for available work:**
   ```bash
   bd ready
   ```

3. **Start new work:**
   ```bash
   jj new -m "Working on <description>"
   bd update <id> --status in_progress
   ```

## During Development

- JJ auto-tracks all file changes (no `git add` needed)
- Use `jj status` to see current changes
- Use `jj describe -m "msg"` to update the change description
- Create issues for discovered work: `bd create "description"`

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `jj git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up:
   ```bash
   bd create "Follow-up task description"
   ```

2. **Run quality gates** (if code changed):
   ```bash
   just test
   just fmt
   just lint
   ```

3. **Update issue status** - Close finished work, update in-progress items:
   ```bash
   bd close <id>
   bd update <id> --status blocked --reason "waiting on X"
   ```

4. **Commit and push** - This is MANDATORY:
   ```bash
   jj describe -m "Final description of changes"
   jj bookmark set main -r @
   jj git push
   bd sync
   jj status  # MUST show clean working copy
   ```

5. **Verify** - All changes committed AND pushed:
   ```bash
   jj log --limit 3
   jj git fetch
   jj log -r 'main' -r 'main@origin'  # Should be same commit
   ```

6. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `jj git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

## JJ Tips

```bash
# Amend current change (just edit files, then optionally update description)
jj describe -m "Updated description"

# Split a change into multiple
jj split

# Squash into parent
jj squash

# Rebase onto latest main
jj git fetch && jj rebase -d main@origin

# View diff of current change
jj diff

# Abandon current change
jj abandon
```

## Beads Tips

```bash
# List all open issues
bd list

# Search issues
bd list --search "keyword"

# Add comment to issue
bd comment <id> "Comment text"

# View issue history
bd history <id>
```
