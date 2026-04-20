# nh_patchproj
Utility for modifying MSBuild project files (.csproj, .props, .targets)
---
## Usage
nh_patchproj <command> [options]

> Version is managed dynamically via <Version> in .csproj. Show it with nh_patchproj --version.

---
## Global Options
| Option | Short | Description |
|--------|-------|-------------|
| --version | -ver | Show utility version |
| --help | -h | Show this help message |
---
## Commands
| Command | Description |
|---------|-------------|
| clean | Analyze and modify project files |
| restore | Restore files from backups |
---
## Options for clean command
| Option | Short | Description |
|--------|-------|-------------|
| --path | -p | Path to directory or file (default: current directory) |
| --remove-package | -rp | NuGet package to remove (can be repeated) |
| --remove-package-regex | -rpr | Regex pattern to match package names |
| --remove-tag | -rt | MSBuild tag/element to remove (can be repeated) |
| --tag-include | -ti | Filter tags by Include, Condition, or Command attribute |
| --xpath | -x | XPath-like expression for advanced tag selection |
| --dry-run | -d | Preview mode: log changes without saving files |
| --backup | -b | Enable backups before modification (creates filename~ files) |
| --no-act | -na | List-only mode: output paths of files that would be modified |
| --exclude | -e | Exclude paths by glob pattern |
| --verbose | -v | Enable detailed logging |
---
## Options for restore command
| Option | Short | Description |
|--------|-------|-------------|
| --path | -p | Path to directory (default: current directory) |
| --cleanup | -c | Delete backup files after successful restoration |
| --exclude | -e | Exclude paths by glob pattern |
| --verbose | -v | Enable detailed logging |
---
## Usage Examples
### Removing packages
nh_patchproj clean -p ./src -rp Newtonsoft.Json
nh_patchproj clean -p ./src -rp Newtonsoft.Json -rp System.Data.SqlClient
nh_patchproj clean -p ./src -rpr ".*\.Tests$"
### Removing tags & elements
nh_patchproj clean -p MyProject.csproj -rt Exec
nh_patchproj clean -p MyProject.csproj -rt Exec -ti powershell
nh_patchproj clean -p MyProject.csproj -rt Target -ti PreBuild
### Preview & Safety modes
nh_patchproj clean -p ./src -rp OldPackage --no-act
nh_patchproj clean -p ./src -rp TestPackage -d -v
nh_patchproj clean -p ./src -rp OldPackage --backup
### Restoring from backups
nh_patchproj restore -p ./src
nh_patchproj restore -p ./src -c
---
## Exit Codes
| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Critical error |
| 2 | Completed with warnings |
---
## CI/CD & Integration
### GitHub Actions / Linux
```yaml
- name: Clean packages
  run: nh_patchproj clean -p ./src -rp Unwanted.Package --backup
- name: Restore if needed
  run: nh_patchproj restore -p ./src --cleanup || true