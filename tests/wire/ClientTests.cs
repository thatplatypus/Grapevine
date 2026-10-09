using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text;
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
        using var client = server.CreateClient(handler);

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

    [Fact(DisplayName = "A server that trusts one proxy takes the client's address from what that proxy forwarded, and one that trusts none takes it from the connection", Timeout = 120_000)]
    public async Task The_clients_address_is_forwarded_only_through_a_trusted_proxy()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var behind = await ServerFixture.StartAsync(cancellationToken, ("server.trustedProxies", 1));
        await using var exposed = await ServerFixture.StartAsync(cancellationToken);
        using var throughProxy = behind.CreateClient();
        using var direct = exposed.CreateClient();

        var believed = await WhoAsync(throughProxy, cancellationToken);
        var ignored = await WhoAsync(direct, cancellationToken);

        // The last entry is the one the proxy itself would have written. The one before it is
        // what a client put there.
        believed["client"].ShouldBe("203.0.113.7");
        IPAddress.TryParse(believed["peer"], out _).ShouldBeTrue(believed["peer"]);
        believed["peer"].ShouldNotBe("203.0.113.7");
        IPAddress.TryParse(ignored["peer"], out _).ShouldBeTrue(ignored["peer"]);
        ignored["client"].ShouldBe(ignored["peer"]);
    }

    [Fact(DisplayName = "A server that names its proxies by address believes the forwarded headers of a connection from one of them, up to the first address that is no proxy's, and of no other connection", Timeout = 120_000)]
    public async Task The_clients_address_is_forwarded_only_by_a_named_proxy()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        var ours = await ServerFixture.NetworkOfTheTestsAsync(cancellationToken);
        await using var named = await ServerFixture.StartAsync(cancellationToken, ("server.trustedProxies", $"{ours}, ::1"));
        await using var elsewhere = await ServerFixture.StartAsync(cancellationToken, ("server.trustedProxies", "203.0.113.0/24"));
        using var throughProxy = named.CreateClient();
        using var direct = elsewhere.CreateClient();

        // What the helper sends is "6.6.6.6, 203.0.113.7": the last entry is no proxy's, so it is the client.
        var believed = await WhoAsync(throughProxy, cancellationToken);
        var ignored = await WhoAsync(direct, cancellationToken);

        believed["client"].ShouldBe("203.0.113.7");
        believed["peer"].ShouldNotBe("203.0.113.7");
        IPAddress.TryParse(ignored["peer"], out _).ShouldBeTrue(ignored["peer"]);
        ignored["client"].ShouldBe(ignored["peer"]);
    }

    [Fact(DisplayName = "A server reads the forwarded headers that it was told its proxy writes, and no other: a host or a prefix that it was not told of is the client's own, and sends no browser anywhere", Timeout = 120_000)]
    public async Task Only_the_forwarded_headers_the_proxy_is_said_to_write_are_read()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var told = await ServerFixture.StartAsync(
            cancellationToken, ("server.trustedProxies", 1), ("server.forwardedHeaders", "for, proto, host, prefix"));
        await using var untold = await ServerFixture.StartAsync(cancellationToken, ("server.trustedProxies", 1));
        using var handler = new HttpClientHandler { AllowAutoRedirect = false };
        using var toTold = told.CreateClient();
        using var toUntold = untold.CreateClient(handler);
        (string Name, string Value)[] forwarded =
        [
            ("X-Forwarded-Proto", "https"),
            ("X-Forwarded-Host", "shop.example"),
            ("X-Forwarded-Prefix", "/account/delete-everything"),
        ];

        var all = await WhoAsync(toTold, cancellationToken, forwarded);
        var two = await WhoAsync(toUntold, cancellationToken, forwarded);
        using var directory = new HttpRequestMessage(HttpMethod.Get, "site/docs");
        directory.Headers.Add("X-Forwarded-Prefix", "/account/delete-everything");
        using var redirect = await toUntold.SendAsync(directory, cancellationToken);

        all["client"].ShouldBe("203.0.113.7");
        all["origin"].ShouldBe("https://shop.example");
        all["prefix"].ShouldBe("/account/delete-everything");
        // The address and the scheme are what every proxy writes, and are read without asking.
        two["client"].ShouldBe("203.0.113.7");
        two["origin"].ShouldStartWith("https://");
        two["origin"].ShouldNotContain("shop.example");
        two["prefix"].ShouldBeEmpty();
        redirect.StatusCode.ShouldBe(HttpStatusCode.MovedPermanently);
        redirect.Headers.Location.ShouldNotBeNull().OriginalString.ShouldBe("/site/docs/");
    }

    private static async Task<Dictionary<string, string>> WhoAsync(
        HttpClient client, CancellationToken cancellationToken, params (string Name, string Value)[] more)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "who");
        request.Headers.Add("X-Forwarded-For", "6.6.6.6, 203.0.113.7");
        foreach (var (name, value) in more)
        {
            request.Headers.Add(name, value);
        }

        using var response = await client.SendAsync(request, cancellationToken);
        response.StatusCode.ShouldBe(HttpStatusCode.OK);
        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        return body.Split('\n', StringSplitOptions.RemoveEmptyEntries)
            .Select(line => line.Split('=', 2))
            .ToDictionary(pair => pair[0], pair => pair[1]);
    }

    [Fact(DisplayName = "A client that asks more often than a limit allows is answered 429, with the seconds until it may come again", Timeout = 120_000)]
    public async Task A_client_that_asks_too_often_is_turned_away()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = server.CreateClient();
        // The diagnostic app counts by this header, three an hour for each value of it.
        var who = Guid.NewGuid().ToString("N");
        var statuses = new List<HttpStatusCode>();
        TimeSpan? wait = null;
        string? problem = null;

        for (var asked = 0; asked < 4; asked++)
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, "limited");
            request.Headers.Add("X-Client", who);
            using var response = await client.SendAsync(request, cancellationToken);
            statuses.Add(response.StatusCode);
            if (response.StatusCode == HttpStatusCode.TooManyRequests)
            {
                wait = response.Headers.RetryAfter?.Delta;
                problem = await response.Content.ReadAsStringAsync(cancellationToken);
            }
        }

        using var other = new HttpRequestMessage(HttpMethod.Get, "limited");
        other.Headers.Add("X-Client", Guid.NewGuid().ToString("N"));
        using var others = await client.SendAsync(other, cancellationToken);

        statuses.ShouldBe([HttpStatusCode.OK, HttpStatusCode.OK, HttpStatusCode.OK, HttpStatusCode.TooManyRequests]);
        var seconds = wait.ShouldNotBeNull().TotalSeconds;
        seconds.ShouldBeInRange(1, 3600);
        problem.ShouldNotBeNull().ShouldContain("\"status\":429");
        others.StatusCode.ShouldBe(HttpStatusCode.OK);
    }

    [Fact(DisplayName = "An answer that did not come from the test's server fails the request, and says what was answered", Timeout = 120_000)]
    public async Task An_answer_from_elsewhere_is_named()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = server.CreateClient();
        using var stranger = new TcpListener(IPAddress.Loopback, 0);
        stranger.Start();
        var port = ((IPEndPoint)stranger.LocalEndpoint).Port;
        var answering = AnswerOnceAsync(
            stranger, "HTTP/1.1 404 Not Found\r\nContent-Length: 4\r\nConnection: close\r\n\r\nnope", cancellationToken);

        var failure = await Should.ThrowAsync<InvalidOperationException>(
            () => client.GetAsync($"http://127.0.0.1:{port}/only/7", cancellationToken));
        await answering;
        var own = await client.GetStringAsync("only/7", cancellationToken);

        failure.Message.ShouldContain("not this test's server");
        failure.Message.ShouldContain("404");
        failure.Message.ShouldContain("nope");
        own.ShouldBe("/only/:id:int|id=7");
    }

    /// <summary>Takes one connection, reads a request's head from it, and says <paramref name="answer"/>.</summary>
    private static async Task AnswerOnceAsync(TcpListener listener, string answer, CancellationToken cancellationToken)
    {
        using var socket = await listener.AcceptSocketAsync(cancellationToken);
        var buffer = new byte[4096];
        var read = 0;
        while (read < buffer.Length && !Encoding.ASCII.GetString(buffer, 0, read).Contains("\r\n\r\n"))
        {
            var count = await socket.ReceiveAsync(buffer.AsMemory(read), cancellationToken);
            if (count == 0)
            {
                break;
            }

            read += count;
        }

        await socket.SendAsync(Encoding.ASCII.GetBytes(answer), cancellationToken);
    }

    [Fact(DisplayName = "A chunked upload through HttpClient comes back byte for byte", Timeout = 120_000)]
    public async Task Chunked_upload_round_trips()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = server.CreateClient();
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
        using var client = server.CreateClient();

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
