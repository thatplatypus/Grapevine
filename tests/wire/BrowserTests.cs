using System.Net;
using System.Text;
using Shouldly;

namespace Grapevine.WireTests;

public class BrowserTests
{
    [Fact(DisplayName = "A preflight from an allowed origin is answered, and the request it was for is run and may be read by the page", Timeout = 120_000)]
    public async Task A_page_on_an_allowed_origin_may_call()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = new HttpClient { BaseAddress = server.BaseAddress };
        using var preflight = new HttpRequestMessage(HttpMethod.Options, "cors/data");
        preflight.Headers.Add("Origin", "https://app.example");
        preflight.Headers.Add("Access-Control-Request-Method", "PUT");
        preflight.Headers.Add("Access-Control-Request-Headers", "content-type");
        using var actual = new HttpRequestMessage(HttpMethod.Put, "cors/data")
        {
            Content = new StringContent("hello", Encoding.UTF8, "text/plain"),
        };
        actual.Headers.Add("Origin", "https://app.example");

        using var allowed = await client.SendAsync(preflight, cancellationToken);
        using var ran = await client.SendAsync(actual, cancellationToken);

        allowed.StatusCode.ShouldBe(HttpStatusCode.NoContent);
        allowed.Headers.GetValues("Access-Control-Allow-Origin").ShouldHaveSingleItem().ShouldBe("https://app.example");
        allowed.Headers.GetValues("Access-Control-Allow-Methods").ShouldHaveSingleItem().ShouldBe("GET, HEAD, POST, PUT");
        allowed.Headers.GetValues("Access-Control-Allow-Headers").ShouldHaveSingleItem().ShouldBe("content-type, x-token");
        allowed.Headers.GetValues("Access-Control-Allow-Credentials").ShouldHaveSingleItem().ShouldBe("true");
        allowed.Headers.GetValues("Access-Control-Max-Age").ShouldHaveSingleItem().ShouldBe("600");
        allowed.Headers.Vary.ShouldBe(["Origin", "Access-Control-Request-Method", "Access-Control-Request-Headers"]);
        ran.StatusCode.ShouldBe(HttpStatusCode.OK);
        (await ran.Content.ReadAsStringAsync(cancellationToken)).ShouldBe("put hello");
        ran.Headers.GetValues("Access-Control-Allow-Origin").ShouldHaveSingleItem().ShouldBe("https://app.example");
        ran.Headers.GetValues("Access-Control-Expose-Headers").ShouldHaveSingleItem().ShouldBe("x-request-id");
    }

    [Fact(DisplayName = "A request from an origin that is not allowed is refused before it runs, and a request with no origin runs", Timeout = 120_000)]
    public async Task A_page_on_another_origin_may_not()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = new HttpClient { BaseAddress = server.BaseAddress };
        using var foreign = new HttpRequestMessage(HttpMethod.Put, "cors/data")
        {
            Content = new StringContent("hello", Encoding.UTF8, "text/plain"),
        };
        foreign.Headers.Add("Origin", "https://evil.example");

        using var refused = await client.SendAsync(foreign, cancellationToken);
        var direct = await client.GetStringAsync("cors/data", cancellationToken);

        refused.StatusCode.ShouldBe(HttpStatusCode.Forbidden);
        refused.Headers.Contains("Access-Control-Allow-Origin").ShouldBeFalse();
        refused.Headers.Vary.ShouldBe(["Origin"]);
        (await refused.Content.ReadAsStringAsync(cancellationToken)).ShouldContain("The origin https://evil.example is not allowed");
        direct.ShouldBe("data");
    }

    [Fact(DisplayName = "A probe is answered 200, and 503 once the server has been told to stop and is waiting out its delay", Timeout = 120_000)]
    public async Task A_probe_sees_a_stop_coming()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken, ("server.shutdownDelayMs", 4000));
        using var client = new HttpClient { BaseAddress = server.BaseAddress };

        using var well = await client.GetAsync("health", cancellationToken);
        var wellBody = await well.Content.ReadAsStringAsync(cancellationToken);
        await server.SignalAsync("TERM", cancellationToken);
        using var going = await client.GetAsync("health", cancellationToken);
        var goingBody = await going.Content.ReadAsStringAsync(cancellationToken);
        var served = await client.GetStringAsync("", cancellationToken);
        var exitCode = await server.WaitForExitAsync(cancellationToken);

        well.StatusCode.ShouldBe(HttpStatusCode.OK);
        wellBody.ShouldBe("""{"status":"ok","checks":{"clock":"ok"}}""");
        going.StatusCode.ShouldBe(HttpStatusCode.ServiceUnavailable);
        goingBody.ShouldBe("""{"status":"stopping"}""");
        served.ShouldBe("ok");
        exitCode.ShouldBe(0);
    }
}
