# План рефакторинга: Серверное кеширование bindings

## 🚨 КРИТИЧЕСКОЕ ИЗМЕНЕНИЕ: Plugin ID Change

**Plugin ID изменяется: `com.mattermost.apps` → `com.mattermost.apps.v2`**

Это означает:
- ❌ Невозможно обновить плагин in-place
- ✅ Требуется полная переустановка
- ✅ Автоматическая очистка клиентского кеша
- ✅ Явное обозначение breaking change
- ⚠️ Все приложения должны быть переустановлены

**См. Этап 12 для деталей реализации**

### Quick Reference: Что меняется

| Компонент | Старое значение | Новое значение |
|-----------|----------------|----------------|
| Plugin ID | `com.mattermost.apps` | `com.mattermost.apps.v2` |
| Версия | `1.2.2` | `2.0.0` |
| API Endpoints | `/plugins/com.mattermost.apps/api/v1/...` | `/plugins/com.mattermost.apps.v2/api/v1/...` |
| App URLs | `/plugins/com.mattermost.apps/apps/<id>/...` | `/plugins/com.mattermost.apps.v2/apps/<id>/...` |
| Константа в коде | `AppsPluginName = "com.mattermost.apps"` | `AppsPluginName = "com.mattermost.apps.v2"` |

### Файлы требующие обновления

- ✅ `plugin.json` - главный манифест (ID и version)
- ✅ `apps/appclient/mattermost_client_pp.go` - константа AppsPluginName
- ✅ `test/restapitest/helper.go` - pluginID в тестах
- ✅ `test/restapitest/*.go` - все пути в REST API тестах
- ✅ `test/e2e/**/*.ts` - все E2E тесты
- ✅ `README.md` - примеры использования
- ✅ `TODO.md` - этот файл (примеры в документации)

### Обоснование выбора ru.2gis.apps

- Использует доменную зону `.ru` для российской компании 2GIS
- Четко обозначает форк от оригинального Mattermost плагина
- Указывает на принадлежность 2GIS
- Соответствует naming conventions для plugin IDs (обратная доменная нотация)
- Более корректно с точки зрения географии и юрисдикции компании

---

## Цель
Переход от клиент-инициируемых запросов bindings к серверному кешированию с периодическим обновлением. Упрощение модели взаимодействия до поддержки только slash-команд с динамическими аргументами.

## Текущая проблема
- Каждый клиент (web/mobile) запрашивает bindings через `/api/v1/bindings`
- При N клиентах и M приложениях получается N×M запросов к приложениям
- Поддерживаются интерактивные элементы UI (channel_header, post_menu), которые не нужны
- Избыточная нагрузка на сервер и приложения

## Целевое состояние
- Bindings кешируются на сервере и обновляются по расписанию
- Поддержка только `/command` locations
- Lookup calls для динамических аргументов команд работают в реальном времени
- Принудительное обновление кеша при операциях с приложениями и по запросу

---

## Этап 1: Конфигурация кеширования

### 1.1 Добавить параметр в StoredConfig
**Файл:** `server/config/config.go`

**Действия:**
- Добавить поле `BindingsCacheIntervalSeconds *int` в структуру `StoredConfig`
- Добавить документацию к полю
- Значение по умолчанию: 60 секунд

**Код:**
```go
type StoredConfig struct {
    // ...existing fields...
    
    // BindingsCacheIntervalSeconds defines how often the server refreshes 
    // bindings cache from all installed apps. Default: 60 seconds.
    BindingsCacheIntervalSeconds *int `json:"bindings_cache_interval_seconds,omitempty"`
}
```

### 1.2 Добавить параметр в Config
**Файл:** `server/config/config.go`

**Действия:**
- Добавить поле `BindingsCacheInterval int` в структуру `Config` (не pointer, с дефолтным значением)

**Код:**
```go
type Config struct {
    StoredConfig
    
    // ...existing fields...
    
    // BindingsCacheInterval is the interval in seconds for refreshing bindings cache
    BindingsCacheInterval int
}
```

### 1.3 Инициализация конфигурации
**Файл:** `server/config/service.go`

**Действия:**
- В функции `newInitializedConfig()` добавить логику установки `BindingsCacheInterval`
- Если `conf.BindingsCacheIntervalSeconds != nil`, использовать это значение
- Иначе использовать константу `DefaultBindingsCacheInterval = 60`

**Код:**
```go
const DefaultBindingsCacheInterval = 60

func (s *service) newInitializedConfig(newStoredConfig StoredConfig, log utils.Logger) (*Config, error) {
    // ...existing code...
    
    if conf.BindingsCacheIntervalSeconds != nil {
        conf.BindingsCacheInterval = *conf.BindingsCacheIntervalSeconds
    } else {
        conf.BindingsCacheInterval = DefaultBindingsCacheInterval
    }
    
    // ...existing code...
}
```

---

## Этап 2: Сервис кеширования bindings

### 2.1 Создать структуры для кеша
**Файл:** `server/proxy/bindings_cache.go` (новый файл)

**Действия:**
- Создать структуру `bindingsCache` для хранения кешированных данных
- Добавить mutex для thread-safe доступа
- Добавить timestamp последнего обновления

**Код:**
```go
package proxy

import (
    "sync"
    "time"

    "github.com/mattermost/mattermost-plugin-apps/apps"
    "github.com/mattermost/mattermost-plugin-apps/server/incoming"
)

type bindingsCache struct {
    mutex       sync.RWMutex
    bindings    []apps.Binding
    lastUpdated time.Time
    updateError error
}

type bindingsCacheService struct {
    cache     *bindingsCache
    proxy     *Proxy
    stopChan  chan struct{}
    isRunning bool
    mutex     sync.Mutex
}
```

### 2.2 Инициализация сервиса кеша
**Файл:** `server/proxy/bindings_cache.go`

**Действия:**
- Создать функцию `newBindingsCacheService()`
- Инициализировать структуры

**Код:**
```go
func newBindingsCacheService(p *Proxy) *bindingsCacheService {
    return &bindingsCacheService{
        cache: &bindingsCache{
            bindings: []apps.Binding{},
        },
        proxy:    p,
        stopChan: make(chan struct{}),
    }
}
```

### 2.3 Метод получения кешированных bindings
**Файл:** `server/proxy/bindings_cache.go`

**Действия:**
- Реализовать метод `GetCachedBindings()` для thread-safe чтения

**Код:**
```go
func (bcs *bindingsCacheService) GetCachedBindings() ([]apps.Binding, time.Time, error) {
    bcs.cache.mutex.RLock()
    defer bcs.cache.mutex.RUnlock()
    
    // Возвращаем копию, чтобы избежать race conditions
    bindingsCopy := make([]apps.Binding, len(bcs.cache.bindings))
    copy(bindingsCopy, bcs.cache.bindings)
    
    return bindingsCopy, bcs.cache.lastUpdated, bcs.cache.updateError
}
```

### 2.4 Метод обновления кеша
**Файл:** `server/proxy/bindings_cache.go`

**Действия:**
- Реализовать метод `refreshCache()` для обновления bindings
- Вызывать `InvokeGetBindings` для каждого приложения
- Обновлять кеш и timestamp

**Код:**
```go
func (bcs *bindingsCacheService) refreshCache(r *incoming.Request, cc apps.Context) error {
    start := time.Now()
    log := r.Log.With("operation", "refresh_bindings_cache")
    
    // Получаем все включенные приложения
    allApps := bcs.proxy.store.App.AsList(store.EnabledAppsOnly)
    
    type result struct {
        appID    apps.AppID
        bindings []apps.Binding
        err      error
    }
    
    results := make(chan result, len(allApps))
    
    // Параллельно запрашиваем bindings у всех приложений
    for i := range allApps {
        go func(app apps.App) {
            appRequest := r.WithDestination(app.AppID)
            bindings, err := bcs.proxy.InvokeGetBindings(appRequest, cc)
            results <- result{
                appID:    app.AppID,
                bindings: bindings,
                err:      err,
            }
        }(allApps[i])
    }
    
    // Собираем результаты
    allBindings := []apps.Binding{}
    var updateError error
    
    for i := 0; i < len(allApps); i++ {
        res := <-results
        if res.err != nil {
            log.WithError(res.err).Debugf("failed to fetch bindings for app %s", res.appID)
            if updateError == nil {
                updateError = res.err
            }
        } else {
            allBindings = mergeBindings(allBindings, res.bindings)
        }
    }
    
    // Сортируем bindings
    sortedBindings := SortTopBindings(allBindings)
    
    // Обновляем кеш
    bcs.cache.mutex.Lock()
    bcs.cache.bindings = sortedBindings
    bcs.cache.lastUpdated = time.Now()
    bcs.cache.updateError = updateError
    bcs.cache.mutex.Unlock()
    
    elapsed := time.Since(start)
    log.With("apps_count", len(allApps), "elapsed", elapsed.String()).
        Debugf("Bindings cache refreshed")
    
    return updateError
}
```

### 2.5 Метод принудительного обновления
**Файл:** `server/proxy/bindings_cache.go`

**Действия:**
- Реализовать публичный метод `RefreshCache()` для внешних вызовов

**Код:**
```go
// RefreshCache forces immediate cache refresh
func (bcs *bindingsCacheService) RefreshCache() {
    // Создаем служебный request для обновления кеша
    r := bcs.proxy.conf.NewIncomingRequest()
    r.Log = r.Log.With("source", "cache_refresh")
    
    // Контекст без привязки к конкретному пользователю/каналу
    cc := apps.Context{
        UserAgentContext: apps.UserAgentContext{
            AppID: apps.AppID("system"),
        },
    }
    
    err := bcs.refreshCache(r, cc)
    if err != nil {
        r.Log.WithError(err).Warnf("Failed to refresh bindings cache")
    }
}
```

### 2.6 Периодическое обновление
**Файл:** `server/proxy/bindings_cache.go`

**Действия:**
- Реализовать методы `Start()` и `Stop()` для запуска/остановки периодического обновления

**Код:**
```go
func (bcs *bindingsCacheService) Start() {
    bcs.mutex.Lock()
    defer bcs.mutex.Unlock()
    
    if bcs.isRunning {
        return
    }
    
    bcs.isRunning = true
    bcs.stopChan = make(chan struct{})
    
    // Первое обновление сразу при старте
    go bcs.RefreshCache()
    
    // Запускаем горутину для периодического обновления
    go bcs.runPeriodicRefresh()
}

func (bcs *bindingsCacheService) runPeriodicRefresh() {
    for {
        interval := time.Duration(bcs.proxy.conf.Get().BindingsCacheInterval) * time.Second
        
        select {
        case <-time.After(interval):
            bcs.RefreshCache()
        case <-bcs.stopChan:
            return
        }
    }
}

func (bcs *bindingsCacheService) Stop() {
    bcs.mutex.Lock()
    defer bcs.mutex.Unlock()
    
    if !bcs.isRunning {
        return
    }
    
    close(bcs.stopChan)
    bcs.isRunning = false
}
```

---

## Этап 3: Интеграция кеша в Proxy

### 3.1 Добавить поле в Proxy
**Файл:** `server/proxy/service.go`

**Действия:**
- Добавить поле `bindingsCache *bindingsCacheService` в структуру `Proxy`

**Код:**
```go
type Proxy struct {
    callOnceMutex *cluster.Mutex

    builtinUpstreams map[apps.AppID]upstream.Upstream

    conf           config.Service
    store          *store.Service
    httpOut        httpout.Service
    upstreams      sync.Map
    sessionService session.Service
    appservices    appservices.Service
    
    bindingsCache  *bindingsCacheService
}
```

### 3.2 Инициализация кеша при создании Proxy
**Файл:** `server/proxy/service.go`

**Действия:**
- В функции `NewService()` создать и инициализировать `bindingsCacheService`

**Код:**
```go
func NewService(conf config.Service, store *store.Service, mutex *cluster.Mutex, httpOut httpout.Service, sessionService session.Service, appservices appservices.Service) Service {
    p := &Proxy{
        callOnceMutex:  mutex,
        conf:           conf,
        store:          store,
        httpOut:        httpOut,
        sessionService: sessionService,
        appservices:    appservices,
        upstreams:      sync.Map{},
        builtinUpstreams: map[apps.AppID]upstream.Upstream{},
    }
    
    p.bindingsCache = newBindingsCacheService(p)
    
    return p
}
```

### 3.3 Добавить методы в интерфейс Proxy
**Файл:** `server/proxy/service.go`

**Действия:**
- Добавить метод `RefreshBindingsCache()` в интерфейс `Service` или создать отдельный интерфейс

**Код:**
```go
// Service interface
type Service interface {
    Admin
    API
    Notifier
    
    // Bindings cache management
    RefreshBindingsCache()
    StartBindingsCache()
    StopBindingsCache()
}
```

### 3.4 Реализовать методы управления кешем в Proxy
**Файл:** `server/proxy/bindings_cache.go` (добавить в конец)

**Действия:**
- Добавить методы-обертки для управления кешем

**Код:**
```go
// Proxy methods for cache management

func (p *Proxy) RefreshBindingsCache() {
    if p.bindingsCache != nil {
        p.bindingsCache.RefreshCache()
    }
}

func (p *Proxy) StartBindingsCache() {
    if p.bindingsCache != nil {
        p.bindingsCache.Start()
    }
}

func (p *Proxy) StopBindingsCache() {
    if p.bindingsCache != nil {
        p.bindingsCache.Stop()
    }
}
```

---

## Этап 4: Запуск кеша при старте плагина

### 4.1 Запустить кеш в OnActivate
**Файл:** `server/plugin.go`

**Действия:**
- В функции `OnActivate()` после инициализации proxy запустить кеш bindings
- Добавить логирование

**Код:**
```go
func (p *Plugin) OnActivate() (err error) {
    // ...existing code до инициализации proxy...
    
    p.proxy = proxy.NewService(p.conf, p.store, mutex, p.httpOut, p.sessionService, p.appservices)
    err = p.proxy.Configure(conf, log)
    if err != nil {
        return errors.Wrapf(err, "failed to initialize app proxy")
    }
    p.proxy.AddBuiltinUpstream(
        builtin.AppID,
        builtin.NewBuiltinApp(p.conf, p.proxy, p.appservices, p.httpOut, p.sessionService),
    )
    log.Debugf("initialized the app proxy")
    
    // Запускаем кеширование bindings
    p.proxy.StartBindingsCache()
    log.Debugf("started bindings cache with interval %d seconds", conf.BindingsCacheInterval)
    
    // ...existing code далее...
}
```

### 4.2 Остановить кеш в OnDeactivate
**Файл:** `server/plugin.go`

**Действия:**
- В функции `OnDeactivate()` остановить периодическое обновление кеша

**Код:**
```go
func (p *Plugin) OnDeactivate() error {
    conf := p.conf.Get()

    // Останавливаем кеш bindings
    if p.proxy != nil {
        p.proxy.StopBindingsCache()
    }

    p.conf.MattermostAPI().Frontend.PublishWebSocketEvent(
        config.WebSocketEventPluginDisabled,
        conf.GetPluginVersionInfo(),
        &model.WebsocketBroadcast{},
    )

    return nil
}
```

---

## Этап 5: Использование кеша в GetBindings

### 5.1 Переписать GetBindings для использования кеша
**Файл:** `server/proxy/bindings.go`

**Действия:**
- Изменить метод `GetBindings()` для возврата кешированных данных
- Убрать параллельные вызовы `InvokeGetBindings`
- Добавить fallback на старое поведение если кеш пуст

**Код:**
```go
// GetBindings returns cached bindings for all apps.
func (p *Proxy) GetBindings(r *incoming.Request, cc apps.Context) (ret []apps.Binding, err error) {
    start := time.Now()
    defer func() {
        log := r.Log.With("elapsed", time.Since(start).String())
        if err != nil {
            log.WithError(err).Warnf("GetBindings failed")
        } else {
            log.Debugf("GetBindings: returned cached bindings")
        }
    }()

    if err := r.Check(
        r.RequireActingUser,
    ); err != nil {
        return nil, err
    }

    // Получаем bindings из кеша
    bindings, lastUpdated, cacheErr := p.bindingsCache.GetCachedBindings()
    
    if cacheErr != nil {
        r.Log.WithError(cacheErr).Warnf("Cache has errors, but returning cached data")
    }
    
    // Проверяем возраст кеша
    cacheAge := time.Since(lastUpdated)
    if cacheAge > time.Minute*5 {
        r.Log.Warnf("Bindings cache is stale (age: %s)", cacheAge.String())
    }
    
    return bindings, cacheErr
}
```

### 5.2 Обновить комментарии в коде
**Файл:** `server/proxy/bindings.go`

**Действия:**
- Обновить комментарии к функции `GetBindings`
- Добавить note о том, что bindings теперь кешируются

---

## Этап 6: Принудительное обновление кеша при операциях

### 6.1 Обновление после install
**Файл:** `server/proxy/install.go`

**Действия:**
- Заменить `dispatchRefreshBindingsEvent()` на `RefreshBindingsCache()`

**Код:**
```go
// В конце функции InstallApp (или где вызывается dispatchRefreshBindingsEvent)
func (p *Proxy) InstallApp(...) {
    // ...existing code...
    
    // Было:
    // p.dispatchRefreshBindingsEvent(r.ActingUserID())
    
    // Стало:
    go p.RefreshBindingsCache()
    
    return app, md, nil
}
```

### 6.2 Обновление после uninstall
**Файл:** `server/proxy/uninstall.go`

**Действия:**
- Заменить `dispatchRefreshBindingsEvent()` на `RefreshBindingsCache()`

**Код:**
```go
func (p *Proxy) UninstallApp(...) {
    // ...existing code...
    
    // Было:
    // p.dispatchRefreshBindingsEvent(r.ActingUserID())
    
    // Стало:
    go p.RefreshBindingsCache()
    
    return md, nil
}
```

### 6.3 Обновление после enable/disable
**Файл:** `server/proxy/enable.go`

**Действия:**
- В функциях `EnableApp()` и `DisableApp()` заменить `dispatchRefreshBindingsEvent()` на `RefreshBindingsCache()`

**Код:**
```go
func (p *Proxy) EnableApp(...) {
    // ...existing code...
    
    // Было:
    // p.dispatchRefreshBindingsEvent(r.ActingUserID())
    
    // Стало:
    go p.RefreshBindingsCache()
    
    return md, nil
}

func (p *Proxy) DisableApp(...) {
    // ...existing code...
    
    // Было:
    // p.dispatchRefreshBindingsEvent(r.ActingUserID())
    
    // Стало:
    go p.RefreshBindingsCache()
    
    return md, nil
}
```

### 6.4 Обновление при CallResponse.RefreshBindings
**Файл:** `server/proxy/invoke_call.go`

**Действия:**
- Найти обработку `RefreshBindings` флага
- Заменить `dispatchRefreshBindingsEvent()` на `RefreshBindingsCache()`

**Код:**
```go
// В функции InvokeCall, где обрабатывается cresp.RefreshBindings
if cresp.RefreshBindings && r.ActingUserID() != "" {
    // Было:
    // p.dispatchRefreshBindingsEvent(r.ActingUserID())
    
    // Стало:
    go p.RefreshBindingsCache()
}
```

---

## Этап 7: Удаление WebSocket событий

### 7.1 Удалить константу WebSocketEventRefreshBindings
**Файл:** `server/config/constants.go`

**Действия:**
- Удалить или пометить как deprecated `WebSocketEventRefreshBindings`
- Добавить комментарий о deprecated

**Код:**
```go
// Удалить или заменить на:
// Deprecated: WebSocketEventRefreshBindings is no longer used. 
// Bindings are now cached server-side.
// const WebSocketEventRefreshBindings = "refresh_bindings"
```

### 7.2 Удалить метод dispatchRefreshBindingsEvent
**Файл:** `server/proxy/bindings.go`

**Действия:**
- Удалить или пометить как deprecated функцию `dispatchRefreshBindingsEvent()`

**Код:**
```go
// Удалить функцию:
// func (p *Proxy) dispatchRefreshBindingsEvent(userID string) {
//     if userID != "" {
//         p.conf.MattermostAPI().Frontend.PublishWebSocketEvent(
//             config.WebSocketEventRefreshBindings, map[string]any{}, &model.WebsocketBroadcast{UserId: userID})
//     }
// }
```

### 7.3 Удалить WebSocket события из OAuth2
**Файл:** `server/appservices/oauth2.go`

**Действия:**
- Заменить `PublishWebSocketEvent(WebSocketEventRefreshBindings)` на вызов `RefreshBindingsCache()`
- Потребуется добавить ссылку на proxy в AppServices или использовать другой механизм

**Варианты:**
1. Добавить метод в интерфейс `Caller` для обновления кеша
2. Использовать event bus или pub/sub
3. Просто удалить вызовы, т.к. кеш обновляется периодически

**Рекомендуемый код (вариант 1):**
```go
// В server/appservices/service.go добавить в интерфейс Caller:
type Caller interface {
    // ...existing methods...
    RefreshBindingsCache()
}

// В server/appservices/oauth2.go:
// Было:
// r.Config().MattermostAPI().Frontend.PublishWebSocketEvent(
//     config.WebSocketEventRefreshBindings, map[string]any{}, &model.WebsocketBroadcast{})

// Стало:
if a.caller != nil {
    go a.caller.RefreshBindingsCache()
}
```

---

## Этап 8: Ограничение locations до /command

### 8.1 Обновить константы locations
**Файл:** `apps/locations.go`

**Действия:**
- Добавить комментарии о deprecated locations
- Оставить константы для обратной совместимости, но пометить их

**Код:**
```go
const (
    // Deprecated: LocationPostMenu is no longer supported. Only /command is allowed.
    LocationPostMenu      Location = "/post_menu"
    
    // Deprecated: LocationChannelHeader is no longer supported. Only /command is allowed.
    LocationChannelHeader Location = "/channel_header"
    
    // LocationCommand is the only supported location for app bindings.
    LocationCommand       Location = "/command"
    
    // Deprecated: LocationInPost is no longer supported. Only /command is allowed.
    LocationInPost        Location = "/in_post"
)
```

### 8.2 Обновить валидацию IsTop
**Файл:** `apps/locations.go`

**Действия:**
- Изменить метод `IsTop()` для возврата true только для `/command`

**Код:**
```go
func (l Location) IsTop() bool {
    switch l {
    case LocationCommand:
        return true
    // Deprecated locations
    case LocationChannelHeader,
        LocationPostMenu:
        return false
    }
    return false
}
```

### 9.3 Добавить валидацию в cleanAppBinding
**Файл:** `server/proxy/invoke_bindings.go`

**Действия:**
- В функции `cleanAppBinding()` добавить проверку на запрещенные locations
- Возвращать ошибку если location не `/command`

**Код:**
```go
func cleanAppBinding(
    app *apps.App,
    b apps.Binding,
    locPrefix apps.Location,
    userAgent string,
    conf config.Config,
) (*apps.Binding, error) {
    // ...existing code...
    
    // Проверяем, что это top-level binding
    if locPrefix == "" && b.Location.IsTop() {
        // Разрешаем только /command
        if b.Location != apps.LocationCommand {
            return nil, errors.Errorf(
                "%s: location %s is no longer supported, only /command is allowed", 
                b.Location, 
                b.Location,
            )
        }
    }
    
    // ...existing code...
}
```

### 8.4 Обновить валидацию манифеста
**Файл:** `apps/manifest.go`

**Действия:**
- Найти валидацию `RequestedLocations` в методе `Validate()`
- Добавить проверку что только `/command` разрешен

**Код:**
```go
func (m *Manifest) Validate() error {
    // ...existing code...
    
    // Validate requested locations
    for _, loc := range m.RequestedLocations {
        if loc != LocationCommand {
            return errors.Errorf(
                "requested location %s is not supported, only /command is allowed",
                loc,
            )
        }
    }
    
    // ...existing code...
}
```

---

## Этап 9: Упрощение Form модели

### 9.1 Пометить modal-специфичные поля как deprecated
**Файл:** `apps/form.go`

**Действия:**
- Добавить комментарии о deprecated полях
- Оставить поля для обратной совместимости

**Код:**
```go
type Form struct {
    Source *Call `json:"source,omitempty"`

    // Deprecated: Title is no longer used as modals are not supported.
    // Only slash commands with autocomplete are supported.
    Title  string `json:"title,omitempty"`
    
    // Deprecated: Header is no longer used as modals are not supported.
    Header string `json:"header,omitempty"`
    
    // Deprecated: Footer is no longer used as modals are not supported.
    Footer string `json:"footer,omitempty"`

    Icon string `json:"icon,omitempty"`

    // Submit is the call to make when the user submits the command.
    Submit *Call `json:"submit,omitempty"`

    // Deprecated: SubmitButtons are no longer used as modals are not supported.
    SubmitButtons string `json:"submit_buttons,omitempty"`

    // Fields is the list of fields in the form, used for command autocomplete.
    Fields []Field `json:"fields,omitempty"`
}
```

### 9.2 Обновить документацию Form
**Файл:** `apps/form.go`

**Действия:**
- Обновить комментарий к структуре Form
- Указать что поддерживается только Autocomplete для команд

**Код:**
```go
// Form defines what inputs a Call accepts and how they are gathered from the user
// in Autocomplete mode for slash commands.
//
// IMPORTANT: update UnmarshalJSON if this struct changes.
//
// For Autocomplete, a form can be bound to a sub-command. The form defines the
// autocomplete behavior once the subcommand is selected. Dynamic select fields
// are supported via lookup calls.
//
// A form can be dynamically fetched if it specifies its Source. Source may
// include Expand and State, allowing to create custom-fit forms for the context.
//
// Note: Modal forms are no longer supported. Only slash command autocomplete is available.
type Form struct {
    // ...
}
```

### 9.3 Сохранить поддержку DynamicSelect
**Файл:** `apps/field.go`

**Действия:**
- Убедиться что `FieldTypeDynamicSelect` и `SelectDynamicLookup` не помечены как deprecated
- Добавить комментарии о поддержке lookup для команд

**Код:**
```go
const (
    // ...existing types...
    
    // FieldTypeDynamicSelect's options are fetched by making a lookup call.
    // This is supported for slash command autocomplete.
    FieldTypeDynamicSelect FieldType = "dynamic_select"
    
    // ...
)

type Field struct {
    // ...existing fields...
    
    // SelectDynamicLookup is the call that will return the options to populate
    // the select field. This is used for slash command autocomplete.
    SelectDynamicLookup *Call `json:"lookup,omitempty"`
    
    // ...
}
```

---

## Этап 10: Обновление документации в binding.go

### 10.1 Обновить комментарии к Binding
**Файл:** `apps/binding.go`

**Действия:**
- Обновить документацию в начале файла
- Указать что поддерживается только `/command`
- Удалить примеры с channel_header и post_menu

**Код:**
```go
// Binding is the principal way for an App to attach its functionality to the
// Mattermost UI. An App binds to the /command location by implementing the
// (mandatory) "bindings" call.
//
// # Mattermost Command Bindings
//
// An App returns its bindings in response to the "bindings" call, that it must
// implement, and can customize in its Manifest. The bindings call returns a tree 
// of app's bindings, organized by the /command location.
//
// Note: Only /command location is supported. Other locations (post_menu, 
// channel_header, in_post) are deprecated and no longer functional.
//
// Top level bindings need to define:
//   - location - must be "/command"
//   - bindings - an array of command bindings
//
// /command bindings can define "inner" subcommands that are collections of more
// bindings/subcommands, and "outer" subcommands that implement forms and can be
// executed. It is not possible to have command bindings that have subcommands
// and flags. It is possible to have positional parameters in an outer
// subcommand, accomplishing similar user experience.
//
// Inner command bindings need to define:
//   - label - the label for the command itself.
//   - location - the location of the command, defaults to label.
//   - hint - Hint line in autocomplete.
//   - description - description line in autocomplete.
//   - bindings - subcommands
//
// Outer command bindings need to define:
//   - label - the label for the command itself.
//   - location - the location of the command, defaults to label.
//   - hint - Hint line in autocomplete.
//   - description - description line in autocomplete.
//   - call or form - either embed a form, or provide a call to fetch it.
//
// Bindings are cached server-side and refreshed periodically (default: 60 seconds).
// Apps can request cache refresh by returning RefreshBindings: true in CallResponse.
//
// Example bindings (hello world app) creates a "/helloworld send" command:
//
//	{
//	    "type": "ok",
//	    "data": [
//	        {
//	            "location": "/command",
//	            "bindings": [
//	                {
//	                    "icon": "icon.png",
//	                    "label": "helloworld",
//	                    "description": "Hello World app",
//	                    "hint": "[send]",
//	                    "bindings": [
//	                        {
//	                            "location": "send",
//	                            "label": "send",
//	                            "call": {
//	                                "path": "/send"
//	                            }
//	                        }
//	                    ]
//	                }
//	            ]
//	        }
//	    ]
//	}
```

### 10.2 Удалить секции о deprecated locations
**Файл:** `apps/binding.go`

**Действия:**
- Удалить или закомментировать секции:
  - `/post_menu bindings need to define:`
  - `/channel_header bindings need to define:`
  - `# In-post Bindings`
- Оставить только документацию по `/command`

---

## Этап 11: Добавление admin endpoint для refresh

### 11.1 Создать HTTP handler для refresh
**Файл:** `server/httpin/bindings.go`

**Действия:**
- Добавить функцию `RefreshBindings()` для принудительного обновления кеша
- Требовать admin права

**Код:**
```go
// RefreshBindings forces immediate bindings cache refresh.
//
//	Path: /api/v1/bindings/refresh
//	Method: POST
//	Input: none
//	Output: {"status": "ok", "message": "cache refresh triggered"}
func (s *Service) RefreshBindings(r *incoming.Request, w http.ResponseWriter, req *http.Request) {
    // Проверяем права администратора
    if err := r.Check(
        r.RequireActingUser,
        r.RequireActingUserSystemAdmin,
    ); err != nil {
        httputils.WriteError(w, err)
        return
    }
    
    r.Log.Debugf("Manual bindings cache refresh requested by %s", r.ActingUserID())
    
    // Запускаем обновление в фоне
    go s.Proxy.RefreshBindingsCache()
    
    response := map[string]string{
        "status":  "ok",
        "message": "Bindings cache refresh triggered",
    }
    
    _ = httputils.WriteJSON(w, response)
}
```

### 11.2 Зарегистрировать endpoint
**Файл:** `server/httpin/service.go`

**Действия:**
- Добавить роут для `/bindings/refresh`

**Код:**
```go
// В функции где регистрируются routes
func (s *Service) initRoutes() {
    // ...existing routes...
    
    h.HandleFunc(path.Bindings, h.GetBindings).Methods(http.MethodGet)
    h.HandleFunc(path.Bindings+"/refresh", h.RefreshBindings).Methods(http.MethodPost)
    
    // ...
}
```

### 11.3 Добавить slash команду для refresh
**Файл:** `server/builtin/bindings.go`

**Действия:**
- Добавить команду `/apps refresh-bindings` в builtin app

**Код:**
```go
func (a *builtinApp) getBindings(creq apps.CallRequest, loc *i18n.Localizer) []apps.Binding {
    commands := []apps.Binding{
        a.infoCommandBinding(loc),
    }

    if creq.Context.ActingUser != nil && creq.Context.ActingUser.IsSystemAdmin() {
        if a.conf.Get().DeveloperMode {
            commands = append(commands, a.debugCommandBinding(loc))
        }
        commands = append(commands,
            a.disableCommandBinding(loc),
            a.enableCommandBinding(loc),
            a.installCommandBinding(loc),
            a.listCommandBinding(loc),
            a.uninstallCommandBinding(loc),
            a.settingsCommandBinding(loc),
            a.refreshBindingsCommandBinding(loc), // <-- НОВАЯ КОМАНДА
        )
    }
    
    // ...
}
```

### 11.4 Создать handler для команды
**Файл:** `server/builtin/refresh_bindings.go` (новый файл)

**Действия:**
- Создать binding и handler для команды refresh-bindings

**Код:**
```go
package builtin

import (
    "github.com/nicksnyder/go-i18n/v2/i18n"

    "github.com/mattermost/mattermost-plugin-apps/apps"
    "github.com/mattermost/mattermost-plugin-apps/server/incoming"
)

func (a *builtinApp) refreshBindingsCommandBinding(loc *i18n.Localizer) apps.Binding {
    return apps.Binding{
        Location: "refresh-bindings",
        Label:    "refresh-bindings",
        Description: a.conf.I18N().LocalizeDefaultMessage(loc, &i18n.Message{
            ID:    "command.refresh-bindings.description",
            Other: "Force immediate refresh of bindings cache",
        }),
        Call: apps.NewCall(PathRefreshBindings),
    }
}

func (a *builtinApp) refreshBindings(r *incoming.Request, creq apps.CallRequest) apps.CallResponse {
    if !creq.Context.ActingUser.IsSystemAdmin() {
        return apps.NewErrorResponse(apps.NewForbiddenError("must be system admin"))
    }
    
    a.proxy.RefreshBindingsCache()
    
    return apps.NewTextResponse("Bindings cache refresh triggered. Cache will be updated shortly.")
}
```

### 11.5 Зарегистрировать handler
**Файл:** `server/builtin/app.go`

**Действия:**
- Добавить константу пути и регистрацию handler

**Код:**
```go
const (
    // ...existing paths...
    PathRefreshBindings = "/refresh-bindings"
)

func (a *builtinApp) Call(r *incoming.Request, creq apps.CallRequest) apps.CallResponse {
    // ...existing switch cases...
    
    case PathRefreshBindings:
        return a.refreshBindings(r, creq)
    
    // ...
}
```

---

## Этап 12: Изменение namespace и версии плагина

### 12.1 Изменить ID плагина в plugin.json
**Файл:** `plugin.json`

**Действия:**
- Изменить `id` с `com.mattermost.apps` на `ru.2gis.apps`
- Это важно для избежания проблем с кешированием на клиентах
- Клиентский код не будет запрашивать старые endpoints
- Подчеркивает что это fork от оригинального плагина Mattermost

**Было:**
```json
{
  "id": "com.mattermost.apps",
  "version": "1.2.2",
  ...
}
```

**Стало:**
```json
{
  "id": "ru.2gis.apps",
  "version": "2.0.0",
  ...
}
```

### 13.2 Обновить константу в коде
**Файл:** `apps/appclient/mattermost_client_pp.go`

**Действия:**
- Обновить константу `AppsPluginName`

**Код:**
```go
const (
    // AppsPluginName is the name of the Apps plugin
    AppsPluginName = "ru.2gis.apps"
)
```

### 13.3 Обновить тесты
**Файл:** `test/restapitest/helper.go`

**Действия:**
- Обновить `pluginID` в тестах

**Код:**
```go
var pluginID = "ru.2gis.apps"
```

### 13.4 Обновить пути в тестах
**Файлы:** 
- `test/restapitest/helper.go`
- `test/restapitest/webhook_test.go`
- `test/restapitest/echo.go`
- `test/restapitest/static.go`
- `test/restapitest/bindings.go`

**Действия:**
- Найти все пути с `/plugins/com.mattermost.apps/`
- Заменить на `/plugins/ru.2gis.apps/`

**Примеры:**
```go
// Было:
appPath := "/plugins/com.mattermost.apps/apps/" + string(app.AppID)

// Стало:
appPath := "/plugins/ru.2gis.apps/apps/" + string(app.AppID)
```

### 13.5 Обновить E2E тесты
**Файл:** `test/e2e/cypress/integration/bindings/channel_header_spec.ts`

**Действия:**
- Обновить plugin ID и пути в E2E тестах

**Код:**
```typescript
// Было:
cy.apiEnablePluginById('com.mattermost.apps');
cy.get('#channel-header img[src="http://localhost:8065/plugins/com.mattermost.apps/apps/hello-world/static/icon.png"]')

// Стало:
cy.apiEnablePluginById('ru.2gis.apps');
cy.get('#channel-header img[src="http://localhost:8065/plugins/ru.2gis.apps/apps/hello-world/static/icon.png"]')
```

### 13.6 Увеличить версию плагина
**Файл:** `plugin.json`

**Действия:**
- Увеличить major версию (breaking change)
- Установить версию 2.0.0

**Код:**
```json
{
  "id": "ru.2gis.apps",
  "version": "2.0.0",
  ...
}
```

### 13.7 Проверить использование namespace в других местах

**Действия:**
- Выполнить глобальный поиск `com.mattermost.apps` в кодовой базе
- Убедиться что все найденные вхождения обновлены или помечены как deprecated

**Команды для проверки:**
```bash
# Найти все вхождения старого plugin ID
grep -r "com.mattermost.apps" --include="*.go" --include="*.ts" --include="*.tsx" --include="*.json"

# Найти пути с плагином
grep -r "/plugins/com.mattermost.apps" --include="*.go" --include="*.ts" --include="*.tsx"
```

**Файлы требующие особого внимания:**
- `plugin.json` - главный манифест
- `apps/appclient/*.go` - константы для клиента
- `test/restapitest/*.go` - все тестовые пути
- `test/e2e/**/*.ts` - E2E тесты с URLs
- Любые примеры в `examples/` или документации
- README.md и другие markdown файлы с примерами

**Что НЕ нужно менять:**
- Комментарии в CHANGELOG о миграции со старого ID
- Исторические упоминания в документации (с пометкой "оригинальный Mattermost плагин")
- Код миграционных утилит, где старый ID используется для чтения

### 13.8 Обновить README и примеры

**Файл:** `README.md`

**Действия:**
- Обновить все примеры использования с новым plugin ID
- Добавить Warning о breaking change в начало
- Обновить URLs в примерах
- Добавить информацию что это fork от Mattermost Apps Plugin

**Пример:**
```markdown
## ⚠️ Version 2.0 Breaking Changes

**This is a fork of the Mattermost Apps Plugin with significant changes**

**Plugin ID has changed from `com.mattermost.apps` to `ru.2gis.apps`**

See [MIGRATION.md](MIGRATION.md) for upgrade instructions.

## Installation

Download the latest release from...

All API endpoints now use the prefix:
```
/plugins/ru.2gis.apps/api/v1/
```

## Examples

Install an app:
```bash
curl -X POST https://your-server/plugins/ru.2gis.apps/api/v1/apps \
  ...
```
```

### 13.9 Обновить CHANGELOG
**Файл:** `CHANGELOG.md` (если существует) или создать

**Действия:**
- Описать breaking changes
- Перечислить новые возможности
- **Важно:** Указать изменение plugin ID на ru.2gis.apps

**Содержание:**
```markdown
## v2.0.0 - BREAKING CHANGES (2GIS Fork)

### ⚠️ IMPORTANT: This is a fork of Mattermost Apps Plugin

**This plugin is a fork of the original Mattermost Apps Plugin with significant architectural changes**

**The plugin ID has changed from `com.mattermost.apps` to `ru.2gis.apps`**

This means:
- You need to **uninstall the old plugin** before installing v2.0
- Client-side caches will be automatically cleared
- All existing apps will need to be **reinstalled** after upgrading
- Plugin configuration will **not** be automatically migrated

**Migration steps:**
1. Backup your plugin configuration
2. Note all installed apps
3. Uninstall `com.mattermost.apps` plugin
4. Install `ru.2gis.apps` plugin
5. Restore configuration if needed
6. Reinstall apps (with updated manifests for v2.0)

### Breaking Changes

- **Plugin ID changed**: `com.mattermost.apps` → `ru.2gis.apps`

- **Server-side bindings caching**: Bindings are now cached on the server with on-demand refresh instead of periodic updates. This significantly reduces load on apps and the server.
  - Bindings are **static** and do not depend on user/channel context
  - Updates only when:
    - App is installed/uninstalled/enabled/disabled
    - App requests refresh via `refresh_bindings: true`
    - Admin manually triggers refresh

- **Only /command location supported**: Removed support for `/post_menu`, `/channel_header`, and `/in_post` locations. Apps can now only bind to `/command` location.

- **Modal forms removed**: Modal forms are no longer supported. Only slash commands with autocomplete are available.

### New Features

- **Health Check mechanism**: Apps can define `on_health_check` callback in manifest
  - Automatically called when app is inactive for configured period (default: 5 minutes)
  - Allows detecting unresponsive apps
  - Configurable via `app_health_check_inactivity_seconds` setting

- **On-demand bindings refresh**: No periodic polling, only when needed
  - Admin command `/apps refresh-bindings` to force immediate cache refresh
  - Admin endpoint `POST /api/v1/bindings/refresh` for programmatic cache refresh
  - Apps can request cache refresh via `refresh_bindings: true` in CallResponse

### Migration Guide for Apps

Apps need to be updated to:
1. Remove bindings for `/post_menu`, `/channel_header`, `/in_post` locations
2. Update manifest to only request `/command` location
3. Remove modal form definitions (Title, Header, Footer, SubmitButtons)
4. Keep only command autocomplete forms with dynamic select support
5. Optionally add `on_health_check` callback for health monitoring

### Deprecated

- `LocationPostMenu`, `LocationChannelHeader`, `LocationInPost` constants
- `WebSocketEventRefreshBindings` - no longer sent to clients
- Modal-specific Form fields: `Title`, `Header`, `Footer`, `SubmitButtons`
- Periodic bindings refresh - replaced with on-demand model

### Technical Details

- All API endpoints now use `/plugins/ru.2gis.apps/` prefix
- Client code will automatically use new endpoints
- No client-side changes required (except for apps themselves)
- Bindings cache is updated only on-demand, reducing unnecessary load
- Health checks monitor app responsiveness during inactivity periods
```

### 13.10 Чеклист для этапа 13 (Plugin ID Change)

Перед переходом к следующему этапу убедитесь:

**Манифест и версия:**
- [ ] `plugin.json`: ID изменен на `ru.2gis.apps`
- [ ] `plugin.json`: version изменена на `2.0.0`
- [ ] `plugin.json`: проверены все другие поля

**Константы в коде:**
- [ ] `apps/appclient/mattermost_client_pp.go`: AppsPluginName обновлен на `ru.2gis.apps`
- [ ] Выполнен grep поиск `"com.mattermost.apps"` в `.go` файлах
- [ ] Все найденные вхождения проверены и обновлены или документированы

**Тесты:**
- [ ] `test/restapitest/helper.go`: pluginID обновлен
- [ ] `test/restapitest/helper.go`: appPath обновлен
- [ ] `test/restapitest/webhook_test.go`: appURL обновлен
- [ ] `test/restapitest/echo.go`: AppPath обновлен
- [ ] `test/restapitest/static.go`: URL путь обновлен
- [ ] `test/restapitest/bindings.go`: URL путь обновлен
- [ ] `test/e2e/**/*.ts`: все plugin IDs и URLs обновлены
- [ ] Выполнен grep поиск `/plugins/com.mattermost.apps/` в тестах

**Документация:**
- [ ] `README.md`: все примеры обновлены с новым plugin ID
- [ ] `README.md`: добавлено предупреждение о breaking change и fork
- [ ] `CHANGELOG.md`: создан и заполнен с акцентом на Plugin ID change и 2GIS fork
- [ ] `MIGRATION.md`: создан с детальными инструкциями по upgrade
- [ ] `TODO.md`: все примеры в этом файле используют новый ID

**Дополнительно:**
- [ ] Примеры приложений обновлены (если есть в репо)
- [ ] Проверена документация в `apps/*.go` файлах
- [ ] Рассмотрено создание миграционной утилиты

**Тестирование после изменений:**
```bash
# Проверить что старый ID больше не используется (кроме документации миграции)
grep -r "com\.mattermost\.apps\"" --include="*.go" | grep -v "ru.2gis.apps" | grep -v "CHANGELOG" | grep -v "MIGRATION"

# Должны найтись только новые ID
grep -r "com\.2gis\.apps" --include="*.go" --include="*.json"

# Проверить тесты
make test

# Собрать плагин
make dist
```

---

## Этап 14: Обновление тестов

### 13.1 Обновить тесты bindings
**Файл:** `server/proxy/bindings_test.go`

**Действия:**
- Найти тест `TestRefreshBindingsEventAfterCall`
- Обновить для проверки вызова `RefreshBindingsCache()` вместо WebSocket события
- Добавить тесты для кеша

**Примерные тесты:**
```go
func TestBindingsCache(t *testing.T) {
    // Тест инициализации кеша
    // Тест периодического обновления
    // Тест принудительного обновления
    // Тест получения из кеша
}

func TestBindingsCacheRefreshOnOperations(t *testing.T) {
    // Тест обновления после install
    // Тест обновления после uninstall
    // Тест обновления после enable/disable
}
```

### 13.2 Обновить тесты валидации locations
**Файл:** `server/proxy/invoke_bindings_test.go` (если существует)

**Действия:**
- Добавить тесты для проверки что только `/command` разрешен
- Проверить что `/post_menu`, `/channel_header` отклоняются

### 13.3 Удалить или обновить deprecated тесты
**Файлы:** различные тестовые файлы

**Действия:**
- Найти тесты использующие `LocationPostMenu`, `LocationChannelHeader`
- Удалить или пометить как deprecated/skip

---

## Этап 14: Документация миграции

### 14.1 Создать MIGRATION.md
**Файл:** `MIGRATION.md` (новый файл)

**Содержание:**
```markdown
# Migration Guide: Apps Framework v2.0 (2GIS Fork)

## ⚠️ CRITICAL: This is a 2GIS Fork

**This plugin is a fork of the original Mattermost Apps Plugin with significant changes**

## ⚠️ CRITICAL: Plugin ID Has Changed

**Before starting migration, read this section carefully!**

The plugin ID has changed from `com.mattermost.apps` to `ru.2gis.apps`. This is a breaking change that requires special attention.

### Why the plugin ID changed

- This is a fork of the original Mattermost plugin
- Prevents client-side caching issues with old bindings
- Forces clients to fetch new bindings structure
- Clearly indicates 2GIS customization
- Avoids conflicts between original and forked installations

### Upgrade Process for Server Admins

**You CANNOT upgrade in place. You must:**

1. **Backup everything:**
   ```bash
   # Backup plugin configuration
   # Note all installed apps
   # Backup app configurations if needed
   ```

2. **Uninstall original plugin:**
   - Go to System Console → Plugins → Plugin Management
   - Uninstall `com.mattermost.apps` plugin
   - Or via CLI: `mattermost plugin delete com.mattermost.apps`

3. **Install 2GIS fork:**
   - Upload or install `ru.2gis.apps` plugin
   - Restore configuration in new plugin settings
   - Configure `app_health_check_inactivity_seconds` if needed (default: 300)

4. **Reinstall apps:**
   - All apps need to be reinstalled
   - Apps must be updated to v2.0 compatible versions
   - Use updated app manifests (see below)

### Impact on URLs

All plugin URLs have changed:

```
OLD: /plugins/com.mattermost.apps/api/v1/...
NEW: /plugins/ru.2gis.apps/api/v1/...

OLD: /plugins/com.mattermost.apps/apps/<app-id>/...
NEW: /plugins/ru.2gis.apps/apps/<app-id>/...
```

**Important:** Client applications (web, mobile, desktop) will automatically use the new URLs. No client updates required.

### Impact on Apps

Apps that make API calls to the plugin need to update their code:

```go
// OLD
const pluginURL = "/plugins/com.mattermost.apps/api/v1/"

// NEW
const pluginURL = "/plugins/ru.2gis.apps/api/v1/"
```

However, if your app uses the official SDK (`apps/appclient`), it will be updated automatically.

## Overview

Version 2.0 introduces significant changes to improve performance and simplify the Apps Framework architecture. This guide helps you migrate your app to the new version.

## Breaking Changes

### 1. Only /command Location Supported

**What changed:** Apps can no longer bind to `/post_menu`, `/channel_header`, or `/in_post` locations.

**Action required:**
- Remove all bindings for deprecated locations from your bindings handler
- Update your manifest to only request `/command` location:

```json
{
  "requested_locations": ["/command"]
}
```

### 2. Modal Forms Removed

**What changed:** Modal forms are no longer supported. Only slash command autocomplete is available.

**Action required:**
- Remove modal-specific fields from your forms:
  - `title`
  - `header`
  - `footer`
  - `submit_buttons`
- Keep only `fields` and `submit` for command autocomplete

### 3. Server-Side Bindings Cache (On-Demand)

**What changed:** Bindings are now cached on the server with on-demand refresh instead of periodic polling or client requests.

**Impact:** Your bindings handler will be called only when:
- App is installed/uninstalled/enabled/disabled
- App explicitly requests refresh via `refresh_bindings: true` in CallResponse
- Admin manually triggers refresh via `/apps refresh-bindings` command

**Action required:**
- Ensure your bindings handler is stateless
- Bindings must not depend on user or channel context (they are now global)
- Use `refresh_bindings: true` in CallResponse if you need immediate cache update after an operation
- Don't rely on bindings being refreshed frequently

### 4. Health Check Support

**What's new:** Apps can now implement health check callback.

**Action required (optional but recommended):**

Add `on_health_check` to your manifest:

```json
{
  "app_id": "your-app",
  "version": "2.0.0",
  "on_health_check": {
    "path": "/health"
  },
  ...
}
```

Implement health check endpoint:

```go
func (a *App) HandleHealthCheck(creq apps.CallRequest) apps.CallResponse {
    // Simple check - just return OK if app is running
    return apps.NewTextResponse("OK")
}
```

**Benefits:**
- Plugin will detect if your app becomes unresponsive
- Health check is called only when app is inactive (no requests for 5 minutes by default)
- Helps with monitoring and debugging

### 5. WebSocket Events Removed

**What changed:** `refresh_bindings` WebSocket event is no longer sent to clients.

**Action required:** No action required for most apps. If you were listening to this event in a custom client, remove that code.

## Migration Steps

### Step 1: Update Manifest

```json
{
  "app_id": "your-app",
  "version": "2.0.0",
  "requested_locations": ["/command"],
  ...
}
```

### Step 2: Update Bindings Handler

Remove deprecated locations:

```go
// Before
func (a *App) GetBindings(creq apps.CallRequest) apps.CallResponse {
    return apps.NewDataResponse([]apps.Binding{
        {Location: apps.LocationPostMenu, ...},      // REMOVE
        {Location: apps.LocationChannelHeader, ...}, // REMOVE
        {Location: apps.LocationCommand, ...},       // KEEP
    })
}

// After
func (a *App) GetBindings(creq apps.CallRequest) apps.CallResponse {
    return apps.NewDataResponse([]apps.Binding{
        {Location: apps.LocationCommand, ...}, // Only /command
    })
}
```

### Step 3: Simplify Forms

```go
// Before
form := apps.Form{
    Title:         "My Modal",          // REMOVE
    Header:        "Fill the form",     // REMOVE
    Footer:        "Submit to continue", // REMOVE
    SubmitButtons: "actions",           // REMOVE
    Fields: []apps.Field{...},          // KEEP
    Submit: &apps.Call{...},            // KEEP
}

// After
form := apps.Form{
    Fields: []apps.Field{...},
    Submit: &apps.Call{...},
}
```

### Step 4: Use RefreshBindings Flag

If your app modifies bindings state, request cache refresh:

```go
func (a *App) HandleAction(creq apps.CallRequest) apps.CallResponse {
    // ... your logic ...
    
    return apps.CallResponse{
        Type:            apps.CallResponseTypeOK,
        Text:            "Action completed",
        RefreshBindings: true, // Request cache refresh
    }
}
```

## Configuration

Admins can configure cache refresh interval:

```json
{
  "bindings_cache_interval_seconds": 60
}
```

Admins can manually refresh cache:

```
/apps refresh-bindings
```

Or via API:

```bash
curl -X POST https://your-mattermost/plugins/com.mattermost.apps/api/v1/bindings/refresh \
  -H "Authorization: Bearer YOUR_TOKEN"
```

## Testing Your Migration

1. Install your updated app
2. Test slash commands and autocomplete
3. Verify dynamic selects (lookup calls) still work
4. Test that `refresh_bindings: true` triggers cache update

## Need Help?

- Join [Mattermost Apps channel](https://community.mattermost.com/core/channels/mattermost-apps)
- Review [updated examples](https://github.com/mattermost/mattermost-app-examples)
```

### 14.2 Обновить README.md
**Файл:** `README.md`

**Действия:**
- Добавить ссылку на MIGRATION.md
- Упомянуть breaking changes в v2.0

---

## Этап 15: Финальная проверка

### 15.1 Чеклист перед релизом

- [ ] **Plugin ID изменен** с `com.mattermost.apps` на `com.mattermost.apps.v2`
- [ ] Все константы с plugin ID обновлены в коде
- [ ] Все пути в тестах обновлены (`/plugins/com.mattermost.apps.v2/`)
- [ ] Все файлы из плана обновлены
- [ ] Кеш bindings работает и обновляется периодически
- [ ] Принудительное обновление работает через команду и API
- [ ] Только `/command` location разрешен
- [ ] Modal-специфичные поля помечены deprecated
- [ ] DynamicSelect и lookup calls работают
- [ ] WebSocket события удалены
- [ ] Версия плагина обновлена до 2.0.0
- [ ] Тесты обновлены и проходят
- [ ] Документация обновлена (CHANGELOG, MIGRATION, README)
- [ ] В CHANGELOG явно указано изменение plugin ID
- [ ] В MIGRATION.md есть инструкции по upgrade для админов
- [ ] Примеры приложений обновлены (если есть в репозитории)

### 15.2 Тестирование

1. **Unit tests:**
   ```bash
   make test
   ```

2. **E2E tests:**
   ```bash
   make test-e2e
   ```

3. **Manual testing:**
   - Установить плагин на тестовом сервере
   - Установить тестовое приложение с `/command` bindings
   - Проверить автодополнение команд
   - Проверить dynamic select (lookup)
   - Выполнить `/apps refresh-bindings`
   - Проверить логи на наличие ошибок
   - Проверить периодическое обновление кеша

### 15.3 Производительность

Проверить метрики:
- Время обновления кеша
- Нагрузка на приложения (должна уменьшиться в N раз, где N - количество клиентов)
- Время ответа на `/api/v1/bindings` (должно значительно уменьшиться)

---

## Дополнительные улучшения (опционально)

### 1. Миграционная утилита для Plugin ID change

**Описание:** Создать helper для автоматической миграции при смене plugin ID

**Файл:** `server/migration/migrate.go` (новый)

**Функциональность:**
- Копирование конфигурации из старого плагина
- Экспорт/импорт списка установленных apps
- Опционально: миграция KV store данных

**Код:**
```go
package migration

import (
    "encoding/json"
    
    "github.com/mattermost/mattermost/server/public/pluginapi"
    "github.com/mattermost/mattermost-plugin-apps/server/config"
)

const OldPluginID = "com.mattermost.apps"
const NewPluginID = "com.mattermost.apps.v2"

// MigrateConfig copies configuration from old plugin to new plugin
func MigrateConfig(mm *pluginapi.Client) error {
    // Read config from old plugin
    // Write to new plugin
    // ...
}

// ExportInstalledApps exports list of installed apps for manual reinstall
func ExportInstalledApps(mm *pluginapi.Client) ([]byte, error) {
    // Export apps list as JSON
    // Include app configurations
    // ...
}
```

**Команда миграции:**
```bash
# CLI команда для админов
mattermost apps migrate-from-v1
```

### 2. Метрики и мониторинг

**Файл:** `server/proxy/bindings_cache.go`

Добавить:
- Prometheus метрики для cache hits/misses
- Метрики времени обновления кеша
- Счетчик ошибок обновления

### 3. Graceful degradation

При ошибках обновления кеша:
- Продолжать отдавать старые данные
- Логировать предупреждения
- Не блокировать клиентов

### 3. Cache warming

При старте плагина:
- Выполнить первое обновление синхронно
- Не отдавать пустой кеш клиентам

### 4. Admin UI

Добавить в админ-панель:
- Статус кеша (последнее обновление, ошибки)
- Кнопку для ручного обновления
- Настройку интервала обновления

---

## Порядок выполнения этапов

Рекомендуемая последовательность:

**⚠️ ВАЖНО: Этап 13 (изменение namespace) должен быть выполнен в самом начале или в конце!**

### Вариант 1: Изменить namespace в начале (рекомендуется)
1. **Этап 13:** Изменить plugin ID на `ru.2gis.apps` и обновить версию (namespace change)
2. **Этап 1:** Конфигурация health check (вместо периодического кеша)
3. **Этап 2:** Создать инфраструктуру кеша (on-demand модель)
4. **Этап 3:** Интегрировать кеш в Proxy
5. **Этап 4:** Инициализация кеша при старте плагина
6. **Этап 5:** Переключить GetBindings на использование кеша
7. **Этап 6:** Обновление кеша при операциях
8. **Этап 7:** Удаление WebSocket событий
9. **Этап 8:** Реализовать Health Check механизм
10. **Этап 9:** Ограничение locations
11. **Этап 10:** Упрощение Form
12. **Этап 11:** Обновление документации в коде
13. **Этап 12:** Admin endpoint для refresh
14. **Этап 14:** Обновление тестов (пути с новым namespace уже изменены)
15. **Этап 15:** Документация миграции
16. **Этап 16:** Тестирование

**Преимущества:** 
- Все разработка идет с новым namespace
- Не нужно переименовывать пути в конце
- Сразу понятно что это 2GIS fork

### Вариант 2: Изменить namespace в конце
1. **Этап 1:** Конфигурация health check
2. **Этап 2:** Создать инфраструктуру кеша (on-demand)
3. **Этап 3:** Интегрировать кеш в Proxy
4. **Этап 4:** Инициализация кеша при старте
5. **Этап 5:** Переключить GetBindings на использование кеша
6. **Этап 6:** Обновление кеша при операциях
7. **Этап 7:** Удаление WebSocket событий
8. **Этап 8:** Реализовать Health Check
9. **Этап 9:** Ограничение locations
10. **Этап 10:** Упрощение Form
11. **Этап 11:** Обновление документации в коде
12. **Этап 12:** Admin endpoint для refresh
13. **Этап 13:** Изменить plugin ID на `ru.2gis.apps` (namespace change)
14. **Этап 14:** Обновление тестов (обновить пути для нового namespace)
15. **Этап 15:** Документация миграции
16. **Этап 16:** Тестирование

**Преимущества:**
- Можно тестировать функциональность до изменения namespace
- Изменение namespace - последний коммит перед релизом

Можно работать параллельно над:
- Этапами 1-7 (core functionality - кеш и конфигурация)
- Этапом 8 (health check - независимая фича)
- Этапами 9-11 (deprecation и упрощение)
- Этапами 12, 15 (admin features и документация)

**Независимо от варианта, этап 13 (namespace) нельзя делать частично - это atomic change.**

### Ключевые отличия от оригинального плана

✅ **Добавлено:**
- Health check механизм (Этап 8)
- Activity tracker для мониторинга приложений
- Конфигурация health check вместо периодического кеша

❌ **Удалено:**
- Периодическое обновление кеша bindings
- Start/Stop методы для кеша
- Интервал обновления кеша в конфигурации

🔄 **Изменено:**
- Namespace: `com.mattermost.apps` → `ru.2gis.apps` (вместо `com.mattermost.apps.v2`)
- Модель обновления кеша: от периодической к on-demand
- Bindings теперь полностью статичны (не зависят от user/channel)

---

## Известные риски и mitigation

### Риск 0: Изменение Plugin ID (КРИТИЧЕСКИЙ)

**Проблема:** Нельзя обновить плагин in-place, требуется переустановка.

**Решение:**
- Четко документировать процесс upgrade
- Предупредить в release notes
- Предоставить скрипт миграции конфигурации
- Предупредить что все apps нужно переустановить
- Рассмотреть создание миграционной утилиты для автоматического копирования:
  - Конфигурации плагина
  - Установленных apps (список)
  - KV store данных (опционально)

**Альтернатива (если критично):**
- Оставить старый plugin ID `com.mattermost.apps`
- Но тогда на клиентах могут остаться кеши старых bindings
- Потребуется явная очистка кеша на клиентах
- **Не рекомендуется** - лучше изменить ID

### Риск 1: Устаревший кеш

**Проблема:** Между обновлениями кеша bindings могут быть неактуальными.

**Решение:**
- Установить разумный интервал по умолчанию (60 сек)
- Позволить администраторам настраивать интервал
- Принудительное обновление при критичных операциях
- Apps могут запросить обновление через `RefreshBindings`

### Риск 2: Ошибки при обновлении кеша

**Проблема:** Если все приложения недоступны, кеш будет пустым.

**Решение:**
- Сохранять предыдущее состояние кеша при ошибках
- Логировать ошибки для мониторинга
- Продолжать отдавать старые данные

### Риск 3: Breaking changes для существующих приложений

**Проблема:** Все приложения перестанут работать после обновления.

**Решение:**
- Четкая документация миграции
- Обновить примеры приложений
- Анонсировать breaking changes заранее
- Major version bump (2.0.0)

### Риск 4: Breaking changes для существующих приложений

**Проблема:** Все приложения перестанут работать после обновления.

**Решение:**
- Четкая документация миграции
- Обновить примеры приложений
- Анонсировать breaking changes заранее
- Major version bump (2.0.0)
- Подчеркнуть что это 2GIS fork с изменениями

### Риск 5: Race conditions в кеше

**Проблема:** Одновременное чтение/запись кеша.

**Решение:**
- Использовать `sync.RWMutex`
- Копировать данные при чтении
- Тестировать с race detector: `go test -race`

### Риск 6: Activity tracker утечки памяти

**Проблема:** Activity tracker хранит данные для всех apps, даже удаленных.

**Решение:**
- Очищать данные удаленных apps при uninstall
- Не хранить историю активности, только последний timestamp
- Периодическая очистка неиспользуемых записей (опционально)

---

## Финальные заметки

### Перед началом разработки

1. **Решение о namespace принято:**
   - ✅ Используем `ru.2gis.apps` (2GIS fork)
   - Подчеркивает принадлежность и отличие от оригинала

2. **Подготовить план коммуникации:**
   - Анонсировать breaking changes заранее (2-4 недели)
   - Подчеркнуть что это 2GIS fork с изменениями
   - Предупредить разработчиков apps о необходимости обновления
   - Подготовить примеры миграции

3. **Подготовить миграционные инструменты:**
   - Скрипт для backup конфигурации
   - Документация по миграции для админов
   - Список изменений для разработчиков apps

### Ключевые решения принятые в плане

✅ **On-Demand Bindings Cache:**
- Отказ от периодического обновления
- Обновление только при необходимости
- Значительное снижение нагрузки

✅ **Health Check механизм:**
- Проверка здоровья при неактивности
- Конфигурируемый интервал
- Опциональный для apps

✅ **Статические Bindings:**
- Не зависят от пользователя/канала
- Упрощает логику
- Улучшает кешируемость

### После завершения всех этапов

1. **Тестирование:**
   - Протестировать на staging окружении
   - Проверить процесс upgrade (uninstall v1 → install v2)
   - Убедиться что все пути с новым namespace работают
   - Протестировать с реальными apps
   - **Важно:** Проверить health check при неактивности
   - **Важно:** Убедиться что bindings НЕ обновляются периодически

2. **Документация:**
   - Создать release notes с акцентом на 2GIS fork
   - Обновить документацию для разработчиков
   - Описать health check механизм
   - Описать on-demand модель кеширования
   - Создать видео-гайд по миграции (опционально)

3. **Релиз:**
   - Анонсировать в community channel за неделю
   - Выложить beta версию для early adopters
   - Собрать feedback
   - Выпустить v2.0.0

4. **Post-release поддержка:**
   - Мониторить issues и вопросы
   - Помогать разработчикам с миграцией apps
   - Обновить примеры apps в документации
   - Следить за метриками health check

### Важные напоминания

⚠️ **Plugin ID change is CRITICAL** - это самое важное изменение в плане. Убедитесь что:
- Все упоминания старого ID заменены на `ru.2gis.apps`
- Тесты используют новый ID
- Документация четко описывает процесс upgrade
- Release notes предупреждают об этом в первую очередь
- Подчеркивается что это 2GIS fork

⚠️ **On-Demand модель** - важное архитектурное решение:
- НЕТ периодического обновления кеша
- Bindings статичны и глобальны
- Health check - отдельный механизм для мониторинга

⚠️ **Нельзя откатиться** после установки v2 без потери данных apps

⚠️ **Все apps должны быть обновлены** - старые apps не будут работать с v2

⚠️ **Health Check ОБЯЗАТЕЛЕН** - все приложения должны реализовать `/health` endpoint:
- Endpoint вызывается без проверки манифеста
- Приложения без `/health` будут логировать ошибки
- Это **breaking requirement** для всех приложений

### Контрольные вопросы перед релизом

- [ ] Все периодические обновления удалены из кода?
- [ ] Health check работает только при неактивности?
- [ ] Bindings действительно статичны?
- [ ] Namespace `ru.2gis.apps` везде?
- [ ] Документация упоминает 2GIS fork?
- [ ] Миграционный путь понятен?

Успехов с реализацией! 🚀

---

## Appendix A: Quick Reference - Plugin ID Changes

### Файлы для изменения (в порядке приоритета)

#### Критические файлы (обязательно)

1. **plugin.json**
   ```json
   - "id": "com.mattermost.apps"
   + "id": "com.mattermost.apps.v2"
   - "version": "1.2.2"
   + "version": "2.0.0"
   ```

2. **apps/appclient/mattermost_client_pp.go**
   ```go
   - AppsPluginName = "com.mattermost.apps"
   + AppsPluginName = "com.mattermost.apps.v2"
   ```

#### Тестовые файлы

3. **test/restapitest/helper.go**
   ```go
   - var pluginID = "com.mattermost.apps"
   + var pluginID = "com.mattermost.apps.v2"
   
   - appPath := "/plugins/com.mattermost.apps/apps/" + string(app.AppID)
   + appPath := "/plugins/com.mattermost.apps.v2/apps/" + string(app.AppID)
   ```

4. **test/restapitest/webhook_test.go**
   ```go
   - const appURL = "/plugins/com.mattermost.apps/apps/" + string(webhookAppID)
   + const appURL = "/plugins/com.mattermost.apps.v2/apps/" + string(webhookAppID)
   ```

5. **test/restapitest/echo.go**
   ```go
   - AppPath: "/plugins/com.mattermost.apps/apps/" + string(echoID)
   + AppPath: "/plugins/com.mattermost.apps.v2/apps/" + string(echoID)
   ```

6. **test/restapitest/static.go**
   ```go
   - iconURL := fmt.Sprintf("/plugins/com.mattermost.apps/apps/%s/static/icon.png", app.Manifest.AppID)
   + iconURL := fmt.Sprintf("/plugins/com.mattermost.apps.v2/apps/%s/static/icon.png", app.Manifest.AppID)
   ```

7. **test/restapitest/bindings.go**
   ```go
   - appsURL := fmt.Sprintf("http://localhost:%v/plugins/com.mattermost.apps/apps", ...)
   + appsURL := fmt.Sprintf("http://localhost:%v/plugins/com.mattermost.apps.v2/apps", ...)
   ```

8. **test/e2e/cypress/integration/bindings/channel_header_spec.ts**
   ```typescript
   - cy.apiEnablePluginById('com.mattermost.apps');
   + cy.apiEnablePluginById('com.mattermost.apps.v2');
   
   - cy.get('#channel-header img[src="http://localhost:8065/plugins/com.mattermost.apps/apps/..."]')
   + cy.get('#channel-header img[src="http://localhost:8065/plugins/com.mattermost.apps.v2/apps/..."]')
   ```

#### Документация

9. **README.md** - обновить все примеры и добавить warning
10. **CHANGELOG.md** - создать с описанием изменений
11. **MIGRATION.md** - создать с инструкциями по миграции

### Команды для проверки

```bash
# Найти все старые вхождения (должны остаться только в CHANGELOG/MIGRATION)
grep -r "com\.mattermost\.apps\"" --include="*.go" --include="*.json" --include="*.ts" | grep -v "v2" | grep -v "CHANGELOG" | grep -v "MIGRATION"

# Найти старые пути
grep -r "/plugins/com\.mattermost\.apps/" --include="*.go" --include="*.ts" | grep -v "v2"

# Проверить что новый ID используется
grep -r "com\.mattermost\.apps\.v2" --include="*.go" --include="*.json"

# Количество замен (должно быть минимум 11)
grep -r "com\.mattermost\.apps\.v2" --include="*.go" --include="*.json" | wc -l
```

### Потенциальные проблемы

❌ **Забыли обновить:**
- E2E тесты - плагин не активируется
- Static URL paths - assets не загружаются
- Test helper - все тесты падают

✅ **Решение:**
- Используйте grep для поиска всех вхождений
- Проверяйте чеклист после каждого изменения
- Запускайте тесты после изменений

### Тестирование изменений

```bash
# 1. Проверить что код компилируется
go build ./...

# 2. Запустить unit тесты
make test

# 3. Запустить E2E тесты (если настроены)
make test-e2e

# 4. Собрать плагин
make dist

# 5. Проверить манифест в бинарнике
unzip -p dist/ru.2gis.apps-*.tar.gz plugin.json | jq '.id'
# Должно вывести: "ru.2gis.apps"
```

### Дополнительные проверки для 2GIS fork

```bash
# Проверить что все упоминания mattermost заменены где нужно
grep -r "mattermost" plugin.json README.md

# Проверить health check конфигурацию
grep -r "app_health_check_inactivity" --include="*.go"

# Убедиться что нет периодического обновления кеша
grep -r "BindingsCacheInterval" --include="*.go"
# Не должно найти использования (только в старой документации)
```

---

## Appendix B: Новые возможности v2.0

### 1. On-Demand Bindings Cache

**Что изменилось:**
- Bindings кешируются на сервере
- Обновление только по необходимости (не периодически)
- Значительное снижение нагрузки на приложения

**Как использовать:**
```go
// В приложении - запросить обновление при изменении состояния
return apps.CallResponse{
    Type: apps.CallResponseTypeOK,
    RefreshBindings: true, // Просим плагин обновить кеш
}
```

### 2. Health Check

**Что это:**
- Механизм проверки здоровья приложений
- Автоматически вызывается при неактивности

**Как реализовать:**

В манифесте:
```json
{
  "on_health_check": {
    "path": "/health"
  }
}
```

В приложении:
```go
func (a *App) HandleHealthCheck(creq apps.CallRequest) apps.CallResponse {
    // Проверить что все ок
    if !a.IsHealthy() {
        return apps.NewErrorResponse(errors.New("service unavailable"))
    }
    return apps.NewTextResponse("OK")
}
```

**Конфигурация:**
```json
{
  "app_health_check_inactivity_seconds": 300
}
```

### 3. Статические Bindings

**Что изменилось:**
- Bindings больше не зависят от пользователя или канала
- Bindings одинаковы для всех пользователей
- Упрощает логику и повышает производительность

**Что делать:**
```go
// НЕ ДЕЛАЙТЕ ТАК - bindings не должны зависеть от context
func (a *App) GetBindings(creq apps.CallRequest) apps.CallResponse {
    // ❌ Плохо - зависит от пользователя
    if creq.Context.ActingUser.IsAdmin() {
        return adminBindings
    }
    return userBindings
}

// ДЕЛАЙТЕ ТАК - статические bindings
func (a *App) GetBindings(creq apps.CallRequest) apps.CallResponse {
    // ✅ Хорошо - всегда одинаковые
    return apps.NewDataResponse([]apps.Binding{...})
}
```

---

## Appendix C: Ссылки на документацию

- [Mattermost Plugin Development](https://developers.mattermost.com/integrate/plugins/)
- [Mattermost Apps Framework](https://developers.mattermost.com/integrate/apps/)
- [Breaking Changes Best Practices](https://developers.mattermost.com/integrate/plugins/best-practices/)

---

*Последнее обновление: 23 декабря 2025*
