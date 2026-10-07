using System.Globalization;
using System.Net.Sockets;
using System.Text;

namespace Grapevine.WireTests;

/// <summary>
/// A client that sends exactly the bytes it is given and reads responses off the socket itself.
/// It shows what an HTTP library hides: half-sent requests, pipelining, and the moment a
/// connection closes.
/// </summary>
public sealed class RawClient : IDisposable
{
    private static readonly byte[] HeadEnd = "\r\n\r\n"u8.ToArray();
    private static readonly byte[] LineEnd = "\r\n"u8.ToArray();

    private readonly NetworkStream _stream;
    private readonly byte[] _chunk = new byte[16 * 1024];
    private readonly List<byte> _received = [];

    private RawClient(NetworkStream stream) => _stream = stream;

    public static async Task<RawClient> ConnectAsync(ServerFixture server, CancellationToken cancellationToken)
    {
        var socket = new Socket(SocketType.Stream, ProtocolType.Tcp) { NoDelay = true };
        try
        {
            await socket.ConnectAsync(server.Host, server.Port, cancellationToken);
        }
        catch
        {
            socket.Dispose();
            throw;
        }

        return new RawClient(new NetworkStream(socket, ownsSocket: true));
    }

    /// <summary>A GET for <paramref name="target"/>, asking to keep the connection or to close it.</summary>
    public static string Get(string target, bool close = false) =>
        $"GET {target} HTTP/1.1\r\nHost: wire\r\n{(close ? "Connection: close\r\n" : "")}\r\n";

    public async Task SendAsync(string text, CancellationToken cancellationToken) =>
        await _stream.WriteAsync(Encoding.UTF8.GetBytes(text), cancellationToken);

    public async Task SendAsync(ReadOnlyMemory<byte> bytes, CancellationToken cancellationToken) =>
        await _stream.WriteAsync(bytes, cancellationToken);

    /// <summary>Reads the status line and headers of the next response. Its body is left unread.</summary>
    public async Task<WireResponse> ReadHeadAsync(CancellationToken cancellationToken)
    {
        var lines = Encoding.Latin1.GetString(await TakeUntilAsync(HeadEnd, cancellationToken)).Split("\r\n");
        var statusLine = lines[0].Split(' ', 3);
        var headers = lines
            .Skip(1)
            .Select(line => line.Split(':', 2))
            .Select(parts => new KeyValuePair<string, string>(parts[0], parts[1].Trim()))
            .ToList();
        return new WireResponse(statusLine[0], int.Parse(statusLine[1], CultureInfo.InvariantCulture), headers, []);
    }

    /// <summary>Reads the next chunk of a chunked body, or null once the last chunk and the trailers have been read.</summary>
    public async Task<byte[]?> ReadChunkAsync(CancellationToken cancellationToken)
    {
        var sizeLine = Encoding.Latin1.GetString(await TakeUntilAsync(LineEnd, cancellationToken));
        var size = int.Parse(sizeLine.Split(';', 2)[0].Trim(), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        if (size == 0)
        {
            while ((await TakeUntilAsync(LineEnd, cancellationToken)).Length > 0)
            {
            }

            return null;
        }

        var data = await TakeAsync(size, cancellationToken);
        await TakeAsync(LineEnd.Length, cancellationToken);
        return data;
    }

    /// <summary>Reads one whole response, framed the way its own headers say.</summary>
    public async Task<WireResponse> ReadResponseAsync(CancellationToken cancellationToken)
    {
        var head = await ReadHeadAsync(cancellationToken);
        if (head.Status is 204 or 304 or < 200)
        {
            return head;
        }

        if (head.Header("Transfer-Encoding") is { } coding && coding.Contains("chunked", StringComparison.OrdinalIgnoreCase))
        {
            var body = new List<byte>();
            while (await ReadChunkAsync(cancellationToken) is { } chunk)
            {
                body.AddRange(chunk);
            }

            return head with { Body = [.. body] };
        }

        if (head.Header("Content-Length") is { } length)
        {
            return head with { Body = await TakeAsync(int.Parse(length, CultureInfo.InvariantCulture), cancellationToken) };
        }

        return head with { Body = await ReadToEndAsync(cancellationToken) };
    }

    /// <summary>Reads until the server closes the connection and returns whatever it sent first.</summary>
    public async Task<byte[]> ReadToEndAsync(CancellationToken cancellationToken)
    {
        while (await ReceiveAsync(cancellationToken))
        {
        }

        byte[] rest = [.. _received];
        _received.Clear();
        return rest;
    }

    public void Dispose() => _stream.Dispose();

    private async Task<bool> ReceiveAsync(CancellationToken cancellationToken)
    {
        var read = await _stream.ReadAsync(_chunk, cancellationToken);
        if (read == 0)
        {
            return false;
        }

        _received.AddRange(_chunk.AsSpan(0, read));
        return true;
    }

    private async Task<byte[]> TakeUntilAsync(byte[] terminator, CancellationToken cancellationToken)
    {
        var from = 0;
        while (true)
        {
            var at = IndexOf(terminator, from);
            if (at >= 0)
            {
                var taken = _received.GetRange(0, at).ToArray();
                _received.RemoveRange(0, at + terminator.Length);
                return taken;
            }

            from = Math.Max(0, _received.Count - terminator.Length + 1);
            if (!await ReceiveAsync(cancellationToken))
            {
                throw new EndOfStreamException("The server closed the connection before the expected bytes arrived.");
            }
        }
    }

    private async Task<byte[]> TakeAsync(int count, CancellationToken cancellationToken)
    {
        while (_received.Count < count)
        {
            if (!await ReceiveAsync(cancellationToken))
            {
                throw new EndOfStreamException($"The server closed the connection {count - _received.Count} bytes short.");
            }
        }

        var taken = _received.GetRange(0, count).ToArray();
        _received.RemoveRange(0, count);
        return taken;
    }

    private int IndexOf(byte[] needle, int from)
    {
        for (var start = from; start <= _received.Count - needle.Length; start++)
        {
            var matches = true;
            for (var offset = 0; matches && offset < needle.Length; offset++)
            {
                matches = _received[start + offset] == needle[offset];
            }

            if (matches)
            {
                return start;
            }
        }

        return -1;
    }
}
