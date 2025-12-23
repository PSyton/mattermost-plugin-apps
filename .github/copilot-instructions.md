# Copilot Instructions: Mattermost Apps Plugin v2.0 (2GIS Fork)

## Critical Rules

1. **Namespace**: ALWAYS use `ru.2gis.apps` (never `com.mattermost.apps` or `.v2`)
2. **NO Periodic Refresh**: Bindings cache updates only on-demand
3. **Health Check Mandatory**: All apps must implement `/health` endpoint
4. **Only /command**: No support for post_menu, channel_header, in_post
5. **No Modals**: Only slash command autocomplete

## Quick Reference

### Namespace Changes
```go
// plugin.json
"id": "ru.2gis.apps"

// apps/appclient/mattermost_client_pp.go
AppsPluginName = "ru.2gis.apps"

// All paths
"/plugins/ru.2gis.apps/apps/..."
```

### Health Check Pattern
```go
// Always use fixed path - no manifest checks!
healthCheckCall := apps.Call{
    Path: path.Health, // = "/health"
}
```

### Activity Tracking
```go
// Record on EVERY app call
p.activityTracker.RecordActivity(appID)
```

### Cache Refresh Triggers
- App install/uninstall/enable/disable
- `RefreshBindings: true` in CallResponse
- Admin manual command
- **NOT** periodic timer

## Common Mistakes

❌ `if app.OnHealthCheck != nil` - NO checks, always call /health  
❌ `Start()` method on bindingsCache - NO periodic updates  
❌ `com.mattermost.apps.v2` - Wrong namespace  
❌ `LocationPostMenu` allowed - Only /command  
❌ Modal form support - Removed  

## See Also

- `.copilot-instructions.md` - Full detailed instructions
- `TODO.md` - Complete implementation plan (16 stages)
- `MIGRATION.md` - Migration guide for app developers
