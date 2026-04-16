using Microsoft.Build.Construction;
using System.Text.RegularExpressions;

namespace nh_patchproj.Services;

public static class ProjectAnalyzer
{
    /// <summary>
    /// Проверяет, требует ли проект изменений по заданным критериям.
    /// Используется исключительно для режима --no-act.
    /// </summary>
    public static bool WouldModify(ProjectRootElement project,
                                   string[] removePackages, string[] removePackageRegex,
                                   string[] removeTags, string[] tagIncludes, string[] xpaths)
    {
        // 1. Пакеты
        var packages = project.Items.Where(i =>
            i.ItemType is "PackageReference" or "PackageVersion" or "GlobalPackageReference");

        foreach (var pkg in packages)
        {
            if (removePackages.Contains(pkg.Include, StringComparer.OrdinalIgnoreCase)) return true;
            if (removePackageRegex.Any(r => Regex.IsMatch(pkg.Include, r, RegexOptions.IgnoreCase))) return true;
        }

        // 2. Теги и элементы
        foreach (var tagName in removeTags)
        {
            var items = project.Items.Where(i => i.ItemType.Equals(tagName, StringComparison.OrdinalIgnoreCase)).ToList();
            if (tagIncludes.Length == 0 && items.Count > 0) return true;
            if (items.Any(i => tagIncludes.Any(ti => i.Include.Contains(ti, StringComparison.OrdinalIgnoreCase)))) return true;

            if (tagName.Equals("Target", StringComparison.OrdinalIgnoreCase))
            {
                if (project.Targets.Any(t => tagIncludes.Length == 0 || tagIncludes.Any(ti => t.Name.Contains(ti, StringComparison.OrdinalIgnoreCase)))) return true;
            }

            if (tagName.Equals("Exec", StringComparison.OrdinalIgnoreCase))
            {
                foreach (var t in project.Targets)
                {
                    foreach (var exec in t.Tasks.Where(task => task.Name.Equals("Exec", StringComparison.OrdinalIgnoreCase)))
                    {
                        bool match = tagIncludes.Length == 0 ||
                                     (!string.IsNullOrEmpty(exec.Condition) && tagIncludes.Any(ti => exec.Condition.Contains(ti, StringComparison.OrdinalIgnoreCase))) ||
                                     (!string.IsNullOrEmpty(exec.GetParameter("Command")) && tagIncludes.Any(ti => exec.GetParameter("Command").Contains(ti, StringComparison.OrdinalIgnoreCase)));
                        if (match) return true;
                    }
                }
            }

            if (tagName.Equals("PropertyGroup", StringComparison.OrdinalIgnoreCase))
            {
                if (project.PropertyGroups.Any(pg => tagIncludes.Any(ti => pg.Condition.Contains(ti, StringComparison.OrdinalIgnoreCase)))) return true;
            }
        }

        // 3. XPath (полная совместимость с логикой TagRemover)
        foreach (var xpath in xpaths)
        {
            var elementName = xpath.TrimStart('/').Split('[')[0];
            var includeMatch = Regex.Match(xpath, @"\[@Include='([^']+)'\]");
            var nameMatch = Regex.Match(xpath, @"\[@Name='([^']+)'\]");

            string includeValue = includeMatch.Success ? includeMatch.Groups[1].Value : null;
            string nameValue = nameMatch.Success ? nameMatch.Groups[1].Value : null;

            if (elementName.Equals("Target", StringComparison.OrdinalIgnoreCase) && !string.IsNullOrEmpty(nameValue))
            {
                if (project.Targets.Any(t => t.Name.Equals(nameValue, StringComparison.OrdinalIgnoreCase))) return true;
            }
            else if (!string.IsNullOrEmpty(includeValue))
            {
                if (project.Items.Any(i => i.ItemType.Equals(elementName, StringComparison.OrdinalIgnoreCase) && i.Include.Equals(includeValue, StringComparison.OrdinalIgnoreCase))) return true;
            }
            else
            {
                if (project.Items.Any(i => i.ItemType.Equals(elementName, StringComparison.OrdinalIgnoreCase))) return true;
            }
        }

        return false;
    }
}