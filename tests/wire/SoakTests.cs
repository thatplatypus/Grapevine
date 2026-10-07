using System.Text.RegularExpressions;
using Shouldly;

namespace Grapevine.WireTests;

public partial class SoakTests
{
    [GeneratedRegex(@"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z DEBUG refused: 501 method BREW is not implemented$")]
    private static partial Regex RefusalLine();

    private const int Clients = 64;
    private const int RequestsEach = 50;

    [Fact(DisplayName = "Sixty-four keep-alive clients making fifty requests each all get their own answers", Timeout = 300_000)]
    public async Task Many_keep_alive_clients_are_all_answered()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);

        var correct = await Task.WhenAll(Enumerable.Range(0, Clients).Select(client => ConverseAsync(server, client, cancellationToken)));

        correct.Sum().ShouldBe(Clients * RequestsEach);
    }

    [Fact(DisplayName = "Log lines written by many workers at once stay whole", Timeout = 300_000)]
    public async Task Concurrent_log_lines_do_not_interleave()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        // Unknown methods are refused by the server core, which logs each refusal at debug: 3,200 lines from 64 threads.
        await using var server = await ServerFixture.StartAsync(cancellationToken, ("log.level", "debug"));

        await Task.WhenAll(Enumerable.Range(0, Clients).Select(client => GetRefusedAsync(server, cancellationToken)));
        var refusals = (await server.OutputLinesAsync(cancellationToken)).Where(line => line.Contains("refused", StringComparison.Ordinal)).ToList();

        refusals.Count.ShouldBe(Clients * RequestsEach);
        refusals.ShouldAllBe(line => RefusalLine().IsMatch(line));
    }

    /// <summary>Opens a connection for each request of one client and has each refused, which the server logs.</summary>
    private static async Task GetRefusedAsync(ServerFixture server, CancellationToken cancellationToken)
    {
        for (var request = 0; request < RequestsEach; request++)
        {
            using var connection = await RawClient.ConnectAsync(server, cancellationToken);
            await connection.SendAsync("BREW / HTTP/1.1\r\nHost: wire\r\n\r\n", cancellationToken);
            (await connection.ReadResponseAsync(cancellationToken)).Status.ShouldBe(501);
        }
    }

    /// <summary>Makes every request of one client on one connection and returns how many answers were its own.</summary>
    private static async Task<int> ConverseAsync(ServerFixture server, int client, CancellationToken cancellationToken)
    {
        using var connection = await RawClient.ConnectAsync(server, cancellationToken);
        var correct = 0;
        for (var request = 0; request < RequestsEach; request++)
        {
            await connection.SendAsync(RawClient.Get($"/inspect/{client}-{request}"), cancellationToken);
            var answer = await connection.ReadResponseAsync(cancellationToken);
            if (answer.Status == 200 && answer.Text.Contains($"param.value={client}-{request}\n", StringComparison.Ordinal))
            {
                correct++;
            }
        }

        return correct;
    }
}
