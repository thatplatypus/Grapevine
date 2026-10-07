using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using Shouldly;

namespace Grapevine.WireTests;

public class ClientTests
{
    [Fact(DisplayName = "HttpClient makes ten requests over one connection", Timeout = 120_000)]
    public async Task HttpClient_reuses_its_connection()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        var connections = 0;
        using var handler = new SocketsHttpHandler
        {
            ConnectCallback = async (context, token) =>
            {
                Interlocked.Increment(ref connections);
                var socket = new Socket(SocketType.Stream, ProtocolType.Tcp) { NoDelay = true };
                try
                {
                    await socket.ConnectAsync(context.DnsEndPoint, token);
                    return new NetworkStream(socket, ownsSocket: true);
                }
                catch
                {
                    socket.Dispose();
                    throw;
                }
            },
        };
        using var client = new HttpClient(handler) { BaseAddress = server.BaseAddress };

        for (var request = 0; request < 10; request++)
        {
            var body = await client.GetStringAsync($"inspect/{request}", cancellationToken);
            body.ShouldContain($"param.value={request}\n");
        }

        // A server that closed after each response would have been dialled ten times.
        connections.ShouldBe(1);
    }

    [Fact(DisplayName = "Two requests written at once on a raw socket are answered in order on it", Timeout = 120_000)]
    public async Task Raw_socket_reuses_its_connection()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = await RawClient.ConnectAsync(server, cancellationToken);

        await client.SendAsync(RawClient.Get("/inspect/first") + RawClient.Get("/inspect/second", close: true), cancellationToken);
        var first = await client.ReadResponseAsync(cancellationToken);
        var second = await client.ReadResponseAsync(cancellationToken);

        first.Text.ShouldContain("param.value=first\n");
        second.Text.ShouldContain("param.value=second\n");
        second.Header("Connection").ShouldBe("close");
        (await client.ReadToEndAsync(cancellationToken)).ShouldBeEmpty();
    }

    [Fact(DisplayName = "A chunked upload through HttpClient comes back byte for byte", Timeout = 120_000)]
    public async Task Chunked_upload_round_trips()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = new HttpClient { BaseAddress = server.BaseAddress };
        var payload = new byte[200_000];
        new Random(20261007).NextBytes(payload);
        using var request = new HttpRequestMessage(HttpMethod.Post, "bytes") { Content = new StreamContent(new MemoryStream(payload)) };
        request.Headers.TransferEncodingChunked = true;

        using var response = await client.SendAsync(request, cancellationToken);

        response.StatusCode.ShouldBe(HttpStatusCode.OK);
        (await response.Content.ReadAsByteArrayAsync(cancellationToken)).ShouldBe(payload);
    }

    [Fact(DisplayName = "A streamed download reaches HttpClient whole", Timeout = 120_000)]
    public async Task Streamed_download_reaches_HttpClient()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = new HttpClient { BaseAddress = server.BaseAddress };

        using var response = await client.GetAsync("stream/3", HttpCompletionOption.ResponseHeadersRead, cancellationToken);

        response.Headers.TransferEncodingChunked.ShouldBe(true);
        response.Content.Headers.ContentLength.ShouldBeNull();
        (await response.Content.ReadAsStringAsync(cancellationToken)).ShouldBe("chunk 1\nchunk 2\nchunk 3\n");
    }

    [Fact(DisplayName = "A streamed download arrives chunk by chunk, not all at the end", Timeout = 120_000)]
    public async Task Streamed_download_arrives_in_chunks()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = await RawClient.ConnectAsync(server, cancellationToken);

        var started = Stopwatch.StartNew();
        await client.SendAsync(RawClient.Get("/stream/4?delay=400"), cancellationToken);
        var head = await client.ReadHeadAsync(cancellationToken);
        var arrivals = new List<TimeSpan>();
        var chunks = new List<string>();
        while (await client.ReadChunkAsync(cancellationToken) is { } chunk)
        {
            arrivals.Add(started.Elapsed);
            chunks.Add(System.Text.Encoding.UTF8.GetString(chunk));
        }

        head.Header("Transfer-Encoding").ShouldBe("chunked");
        chunks.ShouldBe(["chunk 1\n", "chunk 2\n", "chunk 3\n", "chunk 4\n"]);
        // The handler waits 400 ms before each later chunk. A buffered response would deliver all four together.
        (arrivals[^1] - arrivals[0]).ShouldBeGreaterThan(TimeSpan.FromMilliseconds(900));
    }
}
