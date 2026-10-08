namespace Grapevine.E2E;

/// <summary>
/// What a person sees and does on the sample's page, in the page's own terms. A test says what
/// should be true; how the page is asked is here.
/// </summary>
public sealed class TodoPage : IAsyncDisposable
{
    private readonly IBrowserContext _context;
    private readonly List<string> _errors = [];
    private readonly List<string> _requests = [];

    private TodoPage(IBrowserContext context, IPage page)
    {
        _context = context;
        Page = page;
        page.Console += (_, message) =>
        {
            if (message.Type == "error")
            {
                Keep(message.Text);
            }
        };
        page.PageError += (_, error) => Keep(error);
        page.Request += (_, request) =>
        {
            lock (_requests)
            {
                _requests.Add($"{request.Method} {request.Url}");
            }
        };
    }

    public IPage Page { get; }

    /// <summary>The response the page itself came in.</summary>
    public IResponse Document { get; private set; } = null!;

    /// <summary>
    /// Every error the page's console was given and every error the page threw. A refused
    /// content security policy shows here and nowhere else, so a test that expects none says so.
    /// </summary>
    public IReadOnlyList<string> ConsoleErrors
    {
        get
        {
            lock (_errors)
            {
                return [.. _errors];
            }
        }
    }

    /// <summary>Every request the page has made, as its method and the whole address it asked.</summary>
    public IReadOnlyList<string> Requests
    {
        get
        {
            lock (_requests)
            {
                return [.. _requests];
            }
        }
    }

    public ILocator Heading => Page.GetByRole(AriaRole.Heading, new PageGetByRoleOptions { Level = 1 });

    public ILocator TitleInput => Page.GetByTestId("title-input");

    public ILocator AddButton => Page.GetByTestId("add-button");

    public ILocator Message => Page.GetByTestId("message");

    public ILocator Rows => Page.GetByTestId("todo");

    public ILocator Count => Page.GetByTestId("count");

    public ILocator ApiOrigin => Page.GetByTestId("api-origin");

    public ILocator ApiStatus => Page.GetByTestId("api-status");

    /// <summary>The row of the todo whose title is exactly <paramref name="title"/>.</summary>
    public ILocator Row(string title) => Rows.Filter(new LocatorFilterOptions
    {
        Has = Page.GetByTestId("todo-title").GetByText(title, new LocatorGetByTextOptions { Exact = true }),
    });

    /// <summary>
    /// Opens the page at <paramref name="origin"/> in a browser context of its own and comes back
    /// when the page's script has finished starting.
    /// </summary>
    public static async Task<TodoPage> OpenAsync(BrowserFixture browser, string origin)
    {
        var context = await browser.NewContextAsync();
        try
        {
            var opened = new TodoPage(context, await context.NewPageAsync());
            var document = await opened.Page.GotoAsync(origin + "/")
                ?? throw new InvalidOperationException($"{origin}/ gave the browser no response.");

            // A browser reaches its server through a port that Docker publishes on this machine.
            // Should something else ever answer there, the test says so here, and does not go
            // on to fail in a way that reads like a defect of the page.
            var server = await document.HeaderValueAsync("server");
            var type = await document.HeaderValueAsync("content-type");
            if (server != "Grapevine" || type is null || !type.StartsWith("text/html", StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    $"{origin}/ is not the sample's page: it answered {document.Status} as {type ?? "no type"}, "
                    + $"from the server {server ?? "that gave no name"}.");
            }

            opened.Document = document;
            await opened.ReadyAsync();
            return opened;
        }
        catch
        {
            await context.DisposeAsync();
            throw;
        }
    }

    /// <summary>Types a title, presses Add, and comes back when the page has caught up with the API.</summary>
    public async Task AddAsync(string title)
    {
        await TitleInput.FillAsync(title);
        await AddButton.ClickAsync();
        await SettledAsync();
    }

    public async Task SetDoneAsync(string title, bool done)
    {
        await Row(title).GetByTestId("todo-done").SetCheckedAsync(done);
        await SettledAsync();
    }

    public async Task DeleteAsync(string title)
    {
        await Row(title).GetByTestId("todo-delete").ClickAsync();
        await SettledAsync();
    }

    /// <summary>Presses one of the filters: all, open or done.</summary>
    public async Task ShowAsync(string which)
    {
        await Page.GetByTestId($"filter-{which}").ClickAsync();
        await SettledAsync();
    }

    public async Task ReloadAsync()
    {
        await Page.ReloadAsync();
        await ReadyAsync();
    }

    /// <summary>The titles in the list, from the top.</summary>
    public async Task<IReadOnlyList<string>> TitlesAsync() =>
        await Page.GetByTestId("todo-title").AllInnerTextsAsync();

    /// <summary>What the page says went wrong, line by line. Empty when it says nothing.</summary>
    public async Task<IReadOnlyList<string>> MessageLinesAsync() =>
        await Message.Locator("p").AllInnerTextsAsync();

    public async ValueTask DisposeAsync() => await _context.DisposeAsync();

    // The browser reports on a thread of its own.
    private void Keep(string error)
    {
        lock (_errors)
        {
            _errors.Add(error);
        }
    }

    // The script marks the document once it has asked where the API is, how it is, and what is
    // in the list, whatever the answers were.
    private async Task ReadyAsync() =>
        await Page.Locator("html[data-ready='true']").WaitForAsync(new LocatorWaitForOptions { State = WaitForSelectorState.Attached });

    // The script says aria-busy for as long as a change and the reading of the list that
    // follows it are under way. It says so before the click that began them has returned.
    private async Task SettledAsync() =>
        await Page.Locator("main:not([aria-busy='true'])").WaitForAsync();
}
