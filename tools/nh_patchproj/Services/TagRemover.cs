using Microsoft.Build.Construction;

namespace nh_patchproj.Services;

public class TagRemover
{
    private readonly Logger _logger;

    public TagRemover(Logger logger) { _logger = logger; }

    public int RemoveTags(ProjectRootElement project, string[] tagNames, string[] tagIncludes)
    {
        int removed = 0;

        foreach (var tagName in tagNames)
        {
            // Обработка обычных элементов (ItemGroup)
            var items = project.Items.Where(i => i.ItemType.Equals(tagName, StringComparison.OrdinalIgnoreCase)).ToList();
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
                    // ИСПРАВЛЕНИЕ: Удаляем через родителя
                    var parent = item.Parent;
                    if (parent != null)
                    {
                        parent.RemoveChild(item);
                        _logger.Info($"   [✓] {Path.GetFileName(project.FullPath)}: {tagName} ({item.Include})");
                        removed++;
                    }
                }
            }

            // Обработка Target по имени (Target — это прямой дочерний элемент Project)
            if (tagName.Equals("Target", StringComparison.OrdinalIgnoreCase) && tagIncludes.Length > 0)
            {
                var targets = project.Targets.ToList();
                foreach (var target in targets)
                {
                    if (tagIncludes.Any(ti => target.Name.Equals(ti, StringComparison.OrdinalIgnoreCase)))
                    {
                        project.RemoveChild(target);
                        _logger.Info($"   [✓] {Path.GetFileName(project.FullPath)}: Target Name=\"{target.Name}\"");
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
                    var execElements = target.Tasks.Where(t => t.Name.Equals("Exec", StringComparison.OrdinalIgnoreCase)).ToList();
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
                            var condition = !string.IsNullOrEmpty(exec.Condition) ? $" Condition=\"{exec.Condition}\"" : "";
                            _logger.Info($"   [✓] {Path.GetFileName(project.FullPath)}: Exec{condition}");
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
                        if (tagIncludes.Any(ti => pg.Condition.Contains(ti, StringComparison.OrdinalIgnoreCase)))
                        {
                            project.RemoveChild(pg);
                            _logger.Info($"   [✓] {Path.GetFileName(project.FullPath)}: PropertyGroup (Condition=\"{pg.Condition}\")");
                            removed++;
                        }
                    }
                }
            }
        }

        return removed;
    }
}