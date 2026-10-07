using System.Globalization;
using DotNet.Testcontainers.Builders;
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

    /// <summary>Starts a server. Settings are the framework's own keys, such as <c>server.workers</c>.</summary>
    public static async Task<ServerFixture> StartAsync(CancellationToken cancellationToken, params (string Key, int Value)[] settings)
    {
        var assignments = settings.Select(setting => string.Create(CultureInfo.InvariantCulture, $"{setting.Key}={setting.Value}"));
        var container = new ContainerBuilder(Environment.GetEnvironmentVariable("GRAPEVINE_IMAGE") ?? "grapevine")
            // Line-buffered, so the startup banner reaches the container log while the server runs.
            .WithCommand("stdbuf", "-oL", "./build/bin/wire-host")
            .WithEnvironment("PORT", ContainerPort.ToString(CultureInfo.InvariantCulture))
            .WithEnvironment("GRAPEVINE_TEST_SETTINGS", string.Join(',', assignments))
            .WithPortBinding(ContainerPort, assignRandomHostPort: true)
            // How long a stop waits before it kills is set here and not left to the Docker
            // installation, which may allow as little as a second. The grace period under
            // test is the server's own, so the kill has to come later than any of them.
            .WithCreateParameterModifier(parameters => parameters.StopTimeout = TimeSpan.FromSeconds(30))
            // The banner, not a probe request: a probe would take a worker and a keep-alive slot
            // that the tests about workers and idle connections are counting.
            .WithWaitStrategy(Wait.ForUnixContainer().UntilMessageIsLogged("Grapevine listening"))
            .Build();
        await container.StartAsync(cancellationToken);
        return new ServerFixture(container);
    }

    /// <summary>Stops the server the way an orchestrator does, with SIGTERM, and returns its exit code.</summary>
    public async Task<long> StopAsync(CancellationToken cancellationToken)
    {
        await _container.StopAsync(cancellationToken);
        return await _container.GetExitCodeAsync(cancellationToken);
    }

    public async ValueTask DisposeAsync() => await _container.DisposeAsync();
}
