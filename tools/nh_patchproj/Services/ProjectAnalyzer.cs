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
            if (project.Properties.Any(p =>
                p.Name.Equals(tagName, StringComparison.OrdinalIgnoreCase) &&
                (tagIncludes.Length == 0 || tagIncludes.Any(ti => p.Value.Contains(ti, StringComparison.OrdinalIgnoreCase)))))
                return true;

            if (project.Items.Any(i =>
                i.ItemType.Equals(tagName, StringComparison.OrdinalIgnoreCase) &&
                (tagIncludes.Length == 0 || tagIncludes.Any(ti => i.Include.Contains(ti, StringComparison.OrdinalIgnoreCase)))))
                return true;

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

        // 3. XPath
        foreach (var xpath in xpaths)
        {
            var cleanXpath = xpath.TrimStart('/');
            var parts = cleanXpath.Split(new[] { '[' }, 2);
            var elementName = parts[0].Trim('/');
            string attrValue = null;
            if (parts.Length > 1)
            {
                var m = Regex.Match(parts[1], @"@(\w+)='([^']+)'");
                if (m.Success) attrValue = m.Groups[2].Value;
            }

            if (project.Properties.Any(p => p.Name.Equals(elementName, StringComparison.OrdinalIgnoreCase) &&
                (attrValue == null || p.Name.Equals(attrValue, StringComparison.OrdinalIgnoreCase))))
                return true;

            if (elementName.Equals("Target", StringComparison.OrdinalIgnoreCase) && !string.IsNullOrEmpty(attrValue))
            {
                if (project.Targets.Any(t => t.Name.Equals(attrValue, StringComparison.OrdinalIgnoreCase))) return true;
            }
            else if (!string.IsNullOrEmpty(attrValue))
            {
                if (project.Items.Any(i => i.ItemType.Equals(elementName, StringComparison.OrdinalIgnoreCase) &&
                    i.Include.Equals(attrValue, StringComparison.OrdinalIgnoreCase))) return true;
            }
            else
            {
                if (project.Items.Any(i => i.ItemType.Equals(elementName, StringComparison.OrdinalIgnoreCase))) return true;
            }
        }

        return false;
    }
}