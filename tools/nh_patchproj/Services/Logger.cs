using nh_patchproj.Models;

namespace nh_patchproj.Services;

public class Logger
{
    private const string DebugPrefix = "[DEBUG]";
    private const string WarningPrefix = "⚠️  ";
    private const string ErrorPrefix = "❌ ";
    private const string CheckMark = "[✓]";
    private const string EqualsMark = "[＝]";
    private const string SecondsSuffix = "с";

    private readonly bool _verbose;
    private readonly bool _quiet;

    public Logger(bool verbose, bool quiet)
    {
        _verbose = verbose;
        _quiet = quiet;
    }

    public void Info(string message) { if (!_quiet) Console.WriteLine(message); }
    public void Verbose(string message) { if (_verbose && !_quiet) Console.WriteLine($"{DebugPrefix} {message}"); }
    public void Warning(string message) { if (!_quiet) Console.WriteLine($"{WarningPrefix}{message}"); }
    public void Error(string message) { Console.WriteLine($"{ErrorPrefix}{message}"); }

    public void PrintSummary(OperationResult result, TimeSpan duration)
    {
        if (_quiet) return;
        Console.WriteLine();
        Console.WriteLine("📊 Итоги:");
        Console.WriteLine($"   Файлов обработано11: {result.FilesProcessed}");
        Console.WriteLine($"   Пакетов удалено: {result.PackagesRemoved}");
        Console.WriteLine($"   Тегов удалено: {result.TagsRemoved}");
        Console.WriteLine($"   Время выполнения: {duration.TotalSeconds:F1}{SecondsSuffix}");
        if (result.HasWarnings)
            Console.WriteLine($"   Предупреждений: {result.Warnings.Count}");
    }
}
