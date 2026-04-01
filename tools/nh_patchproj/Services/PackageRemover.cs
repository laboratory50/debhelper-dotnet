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
        _logger.Verbose($"Всего элементов в проекте: {project.Items.Count}");
        foreach (var item in project.Items)
        {
            _logger.Verbose($"  - {item.ItemType}: {item.Include}");
        }
        
        // Поиск PackageReference
        var packages = project.Items
            .Where(i => i.ItemType == "PackageReference")
            .ToList();
        
        _logger.Verbose($"Найдено PackageReference: {packages.Count}");
        
        foreach (var package in packages)
        {
            _logger.Verbose($"  Проверка: {package.Include}");
            
            bool shouldRemove = false;
            string reason = "по имени";

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
                        reason = $"по маске {regex}";
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
                    _logger.Error($"   [✗] Не удалось удалить {package.Include}: родитель не найден");
                }
            }
        }
        
        _logger.Verbose($"Удалено пакетов: {removed}");
        return removed;
    }
}