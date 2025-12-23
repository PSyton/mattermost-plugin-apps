# v2.0 Refactoring Documentation

## 📚 Documentation Index

### Planning & Design
- **[TODO.md](TODO.md)** - Complete implementation plan (16 stages) - **START HERE**
- **[MIGRATION.md](MIGRATION.md)** - Migration guide for app developers (to be created in Этап 15)
- **[CHANGELOG.md](CHANGELOG.md)** - Release notes (to be created in Этап 13)

### Development Guidelines
- **[.copilot-instructions.md](.copilot-instructions.md)** - Detailed coding guidelines and patterns
- **[.github/copilot-instructions.md](.github/copilot-instructions.md)** - Quick reference for GitHub Copilot
- **[DEVELOPMENT.md](DEVELOPMENT.md)** - Development workflow and quick start guide
- **[COMMIT_CHECKLIST.md](COMMIT_CHECKLIST.md)** - Pre-commit checklist and commit message templates

### Automation
- **[pre-commit-check.sh](pre-commit-check.sh)** - Automated verification script (run before every commit)

## 🎯 Quick Start

### For First-Time Contributors

1. **Read the plan:**
   ```bash
   cat TODO.md
   ```

2. **Setup environment:**
   ```bash
   git checkout -b feature/v2-refactoring
   ```

3. **Review guidelines:**
   ```bash
   cat .copilot-instructions.md
   ```

4. **Verify environment:**
   ```bash
   ./pre-commit-check.sh
   ```

5. **Start implementing** (see TODO.md for stage order)

### For Quick Reference

- ❓ **What to implement?** → [TODO.md](TODO.md)
- 💻 **How to code?** → [.copilot-instructions.md](.copilot-instructions.md)
- ✅ **Ready to commit?** → [COMMIT_CHECKLIST.md](COMMIT_CHECKLIST.md)
- 🚀 **Quick verification?** → Run `./pre-commit-check.sh`

## 🔑 Key Changes in v2.0

### Namespace
- `com.mattermost.apps` → **`com.2gis.apps`**
- This is a 2GIS fork with breaking changes

### Bindings Cache
- Client-initiated requests → **Server-side caching**
- Periodic refresh → **On-demand refresh only**
- Refresh triggers:
  - App install/uninstall/enable/disable
  - `RefreshBindings: true` in CallResponse
  - Admin manual command

### Health Check
- **MANDATORY** `/health` endpoint for all apps
- Automatic checks during inactivity (default: 5 minutes)
- Fixed path, no manifest configuration

### Locations
- Only **`/command`** supported
- Removed: post_menu, channel_header, in_post

### Forms
- Only **slash command autocomplete**
- Removed: Modal forms

## 📋 Critical Rules

### ✅ DO:
- Use `com.2gis.apps` everywhere
- Implement health check at `/health` path
- Update cache on-demand only
- Record activity on every app call
- Allow only `/command` location
- Use `path.Health` constant
- Run `./pre-commit-check.sh` before commit

### ❌ DON'T:
- Use old namespace `com.mattermost.apps`
- Add periodic cache refresh
- Check `app.OnHealthCheck` in manifest
- Allow post_menu/channel_header locations
- Add modal form support
- Use `BindingsCacheInterval` config

## 🔄 Development Workflow

```
1. Read TODO.md stage
   ↓
2. Write code following .copilot-instructions.md
   ↓
3. Test: make test
   ↓
4. Verify: ./pre-commit-check.sh
   ↓
5. Commit with proper message (see COMMIT_CHECKLIST.md)
   ↓
6. Repeat for next stage
```

## 📦 Implementation Stages (Summary)

1. **Этап 1:** Health check configuration
2. **Этап 2:** Bindings cache service (on-demand)
3. **Этап 3:** Integrate cache in Proxy
4. **Этап 4:** Initialize cache on startup
5. **Этап 5:** Use cache in GetBindings
6. **Этап 6:** Refresh cache on app operations
7. **Этап 7:** Remove WebSocket events
8. **Этап 8:** Health Check implementation (MANDATORY)
9. **Этап 9:** Restrict locations to /command
10. **Этап 10:** Simplify Form model
11. **Этап 11:** Update binding.go documentation
12. **Этап 12:** Admin refresh endpoint
13. **Этап 13:** Change namespace to com.2gis.apps
14. **Этап 14:** Update tests
15. **Этап 15:** Migration documentation
16. **Этап 16:** Final verification

**Total: 16 stages**

See [TODO.md](TODO.md) for detailed implementation instructions.

## 🛠 Quick Commands

```bash
# Verify before commit
./pre-commit-check.sh

# Run tests
make test

# Format code
go fmt ./...

# Check old namespace (should be 0)
grep -r "com\.mattermost\.apps\"" --include="*.go" | grep -v "2gis" | wc -l

# Check new namespace (should be >0 after Этап 13)
grep -r "com\.2gis\.apps" --include="*.go" | wc -l

# Check no periodic refresh (should be 0)
grep -r "BindingsCacheInterval" --include="*.go" | wc -l

# Check health check (should be 0)
grep -r "OnHealthCheck.*nil" --include="*.go" | wc -l
```

## 📊 Progress Tracking

Track your progress through the stages:

- [ ] Этап 1: Health check config
- [ ] Этап 2: Cache service
- [ ] Этап 3: Cache integration
- [ ] Этап 4: Cache initialization
- [ ] Этап 5: Use cache
- [ ] Этап 6: Refresh triggers
- [ ] Этап 7: Remove WebSocket
- [ ] Этап 8: Health Check
- [ ] Этап 9: Restrict locations
- [ ] Этап 10: Simplify forms
- [ ] Этап 11: Update docs
- [ ] Этап 12: Admin endpoint
- [ ] Этап 13: Namespace change
- [ ] Этап 14: Tests
- [ ] Этап 15: Migration doc
- [ ] Этап 16: Final check

## 🤖 Using GitHub Copilot

GitHub Copilot has access to:
- `.github/copilot-instructions.md` (quick reference)
- `.copilot-instructions.md` (detailed guidelines)
- `TODO.md` (implementation plan)

When asking Copilot for help:
1. Mention the stage number (Этап X)
2. Reference the relevant section in TODO.md
3. Copilot will follow the guidelines automatically

Example prompts:
- "Implement Этап 2.3 - refresh cache method"
- "Add health check constant according to Этап 8.1"
- "Update namespace in tests for Этап 13"

## 📞 Getting Help

1. **For implementation details:** Read [TODO.md](TODO.md)
2. **For coding patterns:** Read [.copilot-instructions.md](.copilot-instructions.md)
3. **For commit guidelines:** Read [COMMIT_CHECKLIST.md](COMMIT_CHECKLIST.md)
4. **For workflow help:** Read [DEVELOPMENT.md](DEVELOPMENT.md)
5. **For quick reference:** Check [.github/copilot-instructions.md](.github/copilot-instructions.md)

## ⚠️ Important Notes

- This is a **2GIS fork** of Mattermost Apps Plugin
- Version: **2.0.0** (major breaking changes)
- Plugin ID: **com.2gis.apps**
- **Cannot upgrade in-place** - requires full reinstall
- All apps must be updated for v2.0
- Health check is **MANDATORY** for all apps

## 🚀 Ready to Start?

1. ✅ Read [TODO.md](TODO.md) summary
2. ✅ Review [.copilot-instructions.md](.copilot-instructions.md) critical rules
3. ✅ Run `./pre-commit-check.sh` to verify environment
4. ✅ Create feature branch: `git checkout -b feature/v2-refactoring`
5. ✅ Start with Этап 13 (namespace) or Этап 1 (see TODO.md for recommendations)

**Good luck with the implementation!** 🎉

---

*Last updated: December 23, 2025*
