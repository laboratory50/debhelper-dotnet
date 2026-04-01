using System.Xml;

namespace nh_patchproj.Utils;

public static class XmlValidator
{
    public static bool IsValid(string filePath)
    {
        try
        {
            var settings = new XmlReaderSettings
            {
                DtdProcessing = DtdProcessing.Prohibit,
                XmlResolver = null
            };
            using var reader = XmlReader.Create(filePath, settings);
            while (reader.Read()) { }
            return true;
        }
        catch
        {
            return false;
        }
    }
}
