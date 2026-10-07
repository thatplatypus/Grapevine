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
        await busy.SendAsync(RawClient.Get("/slow/1500"), cancellationToken);
        await Task.Delay(TimeSpan.FromMilliseconds(300), cancellationToken);

        var stopping = server.StopAsync(cancellationToken);
        var answer = await busy.ReadResponseAsync(cancellationToken);
        var idleTail = await idle.ReadToEndAsync(cancellationToken);
        var exitCode = await stopping;

        answer.Status.ShouldBe(200);
        answer.Text.ShouldBe("slow");
        answer.Header("Connection").ShouldBe("close");
        idleTail.ShouldBeEmpty();
        exitCode.ShouldBe(0);
    }

    [Fact(DisplayName = "SIGTERM with a handler that outlasts the grace period exits 1", Timeout = 120_000)]
    public async Task Sigterm_gives_up_after_the_grace_period()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken, ("server.shutdownGraceMs", 200));
        using var busy = await RawClient.ConnectAsync(server, cancellationToken);
        await busy.SendAsync(RawClient.Get("/slow/3000"), cancellationToken);
        await Task.Delay(TimeSpan.FromMilliseconds(300), cancellationToken);

        var exitCode = await server.StopAsync(cancellationToken);

        exitCode.ShouldBe(1);
    }
}
