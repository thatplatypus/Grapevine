namespace Grapevine.E2E;

public class PageTests(BrowserFixture browser)
{
    [Fact(DisplayName = "The page loads from the sample's own server, styled and scripted, with nothing to complain of", Timeout = 180_000)]
    public async Task The_page_loads()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);

        var title = await page.Page.TitleAsync();
        var heading = await page.Heading.InnerTextAsync();
        var headingSize = await page.Heading.EvaluateAsync<string>("heading => getComputedStyle(heading).fontSize");
        var titles = await page.TitlesAsync();
        var count = await page.Count.InnerTextAsync();
        var api = await page.ApiOrigin.InnerTextAsync();
        var status = await page.ApiStatus.InnerTextAsync();

        title.ShouldBe("Grapevine todos");
        heading.ShouldBe("Grapevine todos");
        // 1.75rem, which only the stylesheet says. With nosniff in force the browser applies a
        // stylesheet only when it came as text/css.
        headingSize.ShouldBe("28px");
        titles.ShouldBeEmpty();
        count.ShouldBe("Nothing to do yet.");
        api.ShouldBe(server.Origin);
        status.ShouldBe("ok");
        page.ConsoleErrors.ShouldBeEmpty();
    }

    [Fact(DisplayName = "The foot of the page links to the API's description of itself, which the browser opens as JSON", Timeout = 180_000)]
    public async Task The_page_links_to_the_description()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);

        var words = await page.ApiDescription.InnerTextAsync();
        var address = await page.ApiDescription.EvaluateAsync<string>("link => link.href");
        var opened = await page.Page.RunAndWaitForResponseAsync(
            async () => await page.ApiDescription.ClickAsync(),
            response => response.Url.EndsWith("/openapi.json", StringComparison.Ordinal));
        await page.Page.WaitForURLAsync($"{server.Origin}/openapi.json");
        var type = await opened.HeaderValueAsync("content-type");
        var text = await opened.TextAsync();

        words.ShouldBe("What the API offers, as OpenAPI");
        address.ShouldBe($"{server.Origin}/openapi.json");
        opened.Status.ShouldBe(200);
        type.ShouldBe("application/json; charset=utf-8");
        text.ShouldStartWith("{\"openapi\":\"3.1.1\",\"info\":{\"title\":\"Todo API\"");
        text.ShouldContain("\"/todos/{id}\"");
        page.ConsoleErrors.ShouldBeEmpty();
    }

    [Fact(DisplayName = "An error the page logs is a complaint the test sees", Timeout = 180_000)]
    public async Task A_logged_error_is_seen()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);

        await page.Page.RunAndWaitForConsoleMessageAsync(
            async () => await page.Page.EvaluateAsync("console.error('seen by the watcher')"));

        page.Complaints.ShouldBe(["seen by the watcher"]);
    }
}
