using Microsoft.Build.Construction;
using nh_patchproj.Models;
using nh_patchproj.Services;
using nh_patchproj.Utils;

namespace nh_patchproj.Commands;

public static class CleanCommand
{
    private const string BackupExtension = ".bak";
    private const string TempExtension = ".tmp";

    public static int Execute(ArgParser.ParsedArgs args)
    {
        var path = ArgParser.GetOption(args, "path") ?? ArgParser.GetOption(args, "p");
        if (string.IsNullOrEmpty(path))
        {
            Console.Error.WriteLine("Error: --path parameter is required");
            return ExitCodes.CriticalError;
        }

        var options = new CleanOptions(
            Path: path,
            RemovePackages: ArgParser.GetOptionArray(args, "remove-package").Concat(ArgParser.GetOptionArray(args, "rp")).ToArray(),
            RemovePackageRegex: ArgParser.GetOptionArray(args, "remove-package-regex").Concat(ArgParser.GetOptionArray(args, "rpr")).ToArray(),
            RemoveTags: ArgParser.GetOptionArray(args, "remove-tag").Concat(ArgParser.GetOptionArray(args, "rt")).ToArray(),
            TagInclude: ArgParser.GetOptionArray(args, "tag-include").Concat(ArgParser.GetOptionArray(args, "ti")).ToArray(),
            DryRun: ArgParser.GetOptionBool(args, "dry-run") || ArgParser.GetOptionBool(args, "d"),
            NoBackup: ArgParser.GetOptionBool(args, "no-backup") || ArgParser.GetOptionBool(args, "nb"),
            Verbose: ArgParser.GetOptionBool(args, "verbose") || ArgParser.GetOptionBool(args, "v"),
            Quiet: ArgParser.GetOptionBool(args, "quiet") || ArgParser.GetOptionBool(args, "q"),
            Exclude: ArgParser.GetOptionArray(args, "exclude").Concat(ArgParser.GetOptionArray(args, "e")).ToArray(),
            AutoRestore: ArgParser.GetOptionBool(args, "auto-restore") || ArgParser.GetOptionBool(args, "ar"),
            SingleFile: ArgParser.GetOptionBool(args, "single-file") || ArgParser.GetOptionBool(args, "sf")
        );

        return Execute(options);
    }

    public static int Execute(CleanOptions options)
    {
        var startTime = DateTime.UtcNow;
        var logger = new Logger(options.Verbose, options.Quiet);
        var result = new OperationResult();

        try
        {
            logger.Info("DotNetProjectHelper v1.0.0");
            logger.Info("Scanning: " + options.Path);

            if (options.DryRun)
                logger.Warning("Preview mode - changes will not be saved");

            logger.Verbose("RemovePackages: [" + string.Join(", ", options.RemovePackages) + "]");
            logger.Verbose("RemoveTags: [" + string.Join(", ", options.RemoveTags) + "]");
            logger.Verbose("SingleFile: " + options.SingleFile);

            var scanner = new ProjectScanner(logger);
            List<string> files;

            if (options.SingleFile)
            {
                if (!File.Exists(options.Path))
                {
                    logger.Error("File not found: " + options.Path);
                    return ExitCodes.CriticalError;
                }

                if (!options.Path.EndsWith(".csproj", StringComparison.OrdinalIgnoreCase) &&
                    !options.Path.EndsWith(".props", StringComparison.OrdinalIgnoreCase))
                {
                    logger.Error("Unsupported file type: " + options.Path);
                    return ExitCodes.CriticalError;
                }

                files = new List<string> { Path.GetFullPath(options.Path) };
                logger.Info("Mode: single file");
            }
            else
            {
                files = scanner.Scan(options.Path, options.Exclude);
                if (files.Count == 0)
                {
                    logger.Error("No project files found");
                    return ExitCodes.CriticalError;
                }
            }

            var backupService = new BackupService(logger, !options.NoBackup && !options.DryRun);
            var packageRemover = new PackageRemover(logger);
            var tagRemover = new TagRemover(logger);

            foreach (var file in files)
            {
                try
                {
                    logger.Verbose("Processing: " + file);

                    if (!options.DryRun)
                        backupService.CreateBackup(file);

                    var project = ProjectRootElement.Open(file);
                    bool modified = false;

                    logger.Verbose("RemovePackages.Length: " + options.RemovePackages.Length);
                    logger.Verbose("RemovePackageRegex.Length: " + options.RemovePackageRegex.Length);
                    logger.Verbose("Condition for RemovePackages: " + (options.RemovePackages.Length > 0 || options.RemovePackageRegex.Length > 0));

                    if (options.RemovePackages.Length > 0 || options.RemovePackageRegex.Length > 0)
                    {
                        logger.Verbose("Calling RemovePackages...");
                        var removed = packageRemover.RemovePackages(project, options.RemovePackages, options.RemovePackageRegex);
                        logger.Verbose("RemovePackages returned: " + removed);
                        result.PackagesRemoved += removed;
                        if (removed > 0) modified = true;
                    }
                    else
                    {
                        logger.Verbose("RemovePackages not called (empty parameters)");
                    }

                    if (options.RemoveTags.Length > 0)
                    {
                        logger.Verbose("Calling RemoveTags...");
                        var removed = tagRemover.RemoveTags(project, options.RemoveTags, options.TagInclude);
                        logger.Verbose("RemoveTags returned: " + removed);
                        result.TagsRemoved += removed;
                        if (removed > 0) modified = true;
                    }

                    if (modified && !options.DryRun)
                    {
                        var tempPath = file + TempExtension;
                        project.Save(tempPath);

                        if (XmlValidator.IsValid(tempPath))
                        {
                            File.Delete(file);
                            File.Move(tempPath, file);
                            result.Changes.Add(file);
                        }
                        else
                        {
                            File.Delete(tempPath);
                            backupService.RestoreBackup(file + BackupExtension);
                            result.Errors.Add("Invalid XML: " + file);
                        }
                    }

                    result.FilesProcessed++;
                }
                catch (Exception ex)
                {
                    result.Errors.Add("Error " + file + ": " + ex.Message);
                    logger.Error("Error " + file + ": " + ex.Message);

                    if (options.AutoRestore && !options.DryRun)
                    {
                        logger.Info("Restoring...");
                        backupService.RestoreBackup(file + BackupExtension);
                    }
                }
            }

            logger.PrintSummary(result, DateTime.UtcNow - startTime);

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
}