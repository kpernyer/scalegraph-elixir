# Git Workflow Guide for Scalegraph

This document describes how we handle Git branching and larger changes in the Scalegraph project.

## Overview

Even though you're currently working alone, it's important to establish a good Git workflow from the start. This makes it easy when more developers join and ensures a clean history.

## Branching Strategy

### Main Branches

- **`main`** - The main branch, always stable and deployable
  - All commits on `main` should be tested and working
  - Use `main` as the base for new feature branches

### Feature Branches

For larger changes, create a feature branch:

```bash
# Create and switch to new feature branch
git checkout -b feature/ledger-redesign

# Work on changes...
# Commit regularly with descriptive messages

# When done, merge back to main
git checkout main
git merge feature/ledger-redesign
git push origin main
```

### Naming Conventions

Use descriptive names for branches:

- `feature/ledger-redesign` - New feature
- `fix/transaction-bug` - Bugfix
- `refactor/error-handling` - Refactoring
- `docs/api-documentation` - Documentation
- `chore/dependency-update` - Maintenance

## Workflow for Larger Changes

### 1. Plan the Change

Before you start:
- [ ] Write a brief description of what should be changed
- [ ] Identify which files will be affected
- [ ] Consider if the change can be split into smaller commits

### 2. Create Feature Branch

```bash
# Make sure main is up to date
git checkout main
git pull origin main

# Create new branch
git checkout -b feature/branch-name

# Verify you're on the right branch
git branch
```

### 3. Work in Feature Branch

**Make small, logical commits:**
```bash
# Commit related changes together
git add lib/scalegraph/ledger/core.ex
git commit -m "feat: add transaction validation logic"

# Separate large changes into multiple commits
git add lib/scalegraph/business/contracts.ex
git commit -m "feat: add contract layer for business logic"
```

**Good commit messages:**
- Use prefixes: `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`
- Describe WHAT changed, not HOW
- Examples:
  - ✅ `feat: add contract layer for business transactions`
  - ✅ `fix: handle edge case in transaction validation`
  - ❌ `updated files`
  - ❌ `fix bug`

### 4. Regularly Sync with Main

If you work on a branch for a long time, sync regularly with main:

```bash
# Fetch latest changes from main
git fetch origin

# Merge main into your feature branch
git merge origin/main

# Or rebase (for cleaner history, but more advanced)
git rebase origin/main
```

### 5. When the Change is Complete

**Before merge:**
```bash
# Run all tests
just test

# Check formatting
just fmt

# Run linter
just lint

# Verify everything works
just run  # Start server and test manually
```

**Merge to main:**
```bash
# Switch to main
git checkout main

# Fetch latest changes
git pull origin main

# Merge feature branch
git merge feature/branch-name

# Push to remote
git push origin main

# Delete feature branch (local and remote)
git branch -d feature/branch-name
git push origin --delete feature/branch-name
```

## Handling Uncommitted Changes

### If you already have changes on main

If you have uncommitted changes on `main` and want to move them to a feature branch:

```bash
# Save your changes temporarily
git stash

# Create and switch to feature branch
git checkout -b feature/branch-name

# Restore your changes
git stash pop

# Now you can commit on feature branch
git add .
git commit -m "feat: description of changes"
```

**Alternative: Commit directly on main, then move:**
```bash
# Commit on main
git add .
git commit -m "WIP: work in progress"

# Create feature branch (keeps commit)
git checkout -b feature/branch-name

# Go back to main and remove commit
git checkout main
git reset --hard HEAD~1

# Switch back to feature branch
git checkout feature/branch-name
```

## Best Practices

### 1. Commit Often

- Commit when a logical part is complete
- Small commits are easier to review and revert
- Use `git commit --amend` to update the last commit if you forgot something

### 2. Keep Branches Short

- Merge to main as soon as the feature is complete
- Avoid long-lived branches (more than 1-2 weeks)
- If a branch becomes too large, consider splitting it

### 3. Use Descriptive Messages

```bash
# Good
git commit -m "feat: add contract layer for business transactions

- Separate business logic from ledger layer
- Add contract validation
- Update transaction flow to use contracts"

# Less good
git commit -m "updates"
```

### 4. Test Before Merge

Always test before merging to main:
- Run all tests
- Verify formatting and linting
- Test manually if possible

### 5. Document Larger Changes

For larger changes, create or update documentation:
- Update `ARCHITECTURE.md` if architecture changes
- Update `README.md` if APIs or usage changes
- Create `docs/` files for new features

## When More Developers Join

### Pull Requests (for the future)

When you become several, use Pull Requests:

1. Create feature branch (as above)
2. Push to remote: `git push origin feature/branch-name`
3. Create Pull Request on GitHub/GitLab
4. Discuss and review changes
5. Merge when approved

### Code Review Checklist

- [ ] Code follows `CONVENTIONS.md`
- [ ] All tests pass
- [ ] Formatting and linting are OK
- [ ] Documentation is updated
- [ ] No hardcoded values or secrets
- [ ] Error handling is correct

## Common Commands

```bash
# See status
git status

# See which files changed
git diff

# See commit history
git log --oneline --graph

# See which branches exist
git branch -a

# Delete local branch
git branch -d feature/branch-name

# Delete remote branch
git push origin --delete feature/branch-name

# Undo last commit (keep changes)
git reset --soft HEAD~1

# Undo last commit (discard changes)
git reset --hard HEAD~1

# See differences between branches
git diff main..feature/branch-name
```

## Example: Larger Refactoring

Let's say you're going to refactor the ledger layer:

```bash
# 1. Update main
git checkout main
git pull origin main

# 2. Create feature branch
git checkout -b refactor/ledger-separation

# 3. Work in multiple commits
git add lib/scalegraph/ledger/core.ex
git commit -m "refactor: extract transaction validation"

git add lib/scalegraph/business/contracts.ex
git commit -m "feat: add business contract layer"

git add docs/LEDGER_DESIGN.md
git commit -m "docs: document ledger/business separation"

# 4. Test
just test
just fmt
just lint

# 5. Merge to main
git checkout main
git merge refactor/ledger-separation
git push origin main

# 6. Clean up
git branch -d refactor/ledger-separation
```

## Summary

- **Use feature branches for larger changes**
- **Commit often with descriptive messages**
- **Test before merging to main**
- **Keep main stable and deployable**
- **Document larger changes**

This gives you a clean history and makes it easy to work together when more developers join!
