using System.Text.Json;
using Shouldly;

namespace Grapevine.WireTests;

public class ConfigurationTests
{
    [Fact(DisplayName = "A setting from the environment that is out of range stops the server from starting, with exit code 1 and the reason", Timeout = 120_000)]
    public async Task A_bad_variable_stops_the_server_from_starting()
    {
        var cancellationToken = TestContext.Current.CancellationToken;

        var (exitCode, output, _) = await ServerFixture.RunToExitAsync(cancellationToken, ("GRAPEVINE_SERVER_WORKERS", "0"));

        exitCode.ShouldBe(1);
        output.ShouldContain(line => line.Contains("server.workers must be between 1 and 1024, got 0 (from GRAPEVINE_SERVER_WORKERS)"));
        output.ShouldNotContain(line => line.Contains("Grapevine listening"));
    }

    [Fact(DisplayName = "A GRAPEVINE_ variable that names no setting is warned about by name, and the server starts", Timeout = 120_000)]
    public async Task A_misspelt_variable_is_warned_about()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartWithAsync(
            cancellationToken, ("GRAPEVINE_SERVER_WORKRES", "3"));

        var output = await server.OutputWithAsync(line => line.Contains("Grapevine listening"), cancellationToken);

        output.ShouldContain(line => line.EndsWith(" WARN  the variable GRAPEVINE_SERVER_WORKRES names no setting", StringComparison.Ordinal));
        output.ShouldContain(line => line.Contains("Grapevine listening") && line.EndsWith(" workers=64", StringComparison.Ordinal));
    }

    [Fact(DisplayName = "The variables Kubernetes sets in a pod beside a Service called grapevine do not stop the server", Timeout = 120_000)]
    public async Task Service_links_do_not_stop_the_server()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartWithAsync(
            cancellationToken,
            ("GRAPEVINE_SERVICE_HOST", "10.96.0.12"),
            ("GRAPEVINE_SERVICE_PORT", "8080"),
            ("GRAPEVINE_PORT", "tcp://10.96.0.12:8080"),
            ("GRAPEVINE_PORT_8080_TCP", "tcp://10.96.0.12:8080"),
            ("GRAPEVINE_PORT_8080_TCP_PROTO", "tcp"),
            ("GRAPEVINE_PORT_8080_TCP_PORT", "8080"),
            ("GRAPEVINE_PORT_8080_TCP_ADDR", "10.96.0.12"));
        using var client = server.CreateClient();

        (await client.GetStringAsync("", cancellationToken)).ShouldBe("ok");
        var output = await server.OutputLinesAsync(cancellationToken);
        output.Count(line => line.Contains(" WARN  the variable GRAPEVINE_") && line.EndsWith(" names no setting", StringComparison.Ordinal)).ShouldBe(7);
    }

    [Fact(DisplayName = "With logging off, what stops the server from starting is still said, on standard error", Timeout = 120_000)]
    public async Task What_stops_a_start_is_said_with_logging_off()
    {
        var cancellationToken = TestContext.Current.CancellationToken;

        var (exitCode, output, errors) = await ServerFixture.RunToExitAsync(
            cancellationToken, ("GRAPEVINE_LOG_LEVEL", "off"), ("GRAPEVINE_SERVER_WORKERS", "0"));

        exitCode.ShouldBe(1);
        output.ShouldBeEmpty();
        errors.ShouldBe(["cannot start: server.workers must be between 1 and 1024, got 0 (from GRAPEVINE_SERVER_WORKERS)"]);
    }

    [Fact(DisplayName = "A config file that is named and is not there stops the server from starting, and the reason names the file", Timeout = 120_000)]
    public async Task A_missing_config_file_stops_the_server_from_starting()
    {
        var cancellationToken = TestContext.Current.CancellationToken;

        var (exitCode, output, _) = await ServerFixture.RunToExitAsync(cancellationToken, ("GRAPEVINE_CONFIG", "/nowhere/app.json"));

        exitCode.ShouldBe(1);
        output.ShouldContain(line => line.Contains("the config file /nowhere/app.json does not exist"));
    }

    [Fact(DisplayName = "Settings come from the file that GRAPEVINE_CONFIG names", Timeout = 120_000)]
    public async Task Settings_come_from_the_named_config_file()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartWithAsync(
            cancellationToken, ("GRAPEVINE_CONFIG", "/src/tests/wire/config/three-workers.json"));

        var output = await server.OutputLinesAsync(cancellationToken);

        output.ShouldContain(line => line.Contains("Grapevine listening") && line.EndsWith(" workers=3", StringComparison.Ordinal));
    }

    [Fact(DisplayName = "A variable for a setting wins over the config file", Timeout = 120_000)]
    public async Task A_variable_wins_over_the_config_file()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartWithAsync(
            cancellationToken,
            ("GRAPEVINE_CONFIG", "/src/tests/wire/config/three-workers.json"),
            ("GRAPEVINE_SERVER_WORKERS", "5"));

        var output = await server.OutputLinesAsync(cancellationToken);

        output.ShouldContain(line => line.Contains("Grapevine listening") && line.EndsWith(" workers=5", StringComparison.Ordinal));
    }

    [Fact(DisplayName = "With log.format set to json every line the server writes is a JSON object with a time, a level and a message", Timeout = 120_000)]
    public async Task Json_log_lines_parse()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken, ("log.format", "json"), ("server.workers", 2));
        using var client = await RawClient.ConnectAsync(server, cancellationToken);
        await client.SendAsync(RawClient.Get("/inspect/a?x=1", close: true), cancellationToken);
        (await client.ReadResponseAsync(cancellationToken)).Status.ShouldBe(200);

        var output = await server.OutputWithAsync(line => line.Contains("GET /inspect/a "), cancellationToken);

        output.ShouldNotBeEmpty();
        foreach (var line in output)
        {
            using var document = JsonDocument.Parse(line);
            document.RootElement.GetProperty("time").GetString().ShouldNotBeNullOrEmpty();
            document.RootElement.GetProperty("level").GetString().ShouldBeOneOf("debug", "info", "warn", "error");
            document.RootElement.GetProperty("message").GetString().ShouldNotBeNull();
        }

        using var banner = JsonDocument.Parse(output.First(line => line.Contains("Grapevine listening")));
        banner.RootElement.GetProperty("workers").GetString().ShouldBe("2");
        using var request = JsonDocument.Parse(output.First(line => line.Contains("GET /inspect/a ")));
        request.RootElement.GetProperty("path").GetString().ShouldBe("/inspect/a");
        request.RootElement.GetProperty("status").GetString().ShouldBe("200");
    }

    [Fact(DisplayName = "A request's own X-Request-Id comes back on the response and is in the line the server logs for it", Timeout = 120_000)]
    public async Task A_request_id_is_echoed_and_logged()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = await RawClient.ConnectAsync(server, cancellationToken);

        await client.SendAsync("GET /id HTTP/1.1\r\nHost: wire\r\nX-Request-Id: wire-7\r\nConnection: close\r\n\r\n", cancellationToken);
        var response = await client.ReadResponseAsync(cancellationToken);

        response.Header("X-Request-Id").ShouldBe("wire-7");
        response.Text.ShouldBe("wire-7");
        var output = await server.OutputWithAsync(line => line.Contains(" GET /id 200 "), cancellationToken);
        output.ShouldContain(line => line.Contains(" INFO  GET /id 200 ") && line.EndsWith(" requestId=wire-7", StringComparison.Ordinal));
    }

    [Fact(DisplayName = "A request without an X-Request-Id is given one, and two requests are given different ones", Timeout = 120_000)]
    public async Task A_missing_request_id_is_made()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = await RawClient.ConnectAsync(server, cancellationToken);

        await client.SendAsync(RawClient.Get("/id"), cancellationToken);
        var first = await client.ReadResponseAsync(cancellationToken);
        await client.SendAsync(RawClient.Get("/id", close: true), cancellationToken);
        var second = await client.ReadResponseAsync(cancellationToken);

        var firstId = first.Header("X-Request-Id");
        var secondId = second.Header("X-Request-Id");
        firstId.ShouldNotBeNullOrEmpty();
        firstId.ShouldMatch("^[0-9a-f]{32}$");
        first.Text.ShouldBe(firstId);
        secondId.ShouldNotBeNullOrEmpty();
        secondId.ShouldNotBe(firstId);
    }

    [Fact(DisplayName = "An X-Request-Id that could forge a log line is not taken", Timeout = 120_000)]
    public async Task An_unsafe_request_id_is_replaced()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = await RawClient.ConnectAsync(server, cancellationToken);

        await client.SendAsync("GET /id HTTP/1.1\r\nHost: wire\r\nX-Request-Id: x ERROR forged\r\nConnection: close\r\n\r\n", cancellationToken);
        var response = await client.ReadResponseAsync(cancellationToken);

        response.Header("X-Request-Id").ShouldNotBeNull().ShouldNotContain("forged");
        var output = await server.OutputWithAsync(line => line.Contains(" GET /id 200 "), cancellationToken);
        output.ShouldContain(line => line.Contains(" GET /id 200 "));
        output.ShouldNotContain(line => line.Contains("forged"));
    }
}
