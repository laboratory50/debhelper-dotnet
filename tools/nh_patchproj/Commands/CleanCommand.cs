using Microsoft.Build.Construction;
using nh_patchproj.Models;
using nh_patchproj.Services;
using nh_patchproj.Utils;
using System.Text.RegularExpressions;

namespace nh_patchproj.Commands;

public static class CleanCommand
{
    private const string BackupExtension = ".bak";

    public static int Execute(ArgParser.ParsedArgs args)
    {
        var startTime = DateTime.UtcNow;
        var logger = new Logger(
            ArgParser.GetOptionBool(args, "verbose") || ArgParser.GetOptionBool(args, "v"),
            ArgParser.GetOptionBool(args, "quiet") || ArgParser.GetOptionBool(args, "q")
        );
        var result = new OperationResult();

        try
        {
            logger.Info("DotNetProjectHelper v1.0.0");
            
            // Получение пути (если не указан - текущая директория)
            var pathOptions = ArgParser.GetOption(args, "path");
            var pOptions = ArgParser.GetOption(args, "p");
            string? path = null;
            
            if (pathOptions.Length > 0)
                path = pathOptions[0];
            else if (pOptions.Length > 0)
                path = pOptions[0];
            else
                path = Directory.GetCurrentDirectory();
            
            logger.Info("Scanning: " + path);
            logger.Info("Mode: " + (ArgParser.GetOptionBool(args, "single-file") || ArgParser.GetOptionBool(args, "sf") ? "single file" : "directory scan"));

            // 🔹 РЕЖИМ NO-ACT: только вывод списка файлов без изменений
            if (args.NoAct)
            {
                var noActScanner = new ProjectScanner(logger);
                var noActFiles = ArgParser.GetOptionBool(args, "single-file") || ArgParser.GetOptionBool(args, "sf")
                    ? new List<string> { Path.GetFullPath(path) }
                    : noActScanner.Scan(path, ArgParser.GetOption(args, "exclude"));

                var removePackages = ArgParser.GetOption(args, "remove-package")
                    .Concat(ArgParser.GetOption(args, "rp")).ToArray();
                var removeTags = ArgParser.GetOption(args, "remove-tag")
                    .Concat(ArgParser.GetOption(args, "rt")).ToArray();
                var tagInclude = ArgParser.GetOption(args, "tag-include")
                    .Concat(ArgParser.GetOption(args, "ti")).ToArray();
                var xpaths = ArgParser.GetOption(args, "xpath")
                    .Concat(ArgParser.GetOption(args, "x")).ToArray();

                foreach (var file in noActFiles)
                {
                    bool wouldModify = false;

                    // Проверка PackageReference/PackageVersion/GlobalPackageReference
                    if (removePackages.Length > 0)
                    {
                        var project = ProjectRootElement.Open(file);
                        var packages = project.Items.Where(i => 
                            i.ItemType == "PackageReference" ||
                            i.ItemType == "PackageVersion" ||
                            i.ItemType == "GlobalPackageReference"
                        ).ToList();

                        foreach (var pkg in packages)
                        {
                            if (removePackages.Contains(pkg.Include, StringComparer.OrdinalIgnoreCase))
                            {
                                wouldModify = true;
                                break;
                            }
                        }
                    }

                    // Проверка тегов
                    if (!wouldModify && removeTags.Length > 0)
                    {
                        var project = ProjectRootElement.Open(file);
                        foreach (var tagName in removeTags)
                        {
                            var items = project.Items.Where(i => 
                                i.ItemType.Equals(tagName, StringComparison.OrdinalIgnoreCase)
                            ).ToList();

                            if (tagInclude.Length > 0)
                            {
                                if (items.Any(i => tagInclude.Any(ti =>
                                    i.Include.Equals(ti, StringComparison.OrdinalIgnoreCase) ||
                                    i.Include.Contains(ti, StringComparison.OrdinalIgnoreCase))))
                                {
                                    wouldModify = true;
                                    break;
                                }
                            }
                            else if (items.Count > 0)
                            {
                                wouldModify = true;
                                break;
                            }
                        }
                    }

                    /// 🔹 ИСПРАВЛЕНИЕ: Более точная проверка XPath в no-act режиме
if (!wouldModify && xpaths.Length > 0)
{
    var content = File.ReadAllText(file);
    
    foreach (var xpath in xpaths)
    {
        // Парсим простой XPath: //ElementName[@Attr='value']
        var elementMatch = Regex.Match(xpath, @"//(\w+)(?:\[@(\w+)='([^']+)'\])?");
        
        if (!elementMatch.Success) continue;
        
        var elementName = elementMatch.Groups[1].Value;
        var attrName = elementMatch.Groups[2].Value;
        var attrValue = elementMatch.Groups[3].Value;
        
        bool found = false;
        
        if (!string.IsNullOrEmpty(attrName) && !string.IsNullOrEmpty(attrValue))
        {
            // Ищем точное совпадение: <ElementName ... Attr="value"
            // Учитываем порядок атрибутов и пробелы
            var patterns = new[]
            {
                $"<{elementName}\\s+[^>]*{attrName}=\"{attrValue}\"",
                $"<{elementName}\\s+[^>]*{attrName}='{attrValue}'",
                $"<{elementName}\\s+{attrName}=\"{attrValue}\"",
                $"<{elementName}\\s+{attrName}='{attrValue}'"
            };
            
            foreach (var pattern in patterns)
            {
                if (Regex.IsMatch(content, pattern, RegexOptions.IgnoreCase))
                {
                    found = true;
                    break;
                }
            }
        }
        else
        {
            // Только имя элемента: <ElementName
            if (Regex.IsMatch(content, $"<{elementName}(\\s|>)", RegexOptions.IgnoreCase))
            {
                found = true;
            }
        }
        
        if (found)
        {
            wouldModify = true;
            break;
        }
    }
}

                    if (wouldModify)
                    {
                        Console.WriteLine(file);
                        result.FilesProcessed++;
                    }
                }

                return ExitCodes.Success;
            }

            // 🔹 ОСНОВНОЙ РЕЖИМ: реальная модификация файлов
            logger.Warning("Preview mode - changes will not be saved");
            logger.Verbose("RemovePackages: [" + string.Join(", ", ArgParser.GetOption(args, "remove-package").Concat(ArgParser.GetOption(args, "rp"))) + "]");
            logger.Verbose("RemoveTags: [" + string.Join(", ", ArgParser.GetOption(args, "remove-tag").Concat(ArgParser.GetOption(args, "rt"))) + "]");
            logger.Verbose("XPath: [" + string.Join(", ", ArgParser.GetOption(args, "xpath").Concat(ArgParser.GetOption(args, "x"))) + "]");
            logger.Verbose("SingleFile: " + (ArgParser.GetOptionBool(args, "single-file") || ArgParser.GetOptionBool(args, "sf")));

            var scanner = new ProjectScanner(logger);
            List<string> files;

            if (ArgParser.GetOptionBool(args, "single-file") || ArgParser.GetOptionBool(args, "sf"))
            {
                if (!File.Exists(path))
                {
                    logger.Error("File not found: " + path);
                    return ExitCodes.CriticalError;
                }

                if (!path.EndsWith(".csproj", StringComparison.OrdinalIgnoreCase) &&
                    !path.EndsWith(".props", StringComparison.OrdinalIgnoreCase) &&
                    !path.EndsWith(".targets", StringComparison.OrdinalIgnoreCase))
                {
                    logger.Error("Unsupported file type: " + path);
                    return ExitCodes.CriticalError;
                }

                files = new List<string> { Path.GetFullPath(path) };
            }
            else
            {
                files = scanner.Scan(path, ArgParser.GetOption(args, "exclude"));
                if (files.Count == 0)
                {
                    logger.Error("No project files found");
                    return ExitCodes.CriticalError;
                }
            }

            result.FilesProcessed = files.Count;
            var backupService = new BackupService(logger, !ArgParser.GetOptionBool(args, "no-backup") && !ArgParser.GetOptionBool(args, "dry-run"));

            var packageRemover = new PackageRemover(logger);
            var tagRemover = new TagRemover(logger);

            foreach (var file in files)
            {
                try
                {
                    logger.Verbose("Processing: " + file);

                    if (!ArgParser.GetOptionBool(args, "dry-run"))
                        backupService.CreateBackup(file);

                    var project = ProjectRootElement.Open(file);
                    bool modified = false;

                    var removePackages = ArgParser.GetOption(args, "remove-package")
                        .Concat(ArgParser.GetOption(args, "rp")).ToArray();
                    var removePackageRegex = ArgParser.GetOption(args, "remove-package-regex")
                        .Concat(ArgParser.GetOption(args, "rpr")).ToArray();

                    if (removePackages.Length > 0 || removePackageRegex.Length > 0)
                    {
                        var removed = packageRemover.RemovePackages(project, removePackages, removePackageRegex);
                        if (removed > 0)
                        {
                            modified = true;
                            result.PackagesRemoved += removed;
                        }
                    }

                    var removeTags = ArgParser.GetOption(args, "remove-tag")
                        .Concat(ArgParser.GetOption(args, "rt")).ToArray();
                    var tagInclude = ArgParser.GetOption(args, "tag-include")
                        .Concat(ArgParser.GetOption(args, "ti")).ToArray();
                    var xpaths = ArgParser.GetOption(args, "xpath")
                        .Concat(ArgParser.GetOption(args, "x")).ToArray();

                    if (removeTags.Length > 0 || xpaths.Length > 0)
                    {
                        var removed = tagRemover.RemoveTags(project, removeTags, tagInclude, xpaths);
                        if (removed > 0)
                        {
                            modified = true;
                            result.TagsRemoved += removed;
                        }
                    }

                    if (modified && !ArgParser.GetOptionBool(args, "dry-run"))
                    {
                        project.Save();
                        logger.Info($"[OK] Modified: {Path.GetFileName(file)}");
                    }
                    else if (modified && ArgParser.GetOptionBool(args, "dry-run"))
                    {
                        logger.Info($"[DRY-RUN] Would modify: {Path.GetFileName(file)}");
                    }
                }
                catch (Exception ex)
                {
                    logger.Error($"Error processing {file}: {ex.Message}");
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
        logger.Info($"   Packages removed: {result.PackagesRemoved}");
        logger.Info($"   Tags removed: {result.TagsRemoved}");
        logger.Info($"   Execution time: {duration.TotalSeconds:F1}s");

        if (result.HasWarnings)
            logger.Info($"   Warnings: {result.Warnings.Count}");
    }
}