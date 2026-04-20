using Microsoft.Build.Construction;
using nh_patchproj.Models;
using nh_patchproj.Services;
using nh_patchproj.Utils;

namespace nh_patchproj.Commands;

public static class CleanCommand
{
    public static int Execute(ArgParser.ParsedArgs args)
    {
        var startTime = DateTime.UtcNow;
        var logger = new Logger(ArgParser.GetOptionBool(args, "verbose") || ArgParser.GetOptionBool(args, "v"));
        var result = new OperationResult();

        try
        {
            string path = ArgParser.GetOption(args, "path").FirstOrDefault() ??
                          ArgParser.GetOption(args, "p").FirstOrDefault() ??
                          Directory.GetCurrentDirectory();

            logger.Info($"Scanning: {path}");
            logger.Info($"Mode: {(args.NoAct ? "no-act (preview)" : "modify")}");

            var scanner = new ProjectScanner(logger);
            var files = scanner.Scan(path, ArgParser.GetOption(args, "exclude"));

            if (files.Count == 0)
            {
                logger.Error("No project files found");
                return ExitCodes.CriticalError;
            }

            result.FilesProcessed = files.Count;

            // Сбор параметров один раз
            var removePackages = ArgParser.GetOption(args, "remove-package").Concat(ArgParser.GetOption(args, "rp")).ToArray();
            var removePackageRegex = ArgParser.GetOption(args, "remove-package-regex").Concat(ArgParser.GetOption(args, "rpr")).ToArray();
            var removeTags = ArgParser.GetOption(args, "remove-tag").Concat(ArgParser.GetOption(args, "rt")).ToArray();
            var tagInclude = ArgParser.GetOption(args, "tag-include").Concat(ArgParser.GetOption(args, "ti")).ToArray();
            var xpaths = ArgParser.GetOption(args, "xpath").Concat(ArgParser.GetOption(args, "x")).ToArray();

            bool enableBackup = ArgParser.GetOptionBool(args, "backup") || ArgParser.GetOptionBool(args, "b");
            var backupService = new BackupService(logger, enableBackup && !ArgParser.GetOptionBool(args, "dry-run"));
            var packageRemover = new PackageRemover(logger);
            var tagRemover = new TagRemover(logger);

            foreach (var file in files)
            {
                try
                {
                    var project = ProjectRootElement.Open(file);

                    // 🔹 ЕДИНАЯ ТОЧКА ПРОВЕРКИ
                    bool wouldModify = ProjectAnalyzer.WouldModify(project, removePackages, removePackageRegex, removeTags, tagInclude, xpaths);

                    if (args.NoAct)
                    {
                        // ✅ РЕЖИМ ПРЕДПРОСМОТРА: только вывод файлов
                         if (wouldModify)
                         {
                             var relativePath = Path.GetRelativePath(Directory.GetCurrentDirectory(), file);
                             Console.WriteLine(relativePath);
                         }
                    }
                    else
                    {
                        // ✅ РЕЖИМ ИЗМЕНЕНИЙ: применение логики
                        logger.Verbose($"Processing: {Path.GetFileName(file)}");
                        if (!ArgParser.GetOptionBool(args, "dry-run"))
                            backupService.CreateBackup(file);

                        bool modified = false;
                        int pkgRemoved = packageRemover.RemovePackages(project, removePackages, removePackageRegex);
                        if (pkgRemoved > 0) { modified = true; result.PackagesRemoved += pkgRemoved; }

                        int tagsRemoved = tagRemover.RemoveTags(project, removeTags, tagInclude, xpaths);
                        if (tagsRemoved > 0) { modified = true; result.TagsRemoved += tagsRemoved; }

                        if (modified && !ArgParser.GetOptionBool(args, "dry-run"))
                        {
                            AtomicFileWriter.Save(project, file); // 🔹 Атомарная запись по умолчанию
                            logger.Info($"[OK] Modified: {Path.GetFileName(file)}");
                        }
                        else if (modified)
                        {
                            logger.Info($"[DRY-RUN] Would modify: {Path.GetFileName(file)}");
                        }
                    }
                }
                catch (Exception ex)
                {
                    logger.Error($"Error processing {file}: {ex.Message}");
                    result.Errors.Add($"Error {file}: {ex.Message}");
                }
            }

            PrintSummary(result, startTime, logger);
            return result.HasErrors ? ExitCodes.CriticalError : (result.HasWarnings ? ExitCodes.Warning : ExitCodes.Success);
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
        logger.Info($"   Packages removed: {result.PackagesRemoved}");
        logger.Info($"   Tags removed: {result.TagsRemoved}");
        logger.Info($"   Execution time: {duration.TotalSeconds:F1}s");
        if (result.HasWarnings) logger.Info($"   Warnings: {result.Warnings.Count}");
    }
}