namespace nh_patchproj.Models;

public record CleanOptions(
    string Path,
    string[] RemovePackages,
    string[] RemovePackageRegex,
    string[] RemoveTags,
    string[] TagInclude,
    bool DryRun,
    bool NoBackup,
    bool Verbose,
    bool Quiet,
    string[] Exclude,
    bool AutoRestore,
    bool SingleFile,
    bool NoAct);