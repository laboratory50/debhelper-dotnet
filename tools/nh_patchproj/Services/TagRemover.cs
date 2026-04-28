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
            var properties = project.Properties
                .Where(p => p.Name.Equals(tagName, StringComparison.OrdinalIgnoreCase))
                .ToList();

            foreach (var prop in properties)
            {
                bool shouldRemove = true;
                if (tagIncludes.Length > 0)
                {
                    shouldRemove = tagIncludes.Any(ti =>
                        prop.Value.Contains(ti, StringComparison.OrdinalIgnoreCase));
                }

                if (shouldRemove)
                {
                    prop.Parent?.RemoveChild(prop);
                    _logger.Info($"   {Path.GetFileName(project.FullPath)}: Property '{prop.Name}' removed");
                    removed++;
                }
            }

            // 2. Обработка обычных элементов (ItemGroup)
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

            // 3. Обработка Target по имени
            if (tagName.Equals("Target", StringComparison.OrdinalIgnoreCase) && tagIncludes.Length > 0)
            {
                var targets = project.Targets.ToList();
                foreach (var target in targets)
                {
                    if (tagIncludes.Any(ti => target.Name.Equals(ti, StringComparison.OrdinalIgnoreCase)))
                    {
                        target.Parent?.RemoveChild(target);
                        _logger.Info($"   {Path.GetFileName(project.FullPath)}: Target Name=\"{target.Name}\"");
                        removed++;
                    }
                }
            }

            // 4. Обработка Exec внутри Target
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

            // 5. Обработка PropertyGroup по Condition
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
                            pg.Parent?.RemoveChild(pg);
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
            // Упрощённый парсинг XPath: //ElementName[@Attr='Value']
            var cleanXpath = xpath.TrimStart('/');
            var parts = cleanXpath.Split(new[] { '[' }, 2);
            var elementName = parts[0].Trim('/');

            string attrName = null, attrValue = null;
            if (parts.Length > 1)
            {
                var attrMatch = System.Text.RegularExpressions.Regex.Match(parts[1], @"@(\w+)='([^']+)'");
                if (attrMatch.Success)
                {
                    attrName = attrMatch.Groups[1].Value;
                    attrValue = attrMatch.Groups[2].Value;
                }
            }

            if (string.IsNullOrEmpty(attrName) || attrName == "Name")
            {
                var props = project.Properties
                    .Where(p => p.Name.Equals(elementName, StringComparison.OrdinalIgnoreCase))
                    .Where(p => attrValue == null || p.Name.Equals(attrValue, StringComparison.OrdinalIgnoreCase))
                    .ToList();

                foreach (var prop in props)
                {
                    prop.Parent?.RemoveChild(prop);
                    _logger.Info($"   {Path.GetFileName(project.FullPath)}: XPath removed Property '{prop.Name}'");
                    removed++;
                }
            }

            var items = project.Items
                .Where(i => i.ItemType.Equals(elementName, StringComparison.OrdinalIgnoreCase))
                .Where(i => attrValue == null ||
                           (attrName == "Include" && i.Include.Equals(attrValue, StringComparison.OrdinalIgnoreCase)) ||
                           (attrName == "Condition" && i.Condition.Contains(attrValue, StringComparison.OrdinalIgnoreCase)))
                .ToList();

            foreach (var item in items)
            {
                item.Parent?.RemoveChild(item);
                _logger.Info($"   {Path.GetFileName(project.FullPath)}: XPath removed Item '{item.ItemType}' Include='{item.Include}'");
                removed++;
            }

            // 🔹 3. Поиск Target по имени
            if (elementName.Equals("Target", StringComparison.OrdinalIgnoreCase) && !string.IsNullOrEmpty(attrValue))
            {
                var targets = project.Targets.ToList();
                foreach (var target in targets)
                {
                    if (target.Name.Equals(attrValue, StringComparison.OrdinalIgnoreCase))
                    {
                        target.Parent?.RemoveChild(target);
                        _logger.Info($"   {Path.GetFileName(project.FullPath)}: XPath removed Target '{attrValue}'");
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