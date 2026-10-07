using System.Diagnostics;
using Shouldly;

namespace Grapevine.WireTests;

public class ConcurrencyTests
{
    [Fact(DisplayName = "A silent client and a slow client do not delay another client", Timeout = 120_000)]
    public async Task Stalled_clients_do_not_delay_another()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var silent = await RawClient.ConnectAsync(server, cancellationToken);
        using var slow = await RawClient.ConnectAsync(server, cancellationToken);
        await slow.SendAsync("GET /inspect/slow HT", cancellationToken);

        using var prompt = await RawClient.ConnectAsync(server, cancellationToken);
        var started = Stopwatch.StartNew();
        await prompt.SendAsync(RawClient.Get("/inspect/prompt"), cancellationToken);
        var answer = await prompt.ReadResponseAsync(cancellationToken);

        answer.Status.ShouldBe(200);
        answer.Text.ShouldContain("param.value=prompt");
        started.Elapsed.ShouldBeLessThan(TimeSpan.FromSeconds(2));

        await slow.SendAsync("TP/1.1\r\nHost: wire\r\n\r\n", cancellationToken);
        (await slow.ReadResponseAsync(cancellationToken)).Text.ShouldContain("param.value=slow");
    }

    [Fact(DisplayName = "Twenty clients against four workers are all answered, four at a time", Timeout = 120_000)]
    public async Task More_clients_than_workers_wait_their_turn()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken, ("server.workers", 4));

        var started = Stopwatch.StartNew();
        var answers = await Task.WhenAll(Enumerable.Range(0, 20).Select(_ => GetOnceAsync(server, "/slow/300", cancellationToken)));

        answers.ShouldAllBe(answer => answer.Status == 200 && answer.Text == "slow");
        // Twenty requests of 300 ms are five rounds of four. Without the ceiling they would take one.
        started.Elapsed.ShouldBeGreaterThan(TimeSpan.FromMilliseconds(1200));
    }

    [Fact(DisplayName = "An idle connection gives way when every worker is busy and a client is waiting", Timeout = 120_000)]
    public async Task Idle_connections_are_shed_for_waiting_clients()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(
            cancellationToken,
            ("server.workers", 2),
            ("server.keepAliveTimeoutMs", 60_000));
        using var first = await RawClient.ConnectAsync(server, cancellationToken);
        using var second = await RawClient.ConnectAsync(server, cancellationToken);
        foreach (var idle in new[] { first, second })
        {
            await idle.SendAsync(RawClient.Get("/"), cancellationToken);
            (await idle.ReadResponseAsync(cancellationToken)).Status.ShouldBe(200);
        }

        using var waiting = await RawClient.ConnectAsync(server, cancellationToken);
        var started = Stopwatch.StartNew();
        await waiting.SendAsync(RawClient.Get("/inspect/waiting"), cancellationToken);
        var answer = await waiting.ReadResponseAsync(cancellationToken);

        answer.Text.ShouldContain("param.value=waiting");
        // Both workers were held by connections with a minute of keep-alive left.
        started.Elapsed.ShouldBeLessThan(TimeSpan.FromSeconds(5));
    }

    private static async Task<WireResponse> GetOnceAsync(ServerFixture server, string target, CancellationToken cancellationToken)
    {
        using var client = await RawClient.ConnectAsync(server, cancellationToken);
        await client.SendAsync(RawClient.Get(target, close: true), cancellationToken);
        return await client.ReadResponseAsync(cancellationToken);
    }
}
