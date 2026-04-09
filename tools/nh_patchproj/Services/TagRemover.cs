using Microsoft.Build.Construction;
using nh_patchproj.Services;

namespace nh_patchproj.Services;

public class TagRemover
{
    private readonly Logger _logger;

    public TagRemover(Logger logger) { _logger = logger; }

    public int RemoveTags(ProjectRootElement project, string[] tagNames, string[] tagIncludes, string[] xpaths)
    {
        int removed = 0;

        // 🔹 Обработка XPath (приоритет)
        if (xpaths.Length > 0)
        {
            foreach (var xpath in xpaths)
            {
                removed += RemoveByXPath(project, xpath);
            }
        }

        foreach (var tagName in tagNames)
        {
            // Обработка обычных элементов (ItemGroup)
            var items = project.Items.Where(i => 
                i.ItemType.Equals(tagName, StringComparison.OrdinalIgnoreCase)
            ).ToList();

            foreach (var item in items)
            {
                bool shouldRemove = true;

                if (tagIncludes.Length > 0)
                {
                    shouldRemove = tagIncludes.Any(ti =>
                        item.Include.Equals(ti, StringComparison.OrdinalIgnoreCase) ||
                        item.Include.Contains(ti, StringComparison.OrdinalIgnoreCase));
                }

                if (shouldRemove)
                {
                    var parent = item.Parent;
                    if (parent != null)
                    {
                        parent.RemoveChild(item);
                        _logger.Info($"   {Path.GetFileName(project.FullPath)}: {tagName} ({item.Include})");
                        removed++;
                    }
                }
            }

            // Обработка Target по имени
            if (tagName.Equals("Target", StringComparison.OrdinalIgnoreCase) && tagIncludes.Length > 0)
            {
                var targets = project.Targets.ToList();
                foreach (var target in targets)
                {
                    if (tagIncludes.Any(ti => target.Name.Equals(ti, StringComparison.OrdinalIgnoreCase)))
                    {
                        project.RemoveChild(target);
                        _logger.Info($"   {Path.GetFileName(project.FullPath)}: Target Name=\"{target.Name}\"");
                        removed++;
                    }
                }
            }

            // Обработка Exec внутри Target
            if (tagName.Equals("Exec", StringComparison.OrdinalIgnoreCase))
            {
                var targets = project.Targets.ToList();
                foreach (var target in targets)
                {
                    var execElements = target.Tasks.Where(t => 
                        t.Name.Equals("Exec", StringComparison.OrdinalIgnoreCase)
                    ).ToList();

                    foreach (var exec in execElements)
                    {
                        bool shouldRemove = false;

                        if (tagIncludes.Length > 0)
                        {
                            if (!string.IsNullOrEmpty(exec.Condition))
                            {
                                shouldRemove = tagIncludes.Any(ti =>
                                    exec.Condition.Contains(ti, StringComparison.OrdinalIgnoreCase));
                            }

                            if (!shouldRemove)
                            {
                                var command = exec.GetParameter("Command");
                                if (!string.IsNullOrEmpty(command))
                                {
                                    shouldRemove = tagIncludes.Any(ti =>
                                        command.Contains(ti, StringComparison.OrdinalIgnoreCase));
                                }
                            }
                        }
                        else
                        {
                            shouldRemove = true;
                        }

                        if (shouldRemove)
                        {
                            target.RemoveChild(exec);
                            var condition = !string.IsNullOrEmpty(exec.Condition) 
                                ? $" Condition=\"{exec.Condition}\"" 
                                : "";
                            _logger.Info($"   {Path.GetFileName(project.FullPath)}: Exec{condition}");
                            removed++;
                        }
                    }
                }
            }

            // Обработка PropertyGroup по Condition
            if (tagName.Equals("PropertyGroup", StringComparison.OrdinalIgnoreCase))
            {
                var propGroups = project.PropertyGroups.ToList();
                foreach (var pg in propGroups)
                {
                    if (tagIncludes.Length > 0)
                    {
                        if (tagIncludes.Any(ti => 
                            pg.Condition.Contains(ti, StringComparison.OrdinalIgnoreCase)))
                        {
                            project.RemoveChild(pg);
                            _logger.Info($"   {Path.GetFileName(project.FullPath)}: PropertyGroup (Condition=\"{pg.Condition}\")");
                            removed++;
                        }
                    }
                }
            }
        }

        _logger.Verbose($"Tags removed: {removed}");
        return removed;
    }

    private int RemoveByXPath(ProjectRootElement project, string xpath)
    {
        int removed = 0;

        try
        {
            // Поиск элементов по XPath через Microsoft.Build
            var elementName = xpath.TrimStart('/').TrimStart('/').Split('[')[0];
            var includeMatch = System.Text.RegularExpressions.Regex.Match(xpath, @"\[@Include='([^']+)'\]");
            var nameMatch = System.Text.RegularExpressions.Regex.Match(xpath, @"\[@Name='([^']+)'\]");

            string includeValue = includeMatch.Success ? includeMatch.Groups[1].Value : null;
            string nameValue = nameMatch.Success ? nameMatch.Groups[1].Value : null;

            // Поиск по имени элемента
            var items = project.Items.Where(i => 
                i.ItemType.Equals(elementName, StringComparison.OrdinalIgnoreCase)
            ).ToList();

            foreach (var item in items)
            {
                bool match = true;

                if (!string.IsNullOrEmpty(includeValue) && 
                    !item.Include.Equals(includeValue, StringComparison.OrdinalIgnoreCase))
                    match = false;

                if (match)
                {
                    var parent = item.Parent;
                    if (parent != null)
                    {
                        parent.RemoveChild(item);
                        _logger.Info($"   {Path.GetFileName(project.FullPath)}: XPath matched {elementName} ({item.Include})");
                        removed++;
                    }
                }
            }

            // Для Target по имени
            if (elementName.Equals("Target", StringComparison.OrdinalIgnoreCase) && !string.IsNullOrEmpty(nameValue))
            {
                var targets = project.Targets.ToList();
                foreach (var target in targets)
                {
                    if (target.Name.Equals(nameValue, StringComparison.OrdinalIgnoreCase))
                    {
                        project.RemoveChild(target);
                        _logger.Info($"   {Path.GetFileName(project.FullPath)}: XPath matched Target \"{nameValue}\"");
                        removed++;
                    }
                }
            }
        }
        catch (Exception ex)
        {
            _logger.Error($"XPath error '{xpath}': {ex.Message}");
        }

        return removed;
    }
}