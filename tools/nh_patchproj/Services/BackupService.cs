using Microsoft.Extensions.FileSystemGlobbing;
using Microsoft.Extensions.FileSystemGlobbing.Abstractions;

namespace nh_patchproj.Services;

public class BackupService
{
    private readonly Logger _logger;
    private readonly bool _enabled;

    public BackupService(Logger logger, bool enabled)
    {
        _logger = logger;
        _enabled = enabled;
    }

    public string? CreateBackup(string filePath)
    {
        if (!_enabled) return null;
        var backupPath = filePath + ".bak";
        File.Copy(filePath, backupPath, true);
        _logger.Verbose($"Бэкап создан: {backupPath}");
        return backupPath;
    }

    public void RestoreBackup(string backupPath)
    {
        if (!File.Exists(backupPath)) return;
        var originalPath = backupPath.Replace(".bak", "");
        File.Copy(backupPath, originalPath, true);
        _logger.Info($"Восстановлено: {originalPath}");
    }

    public int RestoreAll(string path, string[] excludePatterns)
    {
        _logger.Info($"🔍 Поиск бэкапов в: {path}");

        var matcher = new Matcher(StringComparison.OrdinalIgnoreCase);
        matcher.AddInclude("**/*.csproj.bak");
        matcher.AddInclude("**/*.props.bak");

        foreach (var pattern in excludePatterns)
            matcher.AddExclude(pattern);

        matcher.AddExclude("**/obj/**");
        matcher.AddExclude("**/bin/**");
        matcher.AddExclude("**/.git/**");

        var results = matcher.Execute(new DirectoryInfoWrapper(new DirectoryInfo(path)));

        int restored = 0;
        foreach (var file in results.Files)
        {
            var backupPath = Path.GetFullPath(Path.Combine(path, file.Path));
            var originalPath = backupPath.Replace(".bak", "");
            File.Copy(backupPath, originalPath, true);
            _logger.Info($"   [✓] Восстановлено: {Path.GetFileName(originalPath)}");
            restored++;
        }

        _logger.Info($"📊 Всего восстановлено: {restored} файлов");
        return restored;
    }

    public int CleanupAll(string path, string[] excludePatterns)
    {
        _logger.Info($"🗑️  Очистка бэкапов в: {path}");

        var matcher = new Matcher(StringComparison.OrdinalIgnoreCase);
        matcher.AddInclude("**/*.bak");

        foreach (var pattern in excludePatterns)
            matcher.AddExclude(pattern);

        var results = matcher.Execute(new DirectoryInfoWrapper(new DirectoryInfo(path)));

        int deleted = 0;
        foreach (var file in results.Files)
        {
            var backupPath = Path.GetFullPath(Path.Combine(path, file.Path));
            File.Delete(backupPath);
            deleted++;
        }

        _logger.Info($"📊 Всего удалено: {deleted} бэкапов");
        return deleted;
    }
}
