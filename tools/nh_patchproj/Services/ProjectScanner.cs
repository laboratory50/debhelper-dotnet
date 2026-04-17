using Microsoft.Extensions.FileSystemGlobbing;
using Microsoft.Extensions.FileSystemGlobbing.Abstractions;

namespace nh_patchproj.Services;

public class ProjectScanner
{
    private readonly Logger _logger;

    public ProjectScanner(Logger logger) { _logger = logger; }

    public List<string> Scan(string path, string[] excludePatterns)
    {
        var files = new List<string>();

        if (File.Exists(path))
        {
            files.Add(Path.GetFullPath(path));
            return files;
        }

        if (!Directory.Exists(path))
        {
            _logger.Error($"Path not found: {path}");
            return files;
        }

        var matcher = new Matcher(StringComparison.OrdinalIgnoreCase);
        matcher.AddInclude("**/*.csproj");
        matcher.AddInclude("**/*.props");
        matcher.AddInclude("**/*.targets");

        foreach (var pattern in excludePatterns)
            matcher.AddExclude(pattern);

        var results = matcher.Execute(new DirectoryInfoWrapper(new DirectoryInfo(path)));

        foreach (var file in results.Files)
        {
            var fullPath = Path.GetFullPath(Path.Combine(path, file.Path));
            if (!files.Contains(fullPath))
                files.Add(fullPath);
        }

        _logger.Verbose($"Founded: {files.Count} project files");
        return files;
    }
}