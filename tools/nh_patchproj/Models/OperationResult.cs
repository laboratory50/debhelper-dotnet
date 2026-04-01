namespace nh_patchproj.Models;

public class OperationResult
{
    public int FilesProcessed { get; set; }
    public int PackagesRemoved { get; set; }
    public int TagsRemoved { get; set; }
    public List<string> Errors { get; } = new();
    public List<string> Warnings { get; } = new();
    public List<string> Changes { get; } = new();

    public bool HasErrors => Errors.Count > 0;
    public bool HasWarnings => Warnings.Count > 0;
}
