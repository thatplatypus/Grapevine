using System.Net;
using System.Net.Http.Json;
using System.Text.RegularExpressions;

namespace Grapevine.E2E;

/// <summary>What a person does with the page, when the page and the API are one server.</summary>
public class SameOriginTests(BrowserFixture browser)
{
    private const string ContentSecurityPolicy =
        "default-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";

    [Fact(DisplayName = "A todo that is added is in the list, and is still there after a reload", Timeout = 180_000)]
    public async Task A_todo_is_added()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);

        await page.AddAsync("Prune the vines");
        var afterAdding = await page.TitlesAsync();
        var field = await page.TitleInput.InputValueAsync();
        var count = await page.Count.InnerTextAsync();
        await page.ReloadAsync();
        var afterReload = await page.TitlesAsync();
        var log = await server.LogWithAsync(line => line.Contains("POST /todos 201"), cancellationToken);

        afterAdding.ShouldBe(["Prune the vines"]);
        field.ShouldBeEmpty();
        count.ShouldBe("1 todo");
        afterReload.ShouldBe(["Prune the vines"]);
        log.ShouldContain(line => line.Contains("POST /todos 201"));
        page.ConsoleErrors.ShouldBeEmpty();
    }

    [Fact(DisplayName = "An empty title is the API's to refuse, and the page shows what it said and which request it was", Timeout = 180_000)]
    public async Task An_empty_title_is_refused()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);

        await page.AddAsync("");
        var said = await page.MessageLinesAsync();
        var titles = await page.TitlesAsync();

        said.Count.ShouldBe(3);
        said[0].ShouldBe("The request is not valid");
        said[1].ShouldBe("title: must not be empty");
        var request = Regex.Match(said[2], "^Request ([0-9a-f]{32})$");
        request.Success.ShouldBeTrue(said[2]);
        titles.ShouldBeEmpty();
        var log = await server.LogWithAsync(line => line.Contains(request.Groups[1].Value), cancellationToken);
        log.ShouldContain(line => line.Contains("POST /todos 400") && line.Contains($"requestId={request.Groups[1].Value}"));
        // The refusal is the one thing that did not go well, and the browser's note of it the
        // only thing in the console.
        page.Refused.ShouldBe([$"POST {server.Origin}/todos 400"]);
        page.Complaints.ShouldBeEmpty();
    }

    [Fact(DisplayName = "A todo that is marked done is struck through, and the filters tell done from open", Timeout = 180_000)]
    public async Task Done_and_the_filters()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);
        await page.AddAsync("Pick");
        await page.AddAsync("Press");

        await page.SetDoneAsync("Pick", true);
        var struck = await page.Row("Pick").GetByTestId("todo-title")
            .EvaluateAsync<string>("title => getComputedStyle(title).textDecorationLine");
        await page.ShowAsync("done");
        var done = await page.TitlesAsync();
        var doneCount = await page.Count.InnerTextAsync();
        var donePressed = await page.Page.GetByTestId("filter-done").GetAttributeAsync("aria-pressed");
        await page.ShowAsync("open");
        var open = await page.TitlesAsync();
        var openCount = await page.Count.InnerTextAsync();
        await page.SetDoneAsync("Press", true);
        var noneOpen = await page.Count.InnerTextAsync();
        await page.ShowAsync("all");
        var all = await page.TitlesAsync();
        await page.SetDoneAsync("Pick", false);
        await page.ShowAsync("open");
        var openAgain = await page.TitlesAsync();

        struck.ShouldBe("line-through");
        done.ShouldBe(["Pick"]);
        doneCount.ShouldBe("1 done");
        donePressed.ShouldBe("true");
        open.ShouldBe(["Press"]);
        openCount.ShouldBe("1 open");
        noneOpen.ShouldBe("Nothing open.");
        all.ShouldBe(["Pick", "Press"]);
        openAgain.ShouldBe(["Pick"]);
        // The filters are the API's: the page asks for a part of the list and shows what it is given.
        page.Requests.ShouldContain($"GET {server.Origin}/todos?done=true");
        page.Requests.ShouldContain($"GET {server.Origin}/todos?done=false");
        var log = await server.LogWithAsync(line => line.Contains("PUT /todos/2 200"), cancellationToken);
        log.ShouldContain(line => line.Contains("PUT /todos/1 200"));
        page.ConsoleErrors.ShouldBeEmpty();
    }

    [Fact(DisplayName = "A todo that is deleted is gone, from the page and from the server", Timeout = 180_000)]
    public async Task A_todo_is_deleted()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);
        await page.AddAsync("Keep");
        await page.AddAsync("Drop");

        await page.DeleteAsync("Drop");
        var afterDeleting = await page.TitlesAsync();
        await page.ReloadAsync();
        var afterReload = await page.TitlesAsync();
        var log = await server.LogWithAsync(line => line.Contains("DELETE /todos/2 204"), cancellationToken);

        afterDeleting.ShouldBe(["Keep"]);
        afterReload.ShouldBe(["Keep"]);
        log.ShouldContain(line => line.Contains("DELETE /todos/2 204"));
        page.ConsoleErrors.ShouldBeEmpty();
    }

    [Fact(DisplayName = "A list that is full refuses one more, and the page says why", Timeout = 180_000)]
    public async Task A_full_list_says_so()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken, ("todo.capacity", "2"));
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);
        await page.AddAsync("One");
        await page.AddAsync("Two");

        await page.AddAsync("Three");
        var said = await page.MessageLinesAsync();
        var titles = await page.TitlesAsync();
        var field = await page.TitleInput.InputValueAsync();

        said.Count.ShouldBe(2);
        said[0].ShouldBe("The list is full: it holds 2 todos");
        said[1].ShouldStartWith("Request ");
        titles.ShouldBe(["One", "Two"]);
        // What was typed is still there to be sent again once there is room.
        field.ShouldBe("Three");
        page.Refused.ShouldBe([$"POST {server.Origin}/todos 409"]);
        page.Complaints.ShouldBeEmpty();
    }

    [Fact(DisplayName = "A list of forty todos comes to the browser compressed, and the page shows every one of them", Timeout = 180_000)]
    public async Task A_long_list_comes_compressed()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        using var client = new HttpClient { BaseAddress = new Uri(server.Origin) };
        var titles = Enumerable.Range(1, 40).Select(number => $"Todo number {number} of forty").ToArray();
        foreach (var title in titles)
        {
            using var made = await client.PostAsJsonAsync("/todos", new { title }, cancellationToken);
            made.StatusCode.ShouldBe(HttpStatusCode.Created);
        }

        await using var page = await TodoPage.OpenAsync(browser, server.Origin);
        var shown = await page.TitlesAsync();
        var list = page.AnswerTo("GET", $"{server.Origin}/todos");
        var encoding = await list.HeaderValueAsync("content-encoding");
        var onTheWire = (await list.Request.SizesAsync()).ResponseBodySize;
        var read = (await list.BodyAsync()).Length;

        encoding.ShouldBe("gzip");
        shown.ShouldBe(titles);
        read.ShouldBeGreaterThan(1024);
        onTheWire.ShouldBeLessThan(read / 2);
        page.Complaints.ShouldBeEmpty();
    }

    [Fact(DisplayName = "A title that reads like markup is shown as the text it is, and runs nothing", Timeout = 180_000)]
    public async Task Markup_is_text()
    {
        const string markup = "<img src=x onerror=\"document.title='run'\">";
        const string accented = "Grapes 🍇 for the café";
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);

        await page.AddAsync(markup);
        await page.AddAsync(accented);
        await page.ReloadAsync();
        var titles = await page.TitlesAsync();
        var images = await page.Rows.Locator("img").CountAsync();
        var documentTitle = await page.Page.TitleAsync();
        var deleteLabel = await page.Row(accented).GetByTestId("todo-delete").GetAttributeAsync("aria-label");

        titles.ShouldBe([markup, accented]);
        images.ShouldBe(0);
        documentTitle.ShouldBe("Grapevine todos");
        deleteLabel.ShouldBe($"Delete: {accented}");
        page.ConsoleErrors.ShouldBeEmpty();
    }

    [Fact(DisplayName = "The page comes with the headers that make a browser careful, and its content security policy lets the page do its work and nothing else", Timeout = 180_000)]
    public async Task The_page_is_served_carefully()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);
        var headers = await page.Document.AllHeadersAsync();

        // Everything a person does, under the policy the page was sent with.
        await page.AddAsync("Under the policy");
        await page.SetDoneAsync("Under the policy", true);
        await page.ShowAsync("done");
        await page.DeleteAsync("Under the policy");
        var errorsOfItsOwn = page.ConsoleErrors;

        // And two things the page never does, which the policy has to stop: a script written
        // into the page, and a call to somewhere that is not its API, here this same server
        // under its other name. A browser says what its policy stopped with an event that
        // names the rule and what it was applied to, and it sends none for anything else.
        var elsewhere = $"http://127.0.0.1:{server.Port}";
        var stopped = await page.Page.EvaluateAsync<string[]>(
            """
            async elsewhere => {
              const stopped = [];
              document.addEventListener('securitypolicyviolation', event => stopped.push(`${event.effectiveDirective} ${event.blockedURI}`));
              const script = document.createElement('script');
              script.textContent = "document.title = 'an inline script ran'";
              document.head.append(script);
              await fetch(`${elsewhere}/health`).catch(() => {});
              // The events are sent after the calls they are about have returned.
              await new Promise(resolve => setTimeout(resolve, 200));
              return stopped;
            }
            """,
            elsewhere);
        var documentTitle = await page.Page.TitleAsync();

        headers["x-content-type-options"].ShouldBe("nosniff");
        headers["x-frame-options"].ShouldBe("DENY");
        headers["referrer-policy"].ShouldBe("same-origin");
        headers["content-security-policy"].ShouldBe(ContentSecurityPolicy);
        errorsOfItsOwn.ShouldBeEmpty();
        documentTitle.ShouldBe("Grapevine todos");
        stopped.ShouldContain(line => line.StartsWith("script-src", StringComparison.Ordinal) && line.EndsWith(" inline", StringComparison.Ordinal));
        stopped.ShouldContain(line => line.StartsWith("connect-src ", StringComparison.Ordinal) && line.Contains(elsewhere, StringComparison.Ordinal));
    }
}
