using System.Text;

namespace Grapevine.WireTests;

/// <summary>One response as it came off the socket.</summary>
public sealed record WireResponse(string Version, int Status, IReadOnlyList<KeyValuePair<string, string>> Headers, byte[] Body)
{
    public string Text => Encoding.UTF8.GetString(Body);

    /// <summary>The first value of a header, by case-insensitive name, or null.</summary>
    public string? Header(string name) => Headers
        .Where(header => string.Equals(header.Key, name, StringComparison.OrdinalIgnoreCase))
        .Select(header => header.Value)
        .FirstOrDefault();
}
