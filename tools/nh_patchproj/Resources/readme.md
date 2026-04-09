# nh_patchproj v1.0.0

Utility for modifying MSBuild project files (.csproj, .props)

---

## Usage

    nh_patchproj <command> [options]

---

## Commands

| Command | Description |
|---------|-------------|
| clean | Clean and modify projects |
| restore | Restore files from backups |
| help | Show this help message |

---

## Options for 'clean' command

| Option | Short | Description |
|--------|-------|-------------|
| --path | -p | Path to directory or file (required) |
| --remove-package | -rp | Package to remove (can be used multiple times) |
| --remove-package-regex | -rpr | Regex pattern for removing packages |
| --remove-tag | -rt | Tag to remove (can be used multiple times) |
| --tag-include | -ti | Filter by Include/Condition/Command attribute |
| --dry-run | -d | Preview mode without writing changes |
| --no-backup | -nb | Do not create backup files |
| --auto-restore | -ar | Auto-restore on error |
| --single-file | -sf | Process single file (do not scan directory) |
| --exclude | -e | Exclude paths by pattern |
| --verbose | -v | Verbose logging |
| --quiet | -q | Minimal logging |
| --no-act | -na | List files that would be modified (no changes, minimal output) |
| --xpath | -x | XPath expression for advanced tag selection |

---

## Options for 'restore' command

| Option | Short | Description |
|--------|-------|-------------|
| --path | -p | Path to directory (required) |
| --cleanup | -c | Delete backups after restoration |
| --exclude | -e | Exclude paths by pattern |
| --verbose | -v | Verbose logging |
| --quiet | -q | Minimal logging |

---

## Usage Examples

### Removing packages

    # Remove a single package from all projects in directory
    nh_patchproj clean -p ./src -rp Newtonsoft.Json

    # Remove multiple packages
    nh_patchproj clean -p ./src -rp Newtonsoft.Json -rp System.Data.SqlClient

    # Remove packages by regex pattern
    nh_patchproj clean -p ./src -rpr ".*\.Tests$"

### Removing tags

    # Remove Exec with Windows_NT in Condition attribute
    nh_patchproj clean -p MyProject.csproj -sf -rt Exec -ti "Windows_NT"

    # Remove Exec with powershell in Command attribute
    nh_patchproj clean -p MyProject.csproj -sf -rt Exec -ti "powershell"

    # Remove entire Target PreBuild element
    nh_patchproj clean -p MyProject.csproj -sf -rt Target -ti PreBuild

### Working modes

    # Preview changes without writing
    nh_patchproj clean -p ./src -rp TestPackage -d

    # Process a single specific file
    nh_patchproj clean -p MyProject.csproj -sf -rp OldLib

    # Without creating backups (for CI/CD)
    nh_patchproj clean -p ./src -rp Test -nb

### Restoring from backups

    # Restore all files from backups
    nh_patchproj restore -p ./src

    # Restore and delete backup files
    nh_patchproj restore -p ./src -c

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Critical error |
| 2 | Completed with warnings |

---

## Integration with debian/rules

    override_dh_auto_build:
        nh_patchproj clean --path $(CURDIR)/src --remove-package "Newtonsoft.Json" --no-backup --quiet
        dh_auto_build

    override_dh_auto_clean:
        nh_patchproj restore --path $(CURDIR)/src --cleanup || true
        dh_auto_clean

---

## License

MIT License