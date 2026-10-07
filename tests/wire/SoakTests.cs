using Shouldly;

namespace Grapevine.WireTests;

public class SoakTests
{
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
