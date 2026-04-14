namespace nh_patchproj.Services;

public class Logger
{
    private readonly bool _verbose;
    private readonly bool _quiet;
    
    // Сделать public
    public const string SecondsSuffix = "s";

    public Logger(bool verbose, bool quiet)
    {
        _verbose = verbose;
        _quiet = quiet;
    }

    public void Info(string message)
    {
        if (!_quiet)
            Console.WriteLine(message);
    }

    public void Warning(string message)
    {
        if (!_quiet)
            Console.WriteLine($"[WARNING] {message}");
    }

    public void Error(string message)
    {
        Console.Error.WriteLine($"[ERROR] {message}");
    }

    public void Verbose(string message)
    {
        if (_verbose && !_quiet)
            Console.WriteLine($"[VERBOSE] {message}");
    }
}