using System.Text.RegularExpressions;

namespace Grapevine.E2E;

/// <summary>
/// The page on one origin and the API on another: two servers of the same image, each told
/// about the other. The page's server tells the page where the API is, and the API is told
/// which origin's pages may call it.
/// </summary>
public class CrossOriginTests(BrowserFixture browser)
{
    [Fact(DisplayName = "A page on one origin uses the API on another that allows it", Timeout = 240_000)]
    public async Task An_allowed_origin_uses_the_api()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        var ports = SampleServer.FreePorts(2);
        var pageOrigin = SampleServer.OriginOn(ports[0]);
        var apiOrigin = SampleServer.OriginOn(ports[1]);
        await using var api = await SampleServer.StartOnAsync(ports[1], cancellationToken, ("todo.allowedOrigins", pageOrigin));
        await using var web = await SampleServer.StartOnAsync(ports[0], cancellationToken, ("todo.apiUrl", apiOrigin));
        await using var page = await TodoPage.OpenAsync(browser, web.Origin);

        var shownApi = await page.ApiOrigin.InnerTextAsync();
        var status = await page.ApiStatus.InnerTextAsync();
        var whereThePageIs = await page.Page.EvaluateAsync<string>("() => location.origin");
        await page.AddAsync("Across origins");
        var afterAdding = await page.TitlesAsync();
        await page.SetDoneAsync("Across origins", true);
        await page.ShowAsync("done");
        var done = await page.TitlesAsync();
        await page.DeleteAsync("Across origins");
        var afterDeleting = await page.TitlesAsync();
        var policy = await page.Document.HeaderValueAsync("content-security-policy");
        var apiLog = await api.LogWithAsync(line => line.Contains("DELETE /todos/1 204"), cancellationToken);
        var webLog = await web.LogWithAsync(line => line.Contains("GET /config.json 200"), cancellationToken);

        // Two origins in the browser's eyes, and the page knows which one its API is.
        whereThePageIs.ShouldBe(pageOrigin);
        shownApi.ShouldBe(apiOrigin);
        apiOrigin.ShouldNotBe(pageOrigin);
        status.ShouldBe("ok");
        afterAdding.ShouldBe(["Across origins"]);
        done.ShouldBe(["Across origins"]);
        afterDeleting.ShouldBeEmpty();
        policy.ShouldBe($"default-src 'self'; connect-src 'self' {apiOrigin}; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
        // The browser asked before each kind of change, and the API said yes.
        apiLog.ShouldContain(line => line.Contains("OPTIONS /todos 204"));
        apiLog.ShouldContain(line => line.Contains("POST /todos 201"));
        apiLog.ShouldContain(line => line.Contains("OPTIONS /todos/1 204"));
        apiLog.ShouldContain(line => line.Contains("PUT /todos/1 200"));
        apiLog.ShouldContain(line => line.Contains("DELETE /todos/1 204"));
        // The page's own server served the page and was asked for nothing else: of the lines it
        // wrote for requests, none is for the list or for a probe.
        webLog.ShouldContain(line => line.Contains("GET /config.json 200"));
        webLog.ShouldNotContain(line => line.Contains("requestId=") && line.Contains("path=/todos"));
        webLog.ShouldNotContain(line => line.Contains("requestId=") && line.Contains("path=/health"));
        page.Requests.ShouldContain($"POST {apiOrigin}/todos");
        page.Requests.ShouldNotContain($"POST {pageOrigin}/todos");
        page.ConsoleErrors.ShouldBeEmpty();
    }

    [Fact(DisplayName = "A page on another origin can read the ID of a refused request, because the API lets it", Timeout = 240_000)]
    public async Task A_header_is_read_across_origins()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        var ports = SampleServer.FreePorts(2);
        var apiOrigin = SampleServer.OriginOn(ports[1]);
        await using var api = await SampleServer.StartOnAsync(
            ports[1], cancellationToken, ("todo.allowedOrigins", SampleServer.OriginOn(ports[0])));
        await using var web = await SampleServer.StartOnAsync(ports[0], cancellationToken, ("todo.apiUrl", apiOrigin));
        await using var page = await TodoPage.OpenAsync(browser, web.Origin);

        await page.AddAsync("");
        var said = await page.MessageLinesAsync();

        said.Count.ShouldBe(3);
        said[0].ShouldBe("The request is not valid");
        said[1].ShouldBe("title: must not be empty");
        var request = Regex.Match(said[2], "^Request ([0-9a-f]{32})$");
        request.Success.ShouldBeTrue(said[2]);
        var apiLog = await api.LogWithAsync(line => line.Contains(request.Groups[1].Value), cancellationToken);
        apiLog.ShouldContain(line => line.Contains("POST /todos 400") && line.Contains($"requestId={request.Groups[1].Value}"));
        page.ConsoleErrors.ShouldBe(["Failed to load resource: the server responded with a status of 400 (Bad Request)"]);
    }

    [Fact(DisplayName = "A page on an origin that is not allowed is told it cannot use the API, and what it sends changes nothing", Timeout = 240_000)]
    public async Task An_origin_that_is_not_allowed_changes_nothing()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        var ports = SampleServer.FreePorts(2);
        var pageOrigin = SampleServer.OriginOn(ports[0]);
        var apiOrigin = SampleServer.OriginOn(ports[1]);
        // The API allows some page, and it is not this one.
        await using var api = await SampleServer.StartOnAsync(ports[1], cancellationToken, ("todo.allowedOrigins", "https://another.example"));
        await using var web = await SampleServer.StartOnAsync(ports[0], cancellationToken, ("todo.apiUrl", apiOrigin));
        await using var page = await TodoPage.OpenAsync(browser, web.Origin);

        var status = await page.ApiStatus.InnerTextAsync();
        var saidAtFirst = await page.MessageLinesAsync();
        await page.AddAsync("From a page that may not");
        var saidAfterAdding = await page.MessageLinesAsync();
        // What the page does is asked about first, and the browser stops at the refusal. A
        // page that means harm sends what a browser does not ask about: a plain POST, whose
        // answer it cannot read and does not need. Only the server can refuse that.
        await page.Page.EvaluateAsync(
            """
            api => fetch(`${api}/todos`, {
              method: 'POST',
              mode: 'no-cors',
              headers: { 'Content-Type': 'text/plain' },
              body: JSON.stringify({ title: 'Forged behind the visitor\'s back' }),
            })
            """,
            apiOrigin);
        var apiLog = await api.LogWithAsync(line => line.Contains("POST /todos 403"), cancellationToken);
        using var direct = new HttpClient();
        using var asked = await direct.GetAsync($"{apiOrigin}/todos", cancellationToken);
        var list = await asked.Content.ReadAsStringAsync(cancellationToken);

        string[] cannotReach =
        [
            $"The API at {apiOrigin} cannot be reached from this page.",
            $"If it is running, it may not allow pages from {pageOrigin}.",
        ];
        status.ShouldBe("cannot be reached");
        saidAtFirst.ShouldBe(cannotReach);
        saidAfterAdding.ShouldBe(cannotReach);
        apiLog.ShouldContain(line => line.Contains("GET /todos 403"));
        apiLog.ShouldContain(line => line.Contains("OPTIONS /todos 403"));
        apiLog.ShouldContain(line => line.Contains("POST /todos 403"));
        apiLog.ShouldNotContain(line => line.Contains("POST /todos 201"));
        // Asked directly, by a client that is no page of anyone's: nothing was ever added.
        asked.Headers.GetValues("Server").ShouldBe(["Grapevine"]);
        list.ShouldBe("[]");
        page.ConsoleErrors.ShouldNotBeEmpty();
        page.ConsoleErrors.ShouldAllBe(error => error.Contains("CORS") || error.Contains("Failed to load resource"));
    }
}
