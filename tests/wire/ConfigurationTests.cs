using Shouldly;

namespace Grapevine.WireTests;

public class ConfigurationTests
{
    [Fact(DisplayName = "A setting from the environment that is out of range stops the server from starting, with exit code 1 and the reason", Timeout = 120_000)]
    public async Task A_bad_variable_stops_the_server_from_starting()
    {
        var cancellationToken = TestContext.Current.CancellationToken;

        var (exitCode, output) = await ServerFixture.RunToExitAsync(cancellationToken, ("GRAPEVINE_SERVER_WORKERS", "0"));

        exitCode.ShouldBe(1);
        output.ShouldContain(line => line.Contains("server.workers must be between 1 and 1024, got 0 (from GRAPEVINE_SERVER_WORKERS)"));
        output.ShouldNotContain(line => line.Contains("Grapevine listening"));
    }
}
