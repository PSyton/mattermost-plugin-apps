# Development Guide for v2.0 Refactoring

## Quick Start

### Prerequisites
- Go 1.19+
- Make
- Git

### Setup Development Environment

1. **Clone and checkout feature branch:**
   ```bash
   git checkout -b feature/v2-refactoring
   ```

2. **Review the plan:**
   ```bash
   cat TODO.md
   ```

3. **Read Copilot instructions:**
   ```bash
   cat .copilot-instructions.md
   ```

## Development Workflow

### Before Starting Work

1. Read the relevant stage in `TODO.md`
2. Check `.copilot-instructions.md` for coding guidelines
3. Ensure you understand the requirements

### During Development

1. Write code following the instructions
2. Test frequently:
   ```bash
   go test ./...
   ```

3. Run pre-commit checks:
   ```bash
   ./pre-commit-check.sh
   ```

### Before Committing

1. **Run verification script:**
   ```bash
   ./pre-commit-check.sh
   ```
   
   This will check:
   - ✅ Code compiles
   - ✅ Tests pass
   - ✅ No old namespace references
   - ✅ New namespace present (if applicable)
   - ✅ No periodic cache refresh
   - ✅ Health check correctly implemented
   - ✅ Code formatting
   - ✅ Go modules clean

2. **Stage your changes:**
   ```bash
   git add <files>
   ```

3. **Commit with proper message:**
   ```bash
   git commit
   ```
   
   Use the template from `COMMIT_CHECKLIST.md`:
   ```
   [Этап X] Brief description
   
   Detailed description:
   - What changed
   - Why changed
   - Any breaking changes
   
   Checklist:
   - [x] Code compiles
   - [x] Tests pass
   - [x] Pre-commit checks pass
   ```

## Key Files

- **TODO.md** - Complete implementation plan (16 stages)
- **.copilot-instructions.md** - Detailed coding guidelines
- **.github/copilot-instructions.md** - Quick reference for Copilot
- **COMMIT_CHECKLIST.md** - Checklist for each commit
- **pre-commit-check.sh** - Automated verification script

## Critical Rules

### 1. Namespace
- ✅ ALWAYS use `ru.2gis.apps`
- ❌ NEVER use `com.mattermost.apps` or `com.mattermost.apps.v2`

### 2. Bindings Cache
- ✅ On-demand refresh only
- ❌ NO periodic updates
- ❌ NO Start/Stop methods for periodic refresh

### 3. Health Check
- ✅ MANDATORY `/health` endpoint
- ✅ Fixed path `path.Health`
- ❌ NO checks for `app.OnHealthCheck`
- ❌ NO manifest configuration

### 4. Locations
- ✅ ONLY `/command` location
- ❌ NO post_menu, channel_header, in_post

### 5. Forms
- ✅ Slash command autocomplete only
- ❌ NO modal forms

## Testing

### Run all tests:
```bash
make test
```

### Run specific package tests:
```bash
go test ./server/proxy -v
```

### Run with coverage:
```bash
go test -cover ./...
```

### Run with race detection:
```bash
go test -race ./...
```

## Common Tasks

### Check old namespace:
```bash
grep -r "com\.mattermost\.apps\"" --include="*.go" | grep -v "2gis" | grep -v "CHANGELOG"
```

### Check for periodic refresh (should be zero):
```bash
grep -r "BindingsCacheInterval" --include="*.go"
```

### Check health check implementation:
```bash
grep -r "OnHealthCheck.*nil" --include="*.go"  # Should be zero
grep -r "path\.Health" --include="*.go"        # Should have results
```

### Format code:
```bash
go fmt ./...
```

### Update dependencies:
```bash
go mod tidy
```

## Troubleshooting

### Tests failing?
```bash
# Run verbose
go test -v ./... 2>&1 | tee test-output.log

# Check specific test
go test -v -run TestSpecificFunction ./server/proxy
```

### Compilation errors?
```bash
# Clean build cache
go clean -cache

# Rebuild
go build ./...
```

### Import issues?
```bash
go mod tidy
go mod vendor  # if using vendor
```

## Git Workflow

### Create feature branch:
```bash
git checkout -b feature/v2-refactoring
```

### Regular commits:
```bash
./pre-commit-check.sh  # Verify first
git add <files>
git commit -m "[Этап X] Description"
```

### Check status:
```bash
git status
git diff
git diff --staged
```

### View history:
```bash
git log --oneline
git log --graph --oneline --all
```

### Push to remote:
```bash
git push origin feature/v2-refactoring
```

## Stage-by-Stage Guide

### Start with Этап 13 (Namespace)
This is recommended as first step (atomic change):

1. Read Этап 13 in TODO.md
2. Update all files listed in 13.1-13.10
3. Run `./pre-commit-check.sh`
4. Commit: `[Этап 13] Change namespace to ru.2gis.apps`

### Then implement Этапы 1-12
Follow the order in TODO.md, making commits for each sub-stage.

### Finish with Этапы 14-16
Tests, documentation, and final verification.

## Getting Help

1. Check `TODO.md` for detailed instructions
2. Check `.copilot-instructions.md` for coding patterns
3. Check `COMMIT_CHECKLIST.md` for commit requirements
4. Use GitHub Copilot with context from these files

## Quick Commands Reference

```bash
# Verify everything before commit
./pre-commit-check.sh

# Run tests
make test

# Format code
go fmt ./...

# Build
go build ./...

# Check namespace
grep -r "com\.2gis\.apps" --include="*.go"

# Clean and rebuild
go clean -cache && go build ./...
```

## Documentation

- **TODO.md** - Implementation plan
- **MIGRATION.md** - Migration guide for app developers (to be created)
- **CHANGELOG.md** - Release notes (to be created)
- **.copilot-instructions.md** - Full development guidelines
- **COMMIT_CHECKLIST.md** - Commit requirements

## Notes

- Make frequent, logical commits
- Each commit should compile
- Use [Этап X] prefix in commit messages
- Document breaking changes
- Run pre-commit checks before every commit
- Keep commits focused on single concern

---

**Ready to start?**

1. Read TODO.md (at least the summary)
2. Run `./pre-commit-check.sh` to verify environment
3. Start with Этап 13 or Этап 1 (see TODO.md for order recommendations)

Good luck! 🚀
