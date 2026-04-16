using Microsoft.Build.Construction;

namespace nh_patchproj.Services;

public static class AtomicFileWriter
{
    /// <summary>
    /// Атомарно сохраняет проект: копирует во временный файл с случайным расширением,
    /// применяет изменения, затем переименовывает поверх оригинала.
    /// </summary>
    public static void Save(ProjectRootElement project, string originalPath)
    {
        // Генерируем случайное расширение без точки (например, XFDSG8K2L)
        var tempSuffix = Path.GetRandomFileName().Replace(".", string.Empty);
        var tempPath = $"{originalPath}.{tempSuffix}";

        try
        {
            // 1. Копируем оригинал для сохранения прав доступа, атрибутов и ACL
            File.Copy(originalPath, tempPath, overwrite: true);

            // 2. Модифицируем временный файл
            project.Save(tempPath);

            // 3. Атомарно заменяем оригинал (переименование в рамках одного тома)
            File.Move(tempPath, originalPath, overwrite: true);
        }
        catch
        {
            // При любой ошибке удаляем временный файл, чтобы не оставлять мусор
            if (File.Exists(tempPath))
                File.Delete(tempPath);
            throw;
        }
    }
}