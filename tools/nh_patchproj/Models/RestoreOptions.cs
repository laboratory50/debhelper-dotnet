namespace nh_patchproj.Models;

public record RestoreOptions(
    string Path,
    bool Verbose,
    bool Quiet,
    string[] Exclude,
    bool Cleanup
);
