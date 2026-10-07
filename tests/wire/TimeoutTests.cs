using System.Diagnostics;
using Shouldly;

namespace Grapevine.WireTests;

public class TimeoutTests
{
    // Each timeout is set to one second. The windows are wide because the image runs under
    // emulation on Apple Silicon, where a container can lose a second to the host.
    private static readonly TimeSpan Earliest = TimeSpan.FromMilliseconds(800);
    private static readonly TimeSpan Latest = TimeSpan.FromSeconds(6);

    [Fact(DisplayName = "A request head that stalls is answered 408 when the header timeout passes", Timeout = 120_000)]
    public async Task Stalled_head_is_answered_408()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken, ("server.headerTimeoutMs", 1000));
        using var client = await RawClient.ConnectAsync(server, cancellationToken);

        var started = Stopwatch.StartNew();
        await client.SendAsync("GET / HTTP/1.1\r\nHo", cancellationToken);
        var answer = await client.ReadResponseAsync(cancellationToken);

        answer.Status.ShouldBe(408);
        started.Elapsed.ShouldBeInRange(Earliest, Latest);
        (await client.ReadToEndAsync(cancellationToken)).ShouldBeEmpty();
    }

    [Fact(DisplayName = "A request body that stalls is answered 408 when the body timeout passes", Timeout = 120_000)]
    public async Task Stalled_body_is_answered_408()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken, ("server.bodyTimeoutMs", 1000));
        using var client = await RawClient.ConnectAsync(server, cancellationToken);

        var started = Stopwatch.StartNew();
        await client.SendAsync("POST /bytes HTTP/1.1\r\nHost: wire\r\nContent-Length: 10\r\n\r\nabc", cancellationToken);
        var answer = await client.ReadResponseAsync(cancellationToken);

        answer.Status.ShouldBe(408);
        started.Elapsed.ShouldBeInRange(Earliest, Latest);
        (await client.ReadToEndAsync(cancellationToken)).ShouldBeEmpty();
    }

    [Fact(DisplayName = "An idle connection is closed without a word when the keep-alive timeout passes", Timeout = 120_000)]
    public async Task Idle_connection_is_closed_quietly()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken, ("server.keepAliveTimeoutMs", 1000));
        using var client = await RawClient.ConnectAsync(server, cancellationToken);
        await client.SendAsync(RawClient.Get("/"), cancellationToken);
        (await client.ReadResponseAsync(cancellationToken)).Status.ShouldBe(200);

        var started = Stopwatch.StartNew();
        var afterwards = await client.ReadToEndAsync(cancellationToken);

        afterwards.ShouldBeEmpty();
        started.Elapsed.ShouldBeInRange(Earliest, Latest);
    }

    [Fact(DisplayName = "A connection that never sends anything is closed without an answer", Timeout = 120_000)]
    public async Task Silent_connection_is_closed_quietly()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken, ("server.headerTimeoutMs", 1000));
        using var client = await RawClient.ConnectAsync(server, cancellationToken);

        var started = Stopwatch.StartNew();
        var sent = await client.ReadToEndAsync(cancellationToken);

        sent.ShouldBeEmpty();
        started.Elapsed.ShouldBeInRange(Earliest, Latest);
    }
}
