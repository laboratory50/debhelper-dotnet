# nh_patchproj v1.0.0

Утилита для модификации MSBuild-проектов (.csproj, .props)

---

## Использование

    nh_patchproj <команда> [опции]

---

## Команды

| Команда | Описание |
|---------|----------|
| clean | Очистка и модификация проектов |
| restore | Восстановление файлов из бэкапов |
| help | Показать эту справку |

---

## Опции команды clean

| Опция | Краткая | Описание |
|-------|---------|----------|
| --path | -p | Путь к директории или файлу (обязательно) |
| --remove-package | -rp | Пакет для удаления (можно несколько раз) |
| --remove-package-regex | -rpr | Regex для удаления пакетов |
| --remove-tag | -rt | Тег для удаления (можно несколько раз) |
| --tag-include | -ti | Фильтр по атрибуту Include/Condition/Command |
| --dry-run | -d | Режим предпросмотра без записи |
| --no-backup | -nb | Не создавать бэкапы |
| --auto-restore | -ar | Автовосстановление при ошибке |
| --single-file | -sf | Обработать один файл (не сканировать) |
| --exclude | -e | Исключить пути по маске |
| --verbose | -v | Подробное логирование |
| --quiet | -q | Минимальное логирование |

---

## Опции команды restore

| Опция | Краткая | Описание |
|-------|---------|----------|
| --path | -p | Путь к директории (обязательно) |
| --cleanup | -c | Удалить бэкапы после восстановления |
| --exclude | -e | Исключить пути по маске |
| --verbose | -v | Подробное логирование |
| --quiet | -q | Минимальное логирование |

---

## Примеры использования

### Удаление пакетов

    # Удалить один пакет из всех проектов в директории
    nh_patchproj clean -p ./src -rp Newtonsoft.Json

    # Удалить несколько пакетов
    nh_patchproj clean -p ./src -rp Newtonsoft.Json -rp System.Data.SqlClient

    # Удалить пакеты по regex
    nh_patchproj clean -p ./src -rpr ".*\.Tests$"

### Удаление тегов

    # Удалить Exec с Windows_NT в Condition
    nh_patchproj clean -p MyProject.csproj -sf -rt Exec -ti "Windows_NT"

    # Удалить Exec с powershell в Command
    nh_patchproj clean -p MyProject.csproj -sf -rt Exec -ti "powershell"

    # Удалить Target PreBuild целиком
    nh_patchproj clean -p MyProject.csproj -sf -rt Target -ti PreBuild

### Режимы работы

    # Предпросмотр изменений без записи
    nh_patchproj clean -p ./src -rp TestPackage -d

    # Обработать один конкретный файл
    nh_patchproj clean -p MyProject.csproj -sf -rp OldLib

    # Без создания бэкапов (для CI/CD)
    nh_patchproj clean -p ./src -rp Test -nb

### Восстановление из бэкапов

    # Восстановить все файлы из бэкапов
    nh_patchproj restore -p ./src

    # Восстановить и удалить бэкапы
    nh_patchproj restore -p ./src -c

---

## Коды возврата

| Код | Значение |
|-----|----------|
| 0 | Успешное выполнение |
| 1 | Критическая ошибка |
| 2 | Выполнено с предупреждениями |

---

## Интеграция с debian/rules

    override_dh_auto_build:
        nh_patchproj clean --path $(CURDIR)/src --remove-package "Newtonsoft.Json" --no-backup --quiet
        dh_auto_build

    override_dh_auto_clean:
        nh_patchproj restore --path $(CURDIR)/src --cleanup || true
        dh_auto_clean

---

## Лицензия

MIT License
