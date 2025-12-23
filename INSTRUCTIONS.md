# 📚 v2.0 Refactoring - Complete Instructions

Welcome to the Mattermost Apps Plugin v2.0 refactoring project (2GIS Fork).

## 🚀 Quick Start (5 Minutes)

1. **Setup environment:**
   ```bash
   ./setup-dev.sh
   ```

2. **Read the plan:**
   ```bash
   cat TODO.md | less
   ```

3. **Start coding** following [.copilot-instructions.md](.copilot-instructions.md)

## 📖 Documentation

### Essential Reading
- **[DOCS_INDEX.md](DOCS_INDEX.md)** - Documentation index and overview ⭐
- **[TODO.md](TODO.md)** - Complete 16-stage implementation plan ⭐
- **[.copilot-instructions.md](.copilot-instructions.md)** - Detailed coding guidelines ⭐

### Development
- **[DEVELOPMENT.md](DEVELOPMENT.md)** - Development workflow
- **[COMMIT_CHECKLIST.md](COMMIT_CHECKLIST.md)** - Pre-commit checklist
- **[pre-commit-check.sh](pre-commit-check.sh)** - Automated verification

### For GitHub Copilot
- **[.github/copilot-instructions.md](.github/copilot-instructions.md)** - Quick reference

## 🎯 What's Changing in v2.0

| Aspect | v1.x | v2.0 |
|--------|------|------|
| **Plugin ID** | `com.mattermost.apps` | `com.2gis.apps` ⚠️ |
| **Bindings** | Client requests | Server cache (on-demand) |
| **Health Check** | Optional | **Mandatory** `/health` |
| **Locations** | Multiple | Only `/command` |
| **Forms** | Modals + Commands | Commands only |

⚠️ **Breaking Change:** Full reinstall required, cannot upgrade in-place

## 💻 Development Commands

```bash
# Setup (run once)
./setup-dev.sh

# Before commit
./pre-commit-check.sh

# Tests
make test

# Build
go build ./...

# Format
go fmt ./...
```

## ✅ Pre-Commit Checklist

- [ ] Code compiles (`go build ./...`)
- [ ] Tests pass (`make test`)
- [ ] Pre-commit check passes (`./pre-commit-check.sh`)
- [ ] Commit message follows template (see COMMIT_CHECKLIST.md)
- [ ] No old namespace references
- [ ] No periodic cache refresh code

## 🔑 Critical Rules

### ✅ DO:
- Use `com.2gis.apps` namespace
- Make health check mandatory at `/health`
- Update cache on-demand only
- Allow only `/command` location

### ❌ DON'T:
- Use old namespace
- Add periodic refresh
- Check `app.OnHealthCheck` in manifest
- Allow post_menu/channel_header

## 📋 Implementation Stages

**Recommended Order:**

**Option 1: Namespace First (Recommended)**
1. Этап 13: Change namespace to com.2gis.apps
2. Этапы 1-12: Implement features
3. Этапы 14-16: Tests and docs

**Option 2: Features First**
1. Этапы 1-12: Implement features
2. Этап 13: Change namespace
3. Этапы 14-16: Tests and docs

See [TODO.md](TODO.md) for detailed stage descriptions.

## 🛠 Troubleshooting

### Tests failing?
```bash
go test -v ./... 2>&1 | tee test-output.log
```

### Old namespace still present?
```bash
grep -r "com\.mattermost\.apps\"" --include="*.go" | grep -v "2gis"
```

### Compilation errors?
```bash
go clean -cache && go build ./...
```

## 📞 Getting Help

1. Check [DOCS_INDEX.md](DOCS_INDEX.md) for documentation overview
2. Read relevant section in [TODO.md](TODO.md)
3. Check [.copilot-instructions.md](.copilot-instructions.md) for patterns
4. Review [COMMIT_CHECKLIST.md](COMMIT_CHECKLIST.md) for requirements

## 🤖 Using GitHub Copilot

Copilot has access to all instructions. Just mention the stage:

```
"Implement Этап 8.3 - activity tracker"
"Add health check constant for Этап 8.1"
"Update namespace in tests according to Этап 13"
```

## 📊 Progress Tracking

Copy this checklist to track your progress:

```
Progress: [====------] 40%

✅ Этап 1: Health check config
✅ Этап 2: Cache service  
✅ Этап 3: Cache integration
✅ Этап 4: Cache init
✅ Этап 5: Use cache
✅ Этап 6: Refresh triggers
⏳ Этап 7: Remove WebSocket (IN PROGRESS)
⬜ Этап 8: Health Check
⬜ Этап 9: Restrict locations
⬜ Этап 10: Simplify forms
⬜ Этап 11: Update docs
⬜ Этап 12: Admin endpoint
⬜ Этап 13: Namespace
⬜ Этап 14: Tests
⬜ Этап 15: Migration doc
⬜ Этап 16: Final check
```

## 🎓 Learning Resources

### First Time?
1. Read [DOCS_INDEX.md](DOCS_INDEX.md) overview
2. Skim [TODO.md](TODO.md) to understand scope
3. Read [DEVELOPMENT.md](DEVELOPMENT.md) for workflow
4. Run `./setup-dev.sh` to setup environment

### Ready to Code?
1. Pick a stage from [TODO.md](TODO.md)
2. Follow patterns in [.copilot-instructions.md](.copilot-instructions.md)
3. Test frequently (`make test`)
4. Verify before commit (`./pre-commit-check.sh`)

### Before Committing?
1. Run `./pre-commit-check.sh`
2. Check [COMMIT_CHECKLIST.md](COMMIT_CHECKLIST.md)
3. Use proper commit message format

## ⚠️ Important Notes

- This is a **2GIS fork**, not official Mattermost
- Version **2.0.0** with major breaking changes
- Plugin ID **com.2gis.apps** (not .v2!)
- **Cannot upgrade** - requires full reinstall
- All apps need updates for v2.0
- Health check is **mandatory**

## 🚀 Ready to Start?

```bash
# 1. Setup
./setup-dev.sh

# 2. Read plan
cat TODO.md | less

# 3. Start coding
# Follow TODO.md stage by stage

# 4. Before each commit
./pre-commit-check.sh
git add <files>
git commit -m "[Этап X] Description"

# 5. Done!
```

## 📚 Full Documentation List

- ⭐ **[DOCS_INDEX.md](DOCS_INDEX.md)** - Start here
- ⭐ **[TODO.md](TODO.md)** - Implementation plan
- ⭐ **[.copilot-instructions.md](.copilot-instructions.md)** - Coding guidelines
- 📖 **[DEVELOPMENT.md](DEVELOPMENT.md)** - Workflow
- ✅ **[COMMIT_CHECKLIST.md](COMMIT_CHECKLIST.md)** - Commit guide
- 🔧 **[setup-dev.sh](setup-dev.sh)** - Setup script
- 🔍 **[pre-commit-check.sh](pre-commit-check.sh)** - Verification
- 🪝 **[pre-commit-hook.sh](pre-commit-hook.sh)** - Git hook

---

**Questions?** Read [DOCS_INDEX.md](DOCS_INDEX.md) for complete documentation overview.

**Good luck!** 🎉
