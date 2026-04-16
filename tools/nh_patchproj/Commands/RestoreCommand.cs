using nh_patchproj.Models;
using nh_patchproj.Services;
using nh_patchproj.Utils;

namespace nh_patchproj.Commands;

public static class RestoreCommand
{
    private const string BackupSuffix = "~";

    public static int Execute(ArgParser.ParsedArgs args)
    {
        var startTime = DateTime.UtcNow;
        var logger = new Logger(
            ArgParser.GetOptionBool(args, "verbose") || ArgParser.GetOptionBool(args, "v")
        );
        var result = new OperationResult();

        try
        {
            // 🔹 ИЗМЕНЕНИЕ: если path не указан, используем текущую директорию
            var pathOptions = ArgParser.GetOption(args, "path");
            var pOptions = ArgParser.GetOption(args, "p");
            string? path = null;
            
            if (pathOptions.Length > 0)
                path = pathOptions[0];
            else if (pOptions.Length > 0)
                path = pOptions[0];
            else
                path = Directory.GetCurrentDirectory();  // ← ТЕПЕРЬ ПО УМОЛЧАНИЮ
            
            logger.Info("Path: " + path);

            if (!Directory.Exists(path))
            {
                logger.Error("Path not found: " + path);
                return ExitCodes.CriticalError;
            }

            var exclude = ArgParser.GetOption(args, "exclude")
                .Concat(ArgParser.GetOption(args, "e")).ToArray();
            var cleanup = ArgParser.GetOptionBool(args, "cleanup") || ArgParser.GetOptionBool(args, "c");

            var scanner = new ProjectScanner(logger);
            var files = scanner.Scan(path, exclude);
            
            if (files.Count == 0)
            {
                logger.Warning("No backup files found");
                return ExitCodes.Success;
            }

            result.FilesProcessed = files.Count;
            var backupService = new BackupService(logger, false);

            foreach (var file in files)
            {
                try
                {
                    var backupFile = file + BackupSuffix;
                    if (!File.Exists(backupFile)) continue;

                    logger.Verbose("Restoring: " + file);

                    File.Copy(backupFile, file, overwrite: true);
                    
                    if (cleanup)
                    {
                        File.Delete(backupFile);
                        logger.Info($"[OK] Restored and cleaned: {Path.GetFileName(file)}");
                    }
                    else
                    {
                        logger.Info($"[OK] Restored: {Path.GetFileName(file)}");
                    }
                    
                    result.FilesProcessed++;
                }
                catch (Exception ex)
                {
                    logger.Error($"Error restoring {file}: {ex.Message}");
                    result.Errors.Add("Error " + file + ": " + ex.Message);
                }
            }

            PrintSummary(result, startTime, logger);
            
            if (result.HasErrors)
            {
                logger.Error("Errors: " + result.Errors.Count);
                return ExitCodes.CriticalError;
            }
            
            return result.HasWarnings ? ExitCodes.Warning : ExitCodes.Success;
        }
        catch (Exception ex)
        {
            logger.Error("Critical error: " + ex.Message);
            return ExitCodes.CriticalError;
        }
    }

    private static void PrintSummary(OperationResult result, DateTime startTime, Logger logger)
    {
        var duration = DateTime.UtcNow - startTime;

        logger.Info("");
        logger.Info("Summary:");
        logger.Info($"   Files processed: {result.FilesProcessed}");
        logger.Info($"   Files restored: {result.FilesProcessed}");
        logger.Info($"   Execution time: {duration.TotalSeconds:F1}s");

        if (result.HasWarnings)
            logger.Info($"   Warnings: {result.Warnings.Count}");
    }
}