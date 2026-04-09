namespace nh_patchproj.Utils;

public static class ArgParser
{
    private const string HelpFileName = "readme.md";
    
    // 🔹 ДОБАВЛЕНО: NoAct в record
    public record ParsedArgs(
        string? Command, 
        Dictionary<string, string[]> Options, 
        List<string> Remaining,
        bool NoAct = false);
    
    public static ParsedArgs Parse(string[] args)
    {
        var options = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        var remaining = new List<string>();
        string? currentKey = null;
        string? command = null;
        bool noAct = false;  // 🔹 ДОБАВЛЕНО

        for (int i = 0; i < args.Length; i++)
        {
            var arg = args[i];

            if (string.IsNullOrEmpty(arg)) continue;

            if (arg.StartsWith("--") || arg.StartsWith("-"))
            {
                var key = arg.TrimStart('-');
                
                // 🔹 ДОБАВЛЕНО: парсинг --xpath / -x
                if (key == "xpath" || key == "x")
                {
                    currentKey = key;
                    if (!options.ContainsKey(currentKey))
                        options[currentKey] = new List<string>();
                    if (i + 1 < args.Length && !args[i + 1].StartsWith("-"))
                        options[currentKey].Add(args[++i]);
                    continue;
                }
                
                // 🔹 ДОБАВЛЕНО: парсинг --no-act / -na
                if (key == "no-act" || key == "na")
                {
                    noAct = true;
                    continue;
                }
                
                bool isFlag = true;
                if (i + 1 < args.Length && !args[i + 1].StartsWith("-"))
                {
                    isFlag = false;
                }

                if (isFlag)
                {
                    if (!options.ContainsKey(key))
                        options[key] = new List<string>();
                    options[key].Add("true");
                }
                else
                {
                    currentKey = key;
                    if (!options.ContainsKey(currentKey))
                        options[currentKey] = new List<string>();
                    options[currentKey].Add(args[++i]);
                }
            }
            else
            {
                if (currentKey != null)
                {
                    options[currentKey].Add(arg);
                }
                else if (command == null)
                {
                    command = arg;
                }
                else
                {
                    remaining.Add(arg);
                }
            }
        }

        var optionsDict = options.ToDictionary(k => k.Key, v => v.Value.ToArray());
        return new ParsedArgs(command, optionsDict, remaining, noAct);  // 🔹 ПЕРЕДАТЬ noAct
    }

    public static string[] GetOption(ParsedArgs args, string key)
    {
        if (args.Options.ContainsKey(key))
            return args.Options[key];
        return Array.Empty<string>();
    }

    public static bool GetOptionBool(ParsedArgs args, string key)
    {
        if (args.Options.ContainsKey(key))
        {
            var v = args.Options[key].FirstOrDefault();
            return v != null && v != "false";
        }
        return false;
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