using System.Reflection;

namespace nh_patchproj.Utils;

public static class VersionProvider
{
    /// <summary>
    /// Возвращает чистую версию без build metadata (например: "1.1.0+abc123" → "1.1.0")
    /// </summary>
    public static string Get()
    {
        var asm = Assembly.GetExecutingAssembly();
        var attr = asm.GetCustomAttribute<AssemblyInformationalVersionAttribute>();
        var raw = attr?.InformationalVersion ?? asm.GetName().Version?.ToString() ?? "1.0.0";
        
        // 🔹 Обрезаем build metadata: всё после '+' (стандарт SemVer 2.0)
        var plusIndex = raw.IndexOf('+');
        return plusIndex >= 0 ? raw.Substring(0, plusIndex) : raw;
    }
}