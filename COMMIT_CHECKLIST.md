# Commit Checklist

Используйте этот чеклист перед каждым коммитом.

## Pre-Commit Verification

### 1. Компиляция
```bash
cd /home/psyton/work/2gis/mattermost-plugin-apps
go build ./...
```
✅ Код должен компилироваться без ошибок

### 2. Тесты
```bash
make test
```
✅ Все тесты должны проходить

### 3. Проверка namespace
```bash
# Проверить что старый namespace не используется (кроме документации)
grep -r "com\.mattermost\.apps\"" --include="*.go" --include="*.json" | \
    grep -v "2gis" | grep -v "CHANGELOG" | grep -v "MIGRATION" | grep -v "TODO"
```
✅ Не должно найти результатов (или только в допустимых файлах)

### 4. Проверка нового namespace
```bash
# Должен использоваться новый namespace
grep -r "com\.2gis\.apps" --include="*.go" --include="*.json"
```
✅ Должны быть результаты в модифицированных файлах

### 5. Проверка периодического обновления
```bash
# НЕ должно быть периодического обновления кеша
grep -r "BindingsCacheInterval" --include="*.go"
```
✅ Не должно найти результатов

### 6. Проверка Health Check
```bash
# НЕ должно быть проверок OnHealthCheck
grep -r "OnHealthCheck.*nil" --include="*.go"
```
✅ Не должно найти результатов

```bash
# Должна использоваться константа path.Health
grep -r "path\.Health" --include="*.go"
```
✅ Должны быть результаты если этап 8 реализован

### 7. Linting (опционально)
```bash
golangci-lint run ./...
```
✅ Минимум ошибок

### 8. Форматирование
```bash
go fmt ./...
```
✅ Код отформатирован

## Commit Message Template

```
[Этап X] Краткое описание изменений

Детальное описание:
- Что изменено
- Почему изменено
- Особенности реализации

Breaking changes (если есть):
- Описание breaking change

Checklist:
- [x] Код компилируется
- [x] Тесты проходят
- [x] Namespace проверен
- [x] Документация обновлена (если нужно)
```

## Примеры хороших commit messages

### Пример 1: Namespace change
```
[Этап 13] Изменен namespace на ru.2gis.apps

Обновлены все файлы с упоминанием plugin ID:
- plugin.json: id изменен на "ru.2gis.apps"
- apps/appclient/mattermost_client_pp.go: константа AppsPluginName
- test/restapitest/helper.go: переменная pluginID
- Все пути в тестах обновлены

Breaking change: плагин требует полной переустановки

Checklist:
- [x] Код компилируется
- [x] Тесты проходят
- [x] grep не находит старый namespace (кроме документации)
- [x] Все URL пути обновлены на /plugins/ru.2gis.apps/
```

### Пример 2: Health Check
```
[Этап 8] Реализован обязательный Health Check механизм

Добавлена поддержка обязательного /health endpoint:
- apps/path/paths.go: добавлена константа Health
- server/proxy/app_activity_tracker.go: новый файл с трекером активности
- server/proxy/service.go: интеграция activityTracker в Proxy
- server/proxy/invoke_call.go: запись активности при каждом вызове

Health check вызывается по фиксированному пути /health без проверок манифеста.
Все приложения обязаны реализовать этот endpoint.

Checklist:
- [x] Код компилируется
- [x] Тесты проходят
- [x] Нет проверок OnHealthCheck (grep показывает 0 результатов)
- [x] Используется path.Health константа
- [x] Документация обновлена
```

### Пример 3: Cache implementation
```
[Этап 2] Реализован on-demand кеш bindings

Создан сервис кеширования bindings без периодического обновления:
- server/proxy/bindings_cache.go: новый файл
- Только методы InitCache() и RefreshCache()
- НЕТ Start/Stop методов для периодики
- НЕТ stopChan и isRunning полей

Кеш обновляется только по требованию:
- При установке/удалении/включении/отключении приложения
- По явному запросу от приложения
- По команде администратора

Checklist:
- [x] Код компилируется
- [x] Тесты проходят
- [x] Нет периодического обновления (grep BindingsCacheInterval = 0 результатов)
- [x] Есть только Init и Refresh методы
```

## Quick Commands

### Запустить все проверки сразу
```bash
#!/bin/bash
echo "=== Компиляция ==="
go build ./... && echo "✅ OK" || echo "❌ FAILED"

echo -e "\n=== Тесты ==="
make test && echo "✅ OK" || echo "❌ FAILED"

echo -e "\n=== Проверка старого namespace ==="
COUNT=$(grep -r "com\.mattermost\.apps\"" --include="*.go" --include="*.json" | \
    grep -v "2gis" | grep -v "CHANGELOG" | grep -v "MIGRATION" | grep -v "TODO" | wc -l)
if [ $COUNT -eq 0 ]; then
    echo "✅ OK (0 найдено)"
else
    echo "❌ FAILED ($COUNT найдено)"
    grep -r "com\.mattermost\.apps\"" --include="*.go" --include="*.json" | \
        grep -v "2gis" | grep -v "CHANGELOG" | grep -v "MIGRATION" | grep -v "TODO"
fi

echo -e "\n=== Форматирование ==="
go fmt ./... && echo "✅ OK" || echo "❌ FAILED"
```

Сохраните как `pre-commit-check.sh` и сделайте исполняемым:
```bash
chmod +x pre-commit-check.sh
```

## Staged Commits Strategy

### Этап 13: Namespace Change
**Один большой коммит**, т.к. это atomic change:
- Все файлы с namespace должны быть изменены одновременно
- Иначе код не скомпилируется

### Этап 1-12: Функциональность
**Отдельные коммиты** для каждого подэтапа:
- Конфигурация (1.1, 1.2, 1.3)
- Cache service структуры (2.1, 2.2)
- Cache service методы (2.3, 2.4, 2.5, 2.6)
- И т.д.

### Этап 14-16: Финализация
**Отдельные коммиты**:
- Тесты
- Документация
- Финальная проверка

## Common Issues

### Issue: Старый namespace остался
```bash
# Найти все вхождения
grep -rn "com\.mattermost\.apps" --include="*.go" --include="*.json"

# Заменить автоматически (осторожно!)
find . -type f \( -name "*.go" -o -name "*.json" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -exec sed -i 's/com\.mattermost\.apps/ru.2gis.apps/g' {} +
```

### Issue: Тесты не проходят
```bash
# Запустить конкретный тест с verbose
go test -v ./server/proxy -run TestBindings

# Показать coverage
go test -cover ./...
```

### Issue: Импорты не разрешаются
```bash
# Обновить зависимости
go mod tidy
go mod vendor  # если используется
```

## Git Commands

### Создать feature branch
```bash
git checkout -b feature/v2-refactoring
```

### Staged commit
```bash
# Проверить что добавили
git status

# Добавить изменения
git add <files>

# Коммит с шаблоном
git commit -m "[Этап X] ..."

# Или открыть редактор для полного сообщения
git commit
```

### Просмотр изменений
```bash
# Что изменено (unstaged)
git diff

# Что будет закоммичено (staged)
git diff --staged

# История
git log --oneline
```

### Amend last commit (если нужно исправить)
```bash
git add <forgotten-file>
git commit --amend --no-edit
```

## Final Verification Before Push

```bash
# 1. Все коммиты правильно оформлены
git log --oneline -10

# 2. Нет лишних файлов
git status

# 3. Тесты проходят на последнем коммите
make test

# 4. Код компилируется
go build ./...

# 5. Push в feature branch
git push origin feature/v2-refactoring
```

## Notes

- Делайте коммиты часто, но логично сгруппированные
- Каждый коммит должен компилироваться
- Используйте префикс [Этап X] для соответствия плану
- Документируйте breaking changes в commit message
- Проверяйте чеклист перед каждым коммитом

---

*Следуйте TODO.md для порядка выполнения этапов*
