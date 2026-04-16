using Microsoft.Build.Locator;
using nh_patchproj.Commands;
using nh_patchproj.Utils;

namespace nh_patchproj;

public class Program
{
    public static int Main(string[] args)
    {
        // 🔹 ГЛОБАЛЬНАЯ ПРОВЕРКА ВЕРСИИ (до MSBuildLocator)
        bool showVersion = Array.Exists(args, a =>
            a.Equals("--version", StringComparison.OrdinalIgnoreCase) ||
            a.Equals("-ver", StringComparison.OrdinalIgnoreCase));

        if (showVersion)
        {
            Console.WriteLine(VersionProvider.Get());
            return ExitCodes.Success;
        }

        MSBuildLocator.RegisterDefaults();
        var parsed = ArgParser.Parse(args);
        var command = parsed.Command?.ToLowerInvariant();

        if (command == "clean")
            return CleanCommand.Execute(parsed);
        else if (command == "restore")
            return RestoreCommand.Execute(parsed);
        else if (command == "help" || command == "--help" || command == "-h" || command == null)
        {
            ArgParser.PrintHelp();
            return ExitCodes.Success;
        }
        else
        {
            Console.WriteLine($"Unknown command: {command}");
            ArgParser.PrintHelp();
            return ExitCodes.CriticalError;
        }
    }
}