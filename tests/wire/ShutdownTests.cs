using System.Diagnostics;
using System.Text;
using Shouldly;

namespace Grapevine.WireTests;

public class ShutdownTests
{
    [Fact(DisplayName = "SIGTERM lets the request in hand finish, closes idle connections, and exits 0", Timeout = 120_000)]
    public async Task Sigterm_finishes_work_in_hand()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var idle = await RawClient.ConnectAsync(server, cancellationToken);
        await idle.SendAsync(RawClient.Get("/"), cancellationToken);
        (await idle.ReadResponseAsync(cancellationToken)).Status.ShouldBe(200);
        using var busy = await RawClient.ConnectAsync(server, cancellationToken);
        await StartStreamAsync(busy, "/stream/2?delay=1500", cancellationToken);

        var stopping = server.StopAsync(cancellationToken);
        var rest = ReadRestOfStreamAsync(busy, cancellationToken);
        var idleTail = idle.ReadToEndAsync(cancellationToken);
        await Task.WhenAll(stopping, rest, idleTail);

        (await rest).ShouldBe(["chunk 2\n"]);
        (await idleTail).ShouldBeEmpty();
        (await stopping).ShouldBe(0);
    }

    [Fact(DisplayName = "SIGTERM with only an idle connection open exits 0 without using the grace period", Timeout = 120_000)]
    public async Task Sigterm_with_nothing_in_hand_stops_at_once()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken, ("server.shutdownGraceMs", 1000));
        using var idle = await RawClient.ConnectAsync(server, cancellationToken);
        await idle.SendAsync(RawClient.Get("/"), cancellationToken);
        (await idle.ReadResponseAsync(cancellationToken)).Status.ShouldBe(200);

        var exitCode = await server.StopAsync(cancellationToken);

        exitCode.ShouldBe(0);
    }

    [Fact(DisplayName = "SIGTERM with a handler that outlasts the grace period exits 1", Timeout = 120_000)]
    public async Task Sigterm_gives_up_after_the_grace_period()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken, ("server.shutdownGraceMs", 200));
        using var busy = await RawClient.ConnectAsync(server, cancellationToken);
        await StartStreamAsync(busy, "/stream/2?delay=3000", cancellationToken);

        var exitCode = await server.StopAsync(cancellationToken);

        exitCode.ShouldBe(1);
    }

    [Fact(DisplayName = "A second SIGTERM ends the server at once with exit 1", Timeout = 120_000)]
    public async Task Second_sigterm_exits_at_once()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var busy = await RawClient.ConnectAsync(server, cancellationToken);
        await StartStreamAsync(busy, "/stream/2?delay=5000", cancellationToken);

        var started = Stopwatch.StartNew();
        await server.SignalAsync("TERM", cancellationToken);
        await server.SignalAsync("TERM", cancellationToken);
        var exitCode = await server.WaitForExitAsync(cancellationToken);

        exitCode.ShouldBe(1);
        // The handler had five seconds to go and the grace period ten.
        started.Elapsed.ShouldBeLessThan(TimeSpan.FromSeconds(3));
    }

    /// <summary>
    /// Asks for a stream and reads its head and first chunk. Once that chunk is here the handler
    /// is known to be running, which a fixed wait could only hope for.
    /// </summary>
    private static async Task StartStreamAsync(RawClient client, string target, CancellationToken cancellationToken)
    {
        await client.SendAsync(RawClient.Get(target), cancellationToken);
        (await client.ReadHeadAsync(cancellationToken)).Status.ShouldBe(200);
        (await client.ReadChunkAsync(cancellationToken)).ShouldNotBeNull();
    }

    private static async Task<List<string>> ReadRestOfStreamAsync(RawClient client, CancellationToken cancellationToken)
    {
        var chunks = new List<string>();
        while (await client.ReadChunkAsync(cancellationToken) is { } chunk)
        {
            chunks.Add(Encoding.UTF8.GetString(chunk));
        }

        return chunks;
    }
}
