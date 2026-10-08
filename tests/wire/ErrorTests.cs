using System.Net;
using System.Text;
using System.Text.Json;
using Shouldly;

namespace Grapevine.WireTests;

public class ErrorTests
{
    private const string ProblemMediaType = "application/problem+json; charset=utf-8";

    [Fact(DisplayName = "An error a handler raises comes back as a problem document with its type, title, status, detail and errors", Timeout = 120_000)]
    public async Task A_raised_problem_is_a_problem_document()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = await RawClient.ConnectAsync(server, cancellationToken);

        await client.SendAsync(RawClient.Get("/raise/problem", close: true), cancellationToken);
        var response = await client.ReadResponseAsync(cancellationToken);

        response.Status.ShouldBe(404);
        response.Header("Content-Type").ShouldBe(ProblemMediaType);
        using var document = JsonDocument.Parse(response.Text);
        var problem = document.RootElement;
        problem.GetProperty("type").GetString().ShouldBe("about:blank");
        problem.GetProperty("title").GetString().ShouldBe("Not Found");
        problem.GetProperty("status").GetInt32().ShouldBe(404);
        problem.GetProperty("detail").GetString().ShouldBe("No such thing");
        problem.GetProperty("errors").GetProperty("id")[0].GetString().ShouldBe("is unknown");
    }

    [Fact(DisplayName = "An unexpected error is a 500 that keeps its message from the client, and the log has the message with the response's request ID", Timeout = 120_000)]
    public async Task An_unexpected_error_is_logged_and_not_shown()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = await RawClient.ConnectAsync(server, cancellationToken);

        await client.SendAsync(RawClient.Get("/raise/plain?why=secret", close: true), cancellationToken);
        var response = await client.ReadResponseAsync(cancellationToken);

        response.Status.ShouldBe(500);
        response.Header("Content-Type").ShouldBe(ProblemMediaType);
        response.Text.ShouldNotContain("the disk is full");
        using var document = JsonDocument.Parse(response.Text);
        document.RootElement.GetProperty("detail").GetString().ShouldBe("An unexpected error occurred");
        var requestId = response.Header("X-Request-Id").ShouldNotBeNull();
        var output = await server.OutputWithAsync(line => line.Contains("unhandled error"), cancellationToken);
        output.ShouldContain(line =>
            line.Contains(" ERROR unhandled error: the disk is full ")
            && line.EndsWith($" requestId={requestId} method=GET path=/raise/plain", StringComparison.Ordinal));
    }

    [Fact(DisplayName = "With app.environment set to Development an unexpected error's message is in the response", Timeout = 120_000)]
    public async Task In_development_an_unexpected_error_says_what_it_was()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartWithAsync(
            cancellationToken, ("GRAPEVINE_APP_ENVIRONMENT", "Development"));
        using var client = await RawClient.ConnectAsync(server, cancellationToken);

        await client.SendAsync(RawClient.Get("/raise/plain", close: true), cancellationToken);
        var response = await client.ReadResponseAsync(cancellationToken);

        response.Status.ShouldBe(500);
        using var document = JsonDocument.Parse(response.Text);
        document.RootElement.GetProperty("detail").GetString().ShouldBe("the disk is full");
        var output = await server.OutputWithAsync(line => line.Contains("unhandled error"), cancellationToken);
        output.ShouldContain(line => line.Contains(" ERROR unhandled error: the disk is full "));
    }

    [Fact(DisplayName = "After a handler has raised, the same connection serves the next request", Timeout = 120_000)]
    public async Task A_connection_survives_a_raised_error()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = await RawClient.ConnectAsync(server, cancellationToken);

        await client.SendAsync(RawClient.Get("/raise/plain"), cancellationToken);
        var failed = await client.ReadResponseAsync(cancellationToken);
        await client.SendAsync(RawClient.Get("/", close: true), cancellationToken);
        var served = await client.ReadResponseAsync(cancellationToken);

        failed.Status.ShouldBe(500);
        failed.Header("Connection").ShouldNotBe("close");
        served.Status.ShouldBe(200);
        served.Text.ShouldBe("ok");
    }

    [Fact(DisplayName = "A JSON body sent over a real socket is read and written back", Timeout = 120_000)]
    public async Task A_json_body_is_read_and_written_back()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = server.CreateClient();
        using var content = new StringContent(
            """{ "title": "Ship it", "tags": ["a", "é 🍇"], "n": 1.5, "done": false, "by": null }""",
            Encoding.UTF8,
            "application/json");

        using var response = await client.PostAsync("json", content, cancellationToken);

        response.StatusCode.ShouldBe(HttpStatusCode.OK);
        (await response.Content.ReadAsStringAsync(cancellationToken))
            .ShouldBe("""{"title":"Ship it","tags":["a","é 🍇"],"n":1.5,"done":false,"by":null}""");
    }

    [Fact(DisplayName = "A JSON body with a key twice is refused with a problem that says what was wrong and where", Timeout = 120_000)]
    public async Task A_json_body_with_a_repeated_key_is_refused()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = server.CreateClient();
        using var content = new StringContent("""{"a":1,"a":2}""", Encoding.UTF8, "application/json");

        using var response = await client.PostAsync("json", content, cancellationToken);

        response.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
        response.Content.Headers.ContentType.ShouldNotBeNull().ToString().ShouldBe(ProblemMediaType);
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
        document.RootElement.GetProperty("status").GetInt32().ShouldBe(400);
        document.RootElement.GetProperty("detail").GetString().ShouldBe("The body is not valid JSON: repeated key at byte 7");
    }
}
