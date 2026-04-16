using Microsoft.Extensions.FileSystemGlobbing;
using Microsoft.Extensions.FileSystemGlobbing.Abstractions;

namespace nh_patchproj.Services;

public class BackupService
{
    private readonly Logger _logger;
    private readonly bool _enabled;
    private const string BackupSuffix = "~";

    public BackupService(Logger logger, bool enabled)
    {
        _logger = logger;
        _enabled = enabled;
    }

    public string? CreateBackup(string filePath)
    {
        if (!_enabled) return null;
        var backupPath = filePath + BackupSuffix;
        File.Copy(filePath, backupPath, true);
        _logger.Verbose($"Backup created: {backupPath}");
        return backupPath;
    }

    public void RestoreBackup(string backupPath)
    {
        if (!File.Exists(backupPath) || !backupPath.EndsWith(BackupSuffix)) return;
        var originalPath = backupPath.Substring(0, backupPath.Length - BackupSuffix.Length);
        File.Copy(backupPath, originalPath, true);
        _logger.Info($"Restored: {originalPath}");
    }

    public int RestoreAll(string path, string[] excludePatterns)
    {
        _logger.Info($"[SEARCH] Searching for backups in: {path}");
        var matcher = new Matcher(StringComparison.OrdinalIgnoreCase);

        // ?? УНИВЕРСАЛЬНЫЙ ПАТТЕРН: ищет любые файлы, оканчивающиеся на ~
        matcher.AddInclude($"**/*{BackupSuffix}");

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
            var originalPath = backupPath.Substring(0, backupPath.Length - BackupSuffix.Length);
            File.Copy(backupPath, originalPath, true);
            _logger.Info($"   [OK] Restored: {Path.GetFileName(originalPath)}");
            restored++;
        }
        _logger.Info($"[SUMMARY] Total restored: {restored} files");
        return restored;
    }

    public int CleanupAll(string path, string[] excludePatterns)
    {
        _logger.Info($"[CLEANUP] Cleaning backups in: {path}");
        var matcher = new Matcher(StringComparison.OrdinalIgnoreCase);
        matcher.AddInclude($"**/*{BackupSuffix}"); // То же универсальное правило

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
        _logger.Info($"[SUMMARY] Total deleted: {deleted} backups");
        return deleted;
    }
}