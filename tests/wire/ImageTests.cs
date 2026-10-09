using Shouldly;

namespace Grapevine.WireTests;

/// <summary>
/// The image run by its own command, as <c>docker run grapevine</c> runs it. Every other test names
/// the program it starts, so these alone hold what that command decides: whether the sample is
/// being tried out, where it takes the README's password, or is a deployment, where it does not.
/// </summary>
public class ImageTests
{
    private const string Listening = "Grapevine listening";
    private const string NoKey = " ERROR cannot start: auth.tokenKey is not set. ";
    private const string ReadmePassword = " ERROR cannot start: todo.adminPassword is the one in the sample's README, ";

    [Fact(DisplayName = "Given nothing, the image tries the sample out: it starts as Development, says so, and warns of its key and its password. The server is the container's first process", Timeout = 120_000)]
    public async Task Given_nothing_the_image_tries_the_sample_out()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartImageAsync(cancellationToken);

        var output = await server.OutputWithAsync(line => line.Contains(Listening), cancellationToken);

        output.ShouldContain(line => line.Contains(Listening) && line.Contains(" environment=Development "));
        output.ShouldContain(line => line.Contains(" WARN  auth.tokenKey is not set: tokens are signed with a key made for this run"));
        output.ShouldContain(line => line.Contains(" WARN  todo.adminPassword is the one in the sample's README: "));
        // A stop is sent to the first process. A shell left in front of the server would take it and pass nothing on.
        (await server.FirstProcessAsync(cancellationToken)).ShouldBe("./build/bin/todo-api");
    }

    [Fact(DisplayName = "A setting that says nothing of the environment leaves the image trying the sample out", Timeout = 120_000)]
    public async Task Another_setting_leaves_the_sample_tried_out()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartImageAsync(
            cancellationToken, ("GRAPEVINE_TODO_ALLOWEDORIGINS", "http://localhost:8080"));

        var output = await server.OutputWithAsync(line => line.Contains(Listening), cancellationToken);

        output.ShouldContain(line => line.Contains(Listening) && line.Contains(" environment=Development "));
    }

    [Fact(DisplayName = "An image that its variable calls a deployment does not start without a key and a password of its own", Timeout = 120_000)]
    public async Task A_deployment_by_its_variable_is_one()
    {
        var cancellationToken = TestContext.Current.CancellationToken;

        var (exitCode, output, _) = await ServerFixture.RunImageToExitAsync(
            cancellationToken, [("GRAPEVINE_APP_ENVIRONMENT", "Production")]);

        ShouldHaveRefused(exitCode, output);
    }

    [Fact(DisplayName = "Nor does one that the config file beside it calls a deployment: the image's command does not speak over the file", Timeout = 120_000)]
    public async Task A_deployment_by_its_config_file_is_one()
    {
        var cancellationToken = TestContext.Current.CancellationToken;

        var (exitCode, output) = await RunWithConfigAsync(
            """{"app":{"environment":"Production"}}""", "/src/grapevine.json", [], cancellationToken);

        ShouldHaveRefused(exitCode, output);
    }

    [Fact(DisplayName = "Nor one that the config file GRAPEVINE_CONFIG names calls a deployment", Timeout = 120_000)]
    public async Task A_deployment_by_a_config_file_elsewhere_is_one()
    {
        var cancellationToken = TestContext.Current.CancellationToken;

        var (exitCode, output) = await RunWithConfigAsync(
            """{"app":{"environment":"Production"}}""", "/etc/grapevine/app.json",
            [("GRAPEVINE_CONFIG", "/etc/grapevine/app.json")], cancellationToken);

        ShouldHaveRefused(exitCode, output);
    }

    [Fact(DisplayName = "An image that is given a config file which says nothing of the environment is a deployment: whoever configures a server is not trying it out", Timeout = 120_000)]
    public async Task A_config_file_that_does_not_say_makes_a_deployment()
    {
        var cancellationToken = TestContext.Current.CancellationToken;

        var (exitCode, output) = await RunWithConfigAsync(
            """{"server":{"workers":3}}""", "/src/grapevine.json", [], cancellationToken);

        ShouldHaveRefused(exitCode, output);
    }

    private static async Task<(long ExitCode, string[] Output)> RunWithConfigAsync(
        string json, string containerPath, (string Name, string Value)[] environment, CancellationToken cancellationToken)
    {
        var local = Path.Combine(Path.GetTempPath(), $"grapevine-config-{Guid.NewGuid():N}.json");
        try
        {
            await File.WriteAllTextAsync(local, json, cancellationToken);
            var (exitCode, output, _) = await ServerFixture.RunImageToExitAsync(cancellationToken, environment, (local, containerPath));
            return (exitCode, output);
        }
        finally
        {
            File.Delete(local);
        }
    }

    private static void ShouldHaveRefused(long exitCode, string[] output)
    {
        exitCode.ShouldBe(1, string.Join('\n', output));
        output.ShouldContain(line => line.Contains(NoKey));
        output.ShouldContain(line => line.Contains(ReadmePassword));
        output.ShouldNotContain(line => line.Contains(Listening));
    }
}
