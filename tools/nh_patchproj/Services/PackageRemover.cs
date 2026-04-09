using Microsoft.Build.Construction;
using System.Text.RegularExpressions;

namespace nh_patchproj.Services;

public class PackageRemover
{
    private readonly Logger _logger;

    public PackageRemover(Logger logger) { _logger = logger; }

    public int RemovePackages(ProjectRootElement project, string[] packageNames, string[] regexPatterns)
    {
        int removed = 0;
        
        // Отладка
        _logger.Verbose($"All elements count: {project.Items.Count}");
        foreach (var item in project.Items)
        {
            _logger.Verbose($"  - {item.ItemType}: {item.Include}");
        }
        
        // Поиск PackageReference
        var packages = project.Items
        .Where(i => i.ItemType == "PackageReference" || i.ItemType == "PackageVersion" || i.ItemType == "GlobalPackageReference")
        .ToList();
        
        _logger.Verbose($"Founded PackageReference: {packages.Count}");
        
        foreach (var package in packages)
        {
            _logger.Verbose($"  Check: {package.Include}");
            
            bool shouldRemove = false;
            string reason = "for name";

            if (packageNames.Contains(package.Include, StringComparer.OrdinalIgnoreCase))
            {
                shouldRemove = true;
            }
            else
            {
                foreach (var regex in regexPatterns)
                {
                    if (Regex.IsMatch(package.Include, regex, RegexOptions.IgnoreCase))
                    {
                        shouldRemove = true;
                        reason = $"for mask {regex}";
                        break;
                    }
                }
            }

            if (shouldRemove)
            {
                var version = package.Metadata.FirstOrDefault(m => m.Name == "Version")?.Value ?? "unknown";
                
                // ИСПРАВЛЕНИЕ: Удаляем через родителя (ItemGroup), а не через ProjectRootElement
                var parent = package.Parent;
                if (parent != null)
                {
                    parent.RemoveChild(package);
                    _logger.Info($"   [✓] {Path.GetFileName(project.FullPath)}: {package.Include}@{version} ({reason})");
                    removed++;
                }
                else
                {
                    _logger.Error($"   Error {package.Include}: parent not found");
                }
            }
        }
        
        _logger.Verbose($"Deleted: {removed}");
        return removed;
    }
}