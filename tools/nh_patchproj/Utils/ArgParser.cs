namespace nh_patchproj.Utils;

public static class ArgParser
{
    private const string HelpFileName = "readme.md";

    public record ParsedArgs(string? Command, Dictionary<string, string[]> Options, List<string> Remaining);

    public static ParsedArgs Parse(string[] args)
    {
        var options = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        var remaining = new List<string>();
        string? currentKey = null;

        for (int i = 0; i < args.Length; i++)
        {
            var arg = args[i];
            if (string.IsNullOrEmpty(arg)) continue;

            // Ключ: --key или -k
            if (arg.StartsWith("--") || arg.StartsWith("-"))
            {
                var key = arg.TrimStart('-');
                
                // Проверка: это флаг без значения?
                bool isFlag = true;
                
                // Если есть следующий аргумент и он не начинается с "-"
                if (i + 1 < args.Length && !args[i + 1].StartsWith("-"))
                {
                    // Это ключ со значением
                    isFlag = false;
                }
                
                if (isFlag)
                {
                    // Флаг (без значения)
                    if (!options.ContainsKey(key))
                        options[key] = new List<string>();
                    options[key].Add("true");
                }
                else
                {
                    // Ключ со значением
                    currentKey = key;
                    if (!options.ContainsKey(currentKey))
                        options[currentKey] = new List<string>();
                    i++; // Переходим к значению
                    options[currentKey].Add(args[i]);
                }
            }
            // Значение для предыдущего ключа (если несколько значений)
            else if (currentKey != null)
            {
                options[currentKey].Add(arg);
            }
            // Остальное
            else
            {
                remaining.Add(arg);
            }
        }

        return new ParsedArgs(
            remaining.Count > 0 ? remaining[0] : null,
            options.ToDictionary(kv => kv.Key, kv => kv.Value.ToArray()),
            remaining.Skip(1).ToList()
        );
    }

    public static string? GetOption(ParsedArgs args, string key)
    {
        return args.Options.TryGetValue(key, out var v) && v.Length > 0 ? v[0] : null;
    }

    public static string[] GetOptionArray(ParsedArgs args, string key)
    {
        return args.Options.TryGetValue(key, out var v) ? v : Array.Empty<string>();
    }

    public static bool GetOptionBool(ParsedArgs args, string key)
    {
        var v = GetOption(args, key);
        return v != null && v != "false";
    }

    public static void PrintHelp()
    {
        try
        {
            var possiblePaths = new[]
            {
                Path.Combine(AppContext.BaseDirectory, "Resources", HelpFileName),
                Path.Combine(AppContext.BaseDirectory, HelpFileName),
                Path.Combine(Directory.GetCurrentDirectory(), "Resources", HelpFileName),
                Path.Combine(Directory.GetCurrentDirectory(), HelpFileName)
            };

            foreach (var path in possiblePaths)
            {
                if (File.Exists(path))
                {
                    Console.WriteLine(File.ReadAllText(path));
                    return;
                }
            }

            Console.WriteLine("nh_patchproj v1.0.0");
            Console.WriteLine("Файл справки readme.md не найден.");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Ошибка чтения справки: {ex.Message}");
        }
    }
}