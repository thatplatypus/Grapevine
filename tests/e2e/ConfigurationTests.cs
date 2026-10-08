namespace Grapevine.E2E;

/// <summary>
/// How the page finds out where its API is, and what it does until it knows and when it cannot
/// find out. The page's own server is asked, and nothing is sent anywhere before it has answered.
/// </summary>
public class ConfigurationTests(BrowserFixture browser)
{
    [Fact(DisplayName = "What a person does before the page knows where its API is waits, and then goes to the API", Timeout = 240_000)]
    public async Task Nothing_is_sent_before_the_page_knows_its_api()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        var ports = SampleServer.FreePorts(2);
        var pageOrigin = SampleServer.OriginOn(ports[0]);
        var apiOrigin = SampleServer.OriginOn(ports[1]);
        await using var api = await SampleServer.StartOnAsync(ports[1], cancellationToken, ("todo.allowedOrigins", pageOrigin));
        await using var web = await SampleServer.StartOnAsync(ports[0], cancellationToken, ("todo.apiUrl", apiOrigin));
        Gate? configuration = null;
        await using var page = await TodoPage.OpenAsync(
            browser,
            web.Origin,
            before: async opened => configuration = await opened.HoldAsync("GET", "/config.json"),
            untilReady: false);
        configuration.ShouldNotBeNull();

        await configuration.Reached.WaitAsync(cancellationToken);
        await page.TitleInput.FillAsync("Early");
        await page.TitleInput.PressAsync("Enter");
        // Long enough for the title to have been sent somewhere, were the page to send it.
        await Task.Delay(TimeSpan.FromMilliseconds(300), cancellationToken);
        var sentMeanwhile = page.Requests.Where(request => request.Contains("/todos", StringComparison.Ordinal)).ToArray();
        configuration.Open();
        await page.ReadyAsync();
        await page.SettledAsync();
        var titles = await page.TitlesAsync();
        using var direct = new HttpClient();
        var atTheApi = await direct.GetStringAsync($"{apiOrigin}/todos", cancellationToken);
        var atThePagesServer = await direct.GetStringAsync($"{pageOrigin}/todos", cancellationToken);

        sentMeanwhile.ShouldBeEmpty();
        titles.ShouldBe(["Early"]);
        page.Requests.ShouldContain($"POST {apiOrigin}/todos");
        page.Requests.ShouldNotContain($"POST {pageOrigin}/todos");
        atTheApi.ShouldContain("\"title\":\"Early\"");
        atThePagesServer.ShouldBe("[]");
        page.Complaints.ShouldBeEmpty();
    }

    [Fact(DisplayName = "A page that cannot find out where its API is says so, and sends nothing anywhere", Timeout = 240_000)]
    public async Task A_page_that_cannot_find_its_api_sends_nothing()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        var ports = SampleServer.FreePorts(2);
        var pageOrigin = SampleServer.OriginOn(ports[0]);
        var apiOrigin = SampleServer.OriginOn(ports[1]);
        await using var api = await SampleServer.StartOnAsync(ports[1], cancellationToken, ("todo.allowedOrigins", pageOrigin));
        await using var web = await SampleServer.StartOnAsync(ports[0], cancellationToken, ("todo.apiUrl", apiOrigin));
        // Something between the page and its server answers for the server, and not with what
        // the server would have said: a gateway that has lost it, as a rule.
        await using var page = await TodoPage.OpenAsync(
            browser,
            web.Origin,
            before: async opened => await opened.Page.RouteAsync(
                url => new Uri(url).AbsolutePath == "/config.json",
                async route => await route.FulfillAsync(new RouteFulfillOptions
                {
                    Status = 502,
                    ContentType = "text/html",
                    Body = "<h1>Bad Gateway</h1>",
                })));

        var saidAtFirst = await page.MessageLinesAsync();
        await page.AddAsync("Lost");
        var saidAfterAdding = await page.MessageLinesAsync();
        var shownApi = await page.ApiOrigin.InnerTextAsync();
        var status = await page.ApiStatus.InnerTextAsync();
        var field = await page.TitleInput.InputValueAsync();
        using var direct = new HttpClient();
        var atTheApi = await direct.GetStringAsync($"{apiOrigin}/todos", cancellationToken);
        var atThePagesServer = await direct.GetStringAsync($"{pageOrigin}/todos", cancellationToken);

        string[] doesNotKnow =
        [
            "This page could not find out where its API is, so it sends nothing.",
            "Load the page again to have it ask once more.",
        ];
        saidAtFirst.ShouldBe(doesNotKnow);
        saidAfterAdding.ShouldBe(doesNotKnow);
        shownApi.ShouldBe("unknown");
        status.ShouldBe("not asked");
        field.ShouldBe("Lost");
        page.Requests.ShouldNotContain(request => request.Contains("/todos", StringComparison.Ordinal));
        page.Requests.ShouldNotContain(request => request.Contains("/health", StringComparison.Ordinal));
        atTheApi.ShouldBe("[]");
        atThePagesServer.ShouldBe("[]");
        page.Refused.ShouldBe([$"GET {pageOrigin}/config.json 502"]);
        page.Complaints.ShouldBeEmpty();
    }

    [Fact(DisplayName = "A server that has nothing to say about it is its own API", Timeout = 180_000)]
    public async Task A_server_that_says_nothing_is_its_own_api()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        // The page as another server might serve it: one that has the page's files and no more.
        await using var page = await TodoPage.OpenAsync(
            browser,
            server.Origin,
            before: async opened => await opened.Page.RouteAsync(
                url => new Uri(url).AbsolutePath == "/config.json",
                async route => await route.FulfillAsync(new RouteFulfillOptions { Status = 404, ContentType = "text/plain", Body = "Not Found" })));

        await page.AddAsync("Mine");
        var titles = await page.TitlesAsync();
        var shownApi = await page.ApiOrigin.InnerTextAsync();
        var status = await page.ApiStatus.InnerTextAsync();

        titles.ShouldBe(["Mine"]);
        shownApi.ShouldBe(server.Origin);
        status.ShouldBe("ok");
        page.Requests.ShouldContain($"POST {server.Origin}/todos");
        page.Refused.ShouldBe([$"GET {server.Origin}/config.json 404"]);
        page.Complaints.ShouldBeEmpty();
    }
}
