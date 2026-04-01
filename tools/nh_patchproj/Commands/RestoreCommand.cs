using nh_patchproj.Models;
using nh_patchproj.Services;
using nh_patchproj.Utils;

namespace nh_patchproj.Commands;

public static class RestoreCommand
{
    public static int Execute(ArgParser.ParsedArgs args)
    {
        var path = ArgParser.GetOption(args, "path") ?? ArgParser.GetOption(args, "p");
        if (string.IsNullOrEmpty(path))
        {
            Console.Error.WriteLine("❌ Ошибка: параметр --path обязателен");
            return ExitCodes.CriticalError;
        }

        var options = new RestoreOptions(
            Path: path,
            Verbose: ArgParser.GetOptionBool(args, "verbose") || ArgParser.GetOptionBool(args, "v"),
            Quiet: ArgParser.GetOptionBool(args, "quiet") || ArgParser.GetOptionBool(args, "q"),
            Exclude: ArgParser.GetOptionArray(args, "exclude").Concat(ArgParser.GetOptionArray(args, "e")).ToArray(),
            Cleanup: ArgParser.GetOptionBool(args, "cleanup") || ArgParser.GetOptionBool(args, "c")
        );

        return Execute(options);
    }

    public static int Execute(RestoreOptions options)
    {
        var startTime = DateTime.UtcNow;
        var logger = new Logger(options.Verbose, options.Quiet);

        try
        {
            logger.Info($"🔧 DotNetProjectHelper v1.0.0 — Восстановление");
            logger.Info($"📁 Путь: {options.Path}");

            if (!Directory.Exists(options.Path))
            {
                logger.Error($"Путь не найден: {options.Path}");
                return ExitCodes.CriticalError;
            }

            var backupService = new BackupService(logger, true);
            var restored = backupService.RestoreAll(options.Path, options.Exclude);

            if (restored == 0)
            {
                logger.Warning("Бэкапы не найдены");
                return ExitCodes.Warning;
            }

            if (options.Cleanup)
            {
                logger.Info("🗑️  Очистка бэкапов...");
                backupService.CleanupAll(options.Path, options.Exclude);
            }

            var duration = DateTime.UtcNow - startTime;
            logger.Info($"✅ Завершено за {duration.TotalSeconds:F1}с");

            return ExitCodes.Success;
        }
        catch (Exception ex)
        {
            logger.Error($"Критическая ошибка: {ex.Message}");
            return ExitCodes.CriticalError;
        }
    }
}
