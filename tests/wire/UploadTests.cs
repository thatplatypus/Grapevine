using System.Net.Sockets;
using Shouldly;

namespace Grapevine.WireTests;

public class UploadTests
{
    [Fact(DisplayName = "A client still uploading when it is answered 413 can read the whole response", Timeout = 120_000)]
    public async Task Refused_upload_still_delivers_its_answer()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken, ("limits.bodyBytes", 1024));
        using var client = await RawClient.ConnectAsync(server, cancellationToken);
        const int announced = 64 * 1024 * 1024;

        await client.SendAsync($"POST /bytes HTTP/1.1\r\nHost: wire\r\nContent-Length: {announced}\r\n\r\n", cancellationToken);
        // The upload carries on while the answer is read. A server that closed at once, with
        // these bytes unread, would make the kernel reset the connection and destroy its own answer.
        var upload = UploadUntilRefusedAsync(client, announced, cancellationToken);
        var answer = await client.ReadResponseAsync(cancellationToken);
        var uploaded = await upload;

        answer.Status.ShouldBe(413);
        answer.Header("Connection").ShouldBe("close");
        answer.Header("Content-Type").ShouldBe("application/problem+json; charset=utf-8");
        answer.Text.ShouldContain("\"status\":413");
        // The server reads on for a moment so its answer survives, but not for as long as the client likes.
        uploaded.ShouldBeLessThan(announced);
    }

    /// <summary>
    /// Writes body bytes at a steady pace until they have all gone or the server stops taking them.
    /// Returns how many went. The pace makes the whole body take ten seconds, far longer than the
    /// server keeps reading after it has refused.
    /// </summary>
    private static async Task<int> UploadUntilRefusedAsync(RawClient client, int total, CancellationToken cancellationToken)
    {
        var block = new byte[64 * 1024];
        var sent = 0;
        try
        {
            while (sent < total)
            {
                await client.SendAsync(block, cancellationToken);
                sent += block.Length;
                await Task.Delay(TimeSpan.FromMilliseconds(10), cancellationToken);
            }
        }
        catch (IOException exception) when (exception.InnerException is SocketException)
        {
            // The server has closed its end, which is what a refusal looks like from here.
        }

        return sent;
    }
}
