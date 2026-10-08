using System.Globalization;
using System.Net;
using System.Net.Sockets;
using DotNet.Testcontainers.Builders;
using DotNet.Testcontainers.Containers;

namespace Grapevine.E2E;

/// <summary>
/// A container running the Todo sample, which is what the image runs when it is told nothing
/// else. Every test starts its own, so no test sees another's todos.
/// </summary>
public sealed class SampleServer : IAsyncDisposable
{
    private const ushort ContainerPort = 8080;
    private readonly IContainer _container;

    private SampleServer(IContainer container)
    {
        _container = container;
        Port = container.GetMappedPublicPort(ContainerPort);
    }

    public int Port { get; }

    /// <summary>The origin by which a browser on this machine reaches the server.</summary>
    public string Origin => OriginOn(Port);

    public static string OriginOn(int port) => $"http://localhost:{port.ToString(CultureInfo.InvariantCulture)}";

    /// <summary>Starts a server on a port that Docker chooses. Settings are the sample's and the framework's keys.</summary>
    public static async Task<SampleServer> StartAsync(CancellationToken cancellationToken, params (string Key, string Value)[] settings) =>
        await StartAsync(port: null, cancellationToken, settings);

    /// <summary>
    /// Starts a server on a port the test chose. Two servers that are told about each other have
    /// to know each other's ports before either of them runs.
    /// </summary>
    public static async Task<SampleServer> StartOnAsync(int port, CancellationToken cancellationToken, params (string Key, string Value)[] settings) =>
        await StartAsync(port, cancellationToken, settings);

    /// <summary>Ports on this machine that nothing listens on at the moment of asking.</summary>
    public static int[] FreePorts(int count)
    {
        var listeners = Enumerable.Range(0, count).Select(_ => new TcpListener(IPAddress.Loopback, 0)).ToArray();
        try
        {
            foreach (var listener in listeners)
            {
                listener.Start();
            }

            // All held at once before any is given back, so that no two are the same.
            return listeners.Select(listener => ((IPEndPoint)listener.LocalEndpoint).Port).ToArray();
        }
        finally
        {
            foreach (var listener in listeners)
            {
                listener.Dispose();
            }
        }
    }

    private static async Task<SampleServer> StartAsync(int? port, CancellationToken cancellationToken, (string Key, string Value)[] settings)
    {
        var builder = new ContainerBuilder(Environment.GetEnvironmentVariable("GRAPEVINE_IMAGE") ?? "grapevine")
            .WithEnvironment("PORT", ContainerPort.ToString(CultureInfo.InvariantCulture))
            .WithEnvironment(settings.ToDictionary(setting => VariableFor(setting.Key), setting => setting.Value))
            .WithWaitStrategy(Wait.ForUnixContainer().UntilMessageIsLogged("Grapevine listening"));
        builder = port is { } chosen
            ? builder.WithPortBinding(chosen, ContainerPort)
            : builder.WithPortBinding(ContainerPort, assignRandomHostPort: true);
        var container = builder.Build();
        try
        {
            await container.StartAsync(cancellationToken);
        }
        catch
        {
            await container.DisposeAsync();
            throw;
        }

        return new SampleServer(container);
    }

    /// <summary>
    /// The environment variable a setting is read from: <c>GRAPEVINE_</c>, then the key in capitals
    /// with an underscore for whatever is not a letter or a digit.
    /// </summary>
    private static string VariableFor(string key) =>
        "GRAPEVINE_" + string.Concat(key.Select(character =>
            char.IsAsciiLetterOrDigit(character) ? char.ToUpperInvariant(character) : '_'));

    /// <summary>
    /// Every line the server has written, once one of them satisfies <paramref name="expected"/>.
    /// A line reaches the container's log a moment after the server writes it, so a test that
    /// looks for one waits for it here.
    /// </summary>
    public async Task<string[]> LogWithAsync(Func<string, bool> expected, CancellationToken cancellationToken)
    {
        var deadline = DateTime.UtcNow + TimeSpan.FromSeconds(10);
        while (true)
        {
            var (stdout, _) = await _container.GetLogsAsync(timestampsEnabled: false, ct: cancellationToken);
            var lines = stdout.Split('\n', StringSplitOptions.RemoveEmptyEntries);
            if (lines.Any(expected) || DateTime.UtcNow > deadline)
            {
                return lines;
            }

            await Task.Delay(TimeSpan.FromMilliseconds(50), cancellationToken);
        }
    }

    public async ValueTask DisposeAsync()
    {
        await SaveLogAsync();
        await _container.DisposeAsync();
    }

    /// <summary>
    /// Keeps what the server wrote, in the folder server-logs beside the test assembly, under the
    /// container's name and with the test and the port at its head. When a browser test fails,
    /// this is what the server saw of it.
    /// </summary>
    private async Task SaveLogAsync()
    {
        try
        {
            var (stdout, stderr) = await _container.GetLogsAsync(timestampsEnabled: true);
            var folder = Path.Combine(AppContext.BaseDirectory, "server-logs");
            Directory.CreateDirectory(folder);
            var test = TestContext.Current.Test?.TestDisplayName ?? "no test";
            var heading = $"# {test}; host port {Port}; saved {DateTime.UtcNow:O}\n";
            await File.WriteAllTextAsync(Path.Combine(folder, $"{_container.Id}.log"), heading + stdout + stderr);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            // The log helps to look into a failure. Not being able to keep it must not be one.
        }
    }
}
