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
