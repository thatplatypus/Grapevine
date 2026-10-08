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

    private ServerFixture(IContainer container)
    {
        _container = container;
        // Asked once, while the container runs: a test that stops the server still wants to
        // say where it was.
        Port = container.GetMappedPublicPort(ContainerPort);
    }

    public string Host => _container.Hostname;

    public int Port { get; }

    public Uri BaseAddress => new($"http://{Host}:{Port}/");

    /// <summary>
    /// A client for this server that fails any request whose answer did not come from a Grapevine
    /// server. A test reaches its server through a port that Docker publishes on this machine, and
    /// once in some hundreds of containers an answer has come back that the server never gave: a
    /// 404 for a route it has, with no line for the request in its log. Whatever answers in its
    /// place then, the test says so here, with what it was told, instead of failing on an
    /// assertion that reads like a defect of the server.
    /// </summary>
    public HttpClient CreateClient(HttpMessageHandler? handler = null) =>
        new(new OwnServerHandler(this, handler ?? new HttpClientHandler())) { BaseAddress = BaseAddress };

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
    public static async Task<ServerFixture> StartWithAsync(CancellationToken cancellationToken, params (string Name, string Value)[] environment) =>
        await StartAsync(cancellationToken, environment, files: []);

    /// <summary>Starts a server in whose container the local file <paramref name="localPath"/> is at <paramref name="containerPath"/>.</summary>
    public static async Task<ServerFixture> StartWithFileAsync(CancellationToken cancellationToken, string localPath, string containerPath) =>
        await StartAsync(cancellationToken, environment: [], files: [(localPath, containerPath)]);

    private static async Task<ServerFixture> StartAsync(
        CancellationToken cancellationToken, (string Name, string Value)[] environment, (string LocalPath, string ContainerPath)[] files)
    {
        var variables = environment.ToDictionary(variable => variable.Name, variable => variable.Value);
        var builder = new ContainerBuilder(Environment.GetEnvironmentVariable("GRAPEVINE_IMAGE") ?? "grapevine");
        foreach (var (localPath, containerPath) in files)
        {
            builder = builder.WithResourceMapping(new FileInfo(localPath), new FileInfo(containerPath));
        }

        var container = builder
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

    /// <summary>
    /// Sends a signal to the server process and returns without waiting for what it does. With
    /// <paramref name="endsTheServer"/> the signal is one the server answers by exiting at once.
    /// The container can then be gone before the command that sent the signal has reported
    /// back, and its report of failure means nothing: the test looks at the exit code instead.
    /// </summary>
    public async Task SignalAsync(string signal, CancellationToken cancellationToken, bool endsTheServer = false)
    {
        var result = await _container.ExecAsync(["sh", "-c", $"kill -{signal} 1"], cancellationToken);
        if (result.ExitCode != 0 && !endsTheServer)
        {
            throw new InvalidOperationException($"kill -{signal} failed: {result.Stderr}");
        }
    }

    /// <summary>
    /// The most memory the server process has ever had resident, in kilobytes: the kernel's own
    /// high-water mark for the first process in the container.
    /// </summary>
    public async Task<long> PeakMemoryKilobytesAsync(CancellationToken cancellationToken)
    {
        var result = await _container.ExecAsync(["sh", "-c", "grep VmHWM /proc/1/status"], cancellationToken);
        var digits = new string(result.Stdout.Where(char.IsDigit).ToArray());
        if (result.ExitCode != 0 || digits.Length == 0)
        {
            throw new InvalidOperationException($"could not read the server's memory: {result.Stdout}{result.Stderr}");
        }

        return long.Parse(digits, CultureInfo.InvariantCulture);
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

    public async ValueTask DisposeAsync()
    {
        await SaveLogAsync();
        await _container.DisposeAsync();
    }

    /// <summary>
    /// Keeps what the server wrote, in a file named after its container, in the folder server-logs
    /// beside the test assembly. When a test fails for a reason the client cannot show, such as a
    /// request that was never answered, this is the only record of what the server saw. The test
    /// run's own output names the container each test used.
    /// </summary>
    private async Task SaveLogAsync()
    {
        try
        {
            var (stdout, stderr) = await _container.GetLogsAsync(timestampsEnabled: true);
            var folder = Path.Combine(AppContext.BaseDirectory, "server-logs");
            Directory.CreateDirectory(folder);
            // Which test this was and where it reached its server, so that a log can be found by
            // either and a stray answer traced to a port.
            var test = TestContext.Current.Test?.TestDisplayName ?? "no test";
            var heading = $"# {test}; host port {Port}; saved {DateTime.UtcNow:O}\n";
            await File.WriteAllTextAsync(Path.Combine(folder, $"{_container.Id}.log"), heading + stdout + stderr);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            // The log helps to look into a failure. Not being able to keep it must not be one.
        }
    }

    /// <summary>
    /// Lets through the answers of a Grapevine server, which all say <c>Server: Grapevine</c>, and
    /// turns any other into a failure that shows what was said and by which port.
    /// </summary>
    private sealed class OwnServerHandler(ServerFixture server, HttpMessageHandler inner) : DelegatingHandler(inner)
    {
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var response = await base.SendAsync(request, cancellationToken);
            if (response.Headers.TryGetValues("Server", out var names) && names.Contains("Grapevine"))
            {
                return response;
            }

            using (response)
            {
                var headers = string.Join("; ", response.Headers.Concat(response.Content.Headers)
                    .Select(header => $"{header.Key}: {string.Join(", ", header.Value)}"));
                var body = await response.Content.ReadAsStringAsync(cancellationToken);
                throw new InvalidOperationException(
                    $"{request.Method} {request.RequestUri} was answered by something that is not this test's server. "
                    + $"It said {(int)response.StatusCode} with the headers [{headers}] and a body that begins "
                    + $"\"{body[..Math.Min(body.Length, 300)]}\". The server is container {server._container.Id}, "
                    + $"published on host port {server.Port}; its log is kept in server-logs.");
            }
        }
    }

    private sealed class UntilExited : IWaitUntil
    {
        public Task<bool> UntilAsync(IContainer container) =>
            Task.FromResult(container.State == TestcontainersStates.Exited);
    }
}
