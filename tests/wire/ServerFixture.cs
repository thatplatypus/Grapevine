using System.Globalization;
using DotNet.Testcontainers.Builders;
using DotNet.Testcontainers.Configurations;
using DotNet.Testcontainers.Containers;

namespace Grapevine.WireTests;

/// <summary>
/// A container running the diagnostic app with its own settings. Every test starts one, so a test
/// that fills every worker or stops the server cannot disturb another.
/// </summary>
public sealed class ServerFixture : IAsyncDisposable
{
    private const ushort ContainerPort = 8080;
    private readonly IContainer _container;

    private ServerFixture(IContainer container) => _container = container;

    public string Host => _container.Hostname;

    public int Port => _container.GetMappedPublicPort(ContainerPort);

    public Uri BaseAddress => new($"http://{Host}:{Port}/");

    /// <summary>
    /// Starts a server. Settings are the framework's own keys, such as <c>server.workers</c>, with a
    /// number or a text for each.
    /// </summary>
    public static async Task<ServerFixture> StartAsync(CancellationToken cancellationToken, params (string Key, object Value)[] settings)
    {
        var variables = settings
            .Select(setting => (VariableFor(setting.Key), Convert.ToString(setting.Value, CultureInfo.InvariantCulture) ?? string.Empty))
            .ToArray();
        return await StartWithAsync(cancellationToken, variables);
    }

    /// <summary>Starts a server with these environment variables, exactly as given.</summary>
    public static async Task<ServerFixture> StartWithAsync(CancellationToken cancellationToken, params (string Name, string Value)[] environment)
    {
        var variables = environment.ToDictionary(variable => variable.Name, variable => variable.Value);
        var container = new ContainerBuilder(Environment.GetEnvironmentVariable("GRAPEVINE_IMAGE") ?? "grapevine")
            // Run as it is, with no stdbuf around it: the tests that read the banner while the
            // server runs hold only because its log lines are written unbuffered.
            .WithCommand("./build/bin/wire-host")
            .WithEnvironment("PORT", ContainerPort.ToString(CultureInfo.InvariantCulture))
            .WithEnvironment(variables)
            .WithPortBinding(ContainerPort, assignRandomHostPort: true)
            // How long a stop waits before it kills is set here and not left to the Docker
            // installation, which may allow as little as a second. The grace period under
            // test is the server's own, so the kill has to come later than any of them.
            .WithCreateParameterModifier(parameters => parameters.StopTimeout = TimeSpan.FromSeconds(30))
            // The banner, not a probe request: a probe would take a worker and a keep-alive slot
            // that the tests about workers and idle connections are counting.
            .WithWaitStrategy(Wait.ForUnixContainer().UntilMessageIsLogged("Grapevine listening"))
            .Build();
        try
        {
            await container.StartAsync(cancellationToken);
        }
        catch
        {
            await container.DisposeAsync();
            throw;
        }

        return new ServerFixture(container);
    }

    /// <summary>
    /// Runs the server with an environment that should keep it from starting, waits for the process
    /// to end by itself, and returns its exit code and every line it wrote, to standard output and
    /// to standard error.
    /// </summary>
    public static async Task<(long ExitCode, string[] Output, string[] Errors)> RunToExitAsync(
        CancellationToken cancellationToken, params (string Name, string Value)[] environment)
    {
        var container = new ContainerBuilder(Environment.GetEnvironmentVariable("GRAPEVINE_IMAGE") ?? "grapevine")
            .WithCommand("./build/bin/wire-host")
            .WithEnvironment("PORT", ContainerPort.ToString(CultureInfo.InvariantCulture))
            .WithEnvironment(environment.ToDictionary(variable => variable.Name, variable => variable.Value))
            // The process is expected to end, so its end is the only thing there is to wait for.
            .WithWaitStrategy(Wait.ForUnixContainer().AddCustomWaitStrategy(
                new UntilExited(), strategy => strategy.WithMode(WaitStrategyMode.OneShot)))
            .Build();
        await using (container)
        {
            await container.StartAsync(cancellationToken);
            var exitCode = await container.GetExitCodeAsync(cancellationToken);
            var (stdout, stderr) = await container.GetLogsAsync(timestampsEnabled: false, ct: cancellationToken);
            return (
                exitCode,
                stdout.Split('\n', StringSplitOptions.RemoveEmptyEntries),
                stderr.Split('\n', StringSplitOptions.RemoveEmptyEntries));
        }
    }

    /// <summary>
    /// The environment variable the framework reads a setting from: <c>GRAPEVINE_</c>, then the key in
    /// capitals with an underscore for whatever is not a letter or a digit.
    /// </summary>
    public static string VariableFor(string key) =>
        "GRAPEVINE_" + string.Concat(key.Select(character =>
            char.IsAsciiLetterOrDigit(character) ? char.ToUpperInvariant(character) : '_'));

    /// <summary>Stops the server the way an orchestrator does, with SIGTERM, and returns its exit code.</summary>
    public async Task<long> StopAsync(CancellationToken cancellationToken)
    {
        await _container.StopAsync(cancellationToken);
        return await _container.GetExitCodeAsync(cancellationToken);
    }

    /// <summary>Sends a signal to the server process and returns without waiting for what it does.</summary>
    public async Task SignalAsync(string signal, CancellationToken cancellationToken)
    {
        var result = await _container.ExecAsync(["sh", "-c", $"kill -{signal} 1"], cancellationToken);
        if (result.ExitCode != 0)
        {
            throw new InvalidOperationException($"kill -{signal} failed: {result.Stderr}");
        }
    }

    /// <summary>Waits for the server process to end by itself and returns its exit code.</summary>
    public async Task<long> WaitForExitAsync(CancellationToken cancellationToken) =>
        await _container.GetExitCodeAsync(cancellationToken);

    /// <summary>Every line the server has written to standard output so far.</summary>
    public async Task<string[]> OutputLinesAsync(CancellationToken cancellationToken)
    {
        var (stdout, _) = await _container.GetLogsAsync(timestampsEnabled: false, ct: cancellationToken);
        return stdout.Split('\n', StringSplitOptions.RemoveEmptyEntries);
    }

    /// <summary>
    /// Every line the server has written, once one of them satisfies <paramref name="expected"/>.
    /// A line reaches the container's log a moment after the server writes it, so a test that
    /// looks for one line waits for it here instead of reading the log once and hoping.
    /// </summary>
    public async Task<string[]> OutputWithAsync(Func<string, bool> expected, CancellationToken cancellationToken)
    {
        var deadline = DateTime.UtcNow + TimeSpan.FromSeconds(10);
        while (true)
        {
            var lines = await OutputLinesAsync(cancellationToken);
            if (lines.Any(expected) || DateTime.UtcNow > deadline)
            {
                return lines;
            }

            await Task.Delay(TimeSpan.FromMilliseconds(50), cancellationToken);
        }
    }

    public async ValueTask DisposeAsync() => await _container.DisposeAsync();

    private sealed class UntilExited : IWaitUntil
    {
        public Task<bool> UntilAsync(IContainer container) =>
            Task.FromResult(container.State == TestcontainersStates.Exited);
    }
}
