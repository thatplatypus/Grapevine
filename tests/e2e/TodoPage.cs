namespace Grapevine.E2E;

/// <summary>
/// What a person sees and does on the sample's page, in the page's own terms. A test says what
/// should be true; how the page is asked is here.
/// </summary>
public sealed class TodoPage : IAsyncDisposable
{
    private readonly IBrowserContext _context;
    private readonly List<(string Text, string Where)> _errors = [];
    private readonly List<string> _requests = [];
    private readonly List<(string Said, string Url)> _refused = [];
    private readonly List<(string Said, string Url)> _unanswered = [];
    private readonly List<Gate> _gates = [];

    private TodoPage(IBrowserContext context, IPage page)
    {
        _context = context;
        Page = page;
        page.Console += (_, message) =>
        {
            if (message.Type == "error")
            {
                Keep(message.Text, message.Location);
            }
        };
        page.PageError += (_, error) => Keep(error, "");
        page.Request += (_, request) =>
        {
            lock (_requests)
            {
                _requests.Add($"{request.Method} {request.Url}");
            }
        };
        page.Response += (_, response) =>
        {
            if (response.Status >= 400)
            {
                lock (_refused)
                {
                    _refused.Add(($"{response.Request.Method} {response.Url} {response.Status}", response.Url));
                }
            }
        };
        page.RequestFailed += (_, request) =>
        {
            lock (_unanswered)
            {
                _unanswered.Add(($"{request.Method} {request.Url}", request.Url));
            }
        };
    }

    public IPage Page { get; }

    /// <summary>The response the page itself came in.</summary>
    public IResponse Document { get; private set; } = null!;

    /// <summary>
    /// Every error the page's console was given and every error the page threw, as the browser
    /// worded it. How a browser words things is the browser's business: a test asks
    /// <see cref="Complaints"/> whether anything is wrong.
    /// </summary>
    public IReadOnlyList<string> ConsoleErrors
    {
        get
        {
            lock (_errors)
            {
                return [.. _errors.Select(error => error.Text)];
            }
        }
    }

    /// <summary>
    /// The answers the page was given that say no, as the method, the whole address and the
    /// status: everything from 400 up.
    /// </summary>
    public IReadOnlyList<string> Refused
    {
        get
        {
            lock (_refused)
            {
                return [.. _refused.Select(answer => answer.Said)];
            }
        }
    }

    /// <summary>
    /// The requests of the page that came to nothing, as the method and the whole address: no
    /// connection, or an answer the browser would not hand to the page.
    /// </summary>
    public IReadOnlyList<string> Unanswered
    {
        get
        {
            lock (_unanswered)
            {
                return [.. _unanswered.Select(request => request.Said)];
            }
        }
    }

    /// <summary>
    /// The errors that nothing in <see cref="Refused"/> or <see cref="Unanswered"/> accounts for.
    /// A browser notes every request that did not go well in its console, in words of its own,
    /// and such a note is told from a real complaint by the address it is about: the one it
    /// was logged for, or one it names. A refused content security policy, a script that
    /// throws and anything the page logs itself are complaints, so a test that expects none
    /// says so.
    /// </summary>
    public IReadOnlyList<string> Complaints
    {
        get
        {
            string[] addresses;
            lock (_refused)
            {
                lock (_unanswered)
                {
                    addresses = [.. _refused.Select(answer => answer.Url), .. _unanswered.Select(request => request.Url)];
                }
            }

            lock (_errors)
            {
                return [.. _errors
                    .Where(error => !addresses.Any(address => error.Where.StartsWith(address, StringComparison.Ordinal) || error.Text.Contains(address, StringComparison.Ordinal)))
                    .Select(error => error.Text)];
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
    /// when the page's script has finished starting. What <paramref name="before"/> does is done
    /// before the page is asked for, which is when a test has to say what the page's requests
    /// will meet. A test that holds the page's start back passes false for
    /// <paramref name="untilReady"/>, and waits with <see cref="ReadyAsync"/> when it has let go.
    /// </summary>
    public static async Task<TodoPage> OpenAsync(
        BrowserFixture browser, string origin, Func<TodoPage, Task>? before = null, bool untilReady = true)
    {
        var context = await browser.NewContextAsync();
        try
        {
            var opened = new TodoPage(context, await context.NewPageAsync());
            if (before is not null)
            {
                await before(opened);
            }

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
            if (untilReady)
            {
                await opened.ReadyAsync();
            }

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

    /// <summary>
    /// Holds back the page's requests of <paramref name="method"/> for
    /// <paramref name="pathAndQuery"/>, each until the gate that comes back is opened. With it a
    /// test says in which order things happen, where it could otherwise only hope.
    /// </summary>
    public async Task<Gate> HoldAsync(string method, string pathAndQuery)
    {
        var gate = new Gate();
        lock (_gates)
        {
            _gates.Add(gate);
        }

        await Page.RouteAsync(
            url => new Uri(url).PathAndQuery == pathAndQuery,
            async route =>
            {
                if (route.Request.Method == method)
                {
                    await gate.PassAsync();
                }

                await route.FallbackAsync();
            });
        return gate;
    }

    /// <summary>
    /// Where the keyboard is: the test id of the control that has the focus, with the title of
    /// its todo when it is in a row, or "nothing" when no control has it.
    /// </summary>
    public async Task<string> FocusAsync() =>
        await Page.EvaluateAsync<string>(
            """
            () => {
              const held = document.activeElement;
              if (!held || held === document.body) {
                return 'nothing';
              }
              const row = held.closest('[data-testid="todo"]');
              const name = held.dataset.testid ?? held.tagName.toLowerCase();
              return row ? `${name} of ${row.querySelector('[data-testid="todo-title"]').textContent}` : name;
            }
            """);

    /// <summary>The titles in the list, from the top.</summary>
    public async Task<IReadOnlyList<string>> TitlesAsync() =>
        await Page.GetByTestId("todo-title").AllInnerTextsAsync();

    /// <summary>What the page says went wrong, line by line. Empty when it says nothing.</summary>
    public async Task<IReadOnlyList<string>> MessageLinesAsync() =>
        await Message.Locator("p").AllInnerTextsAsync();

    public async ValueTask DisposeAsync()
    {
        // A request that is still held would keep its handler waiting for good.
        Gate[] gates;
        lock (_gates)
        {
            gates = [.. _gates];
        }

        foreach (var gate in gates)
        {
            gate.Open();
        }

        await _context.DisposeAsync();
    }

    /// <summary>
    /// Comes back when the page's script has finished starting. The script marks the document
    /// once it has asked where the API is, how it is, and what is in the list, whatever the
    /// answers were.
    /// </summary>
    public async Task ReadyAsync() =>
        await Page.Locator("html[data-ready='true']").WaitForAsync(new LocatorWaitForOptions { State = WaitForSelectorState.Attached });

    /// <summary>
    /// Comes back when the page has caught up with the API. The script marks the document as
    /// busy for as long as any change, and the reading of the list that follows it, is under
    /// way or waiting for its turn. It does so before the click that began them has returned.
    /// </summary>
    public async Task SettledAsync() =>
        await Page.Locator("html:not([data-busy])").WaitForAsync(new LocatorWaitForOptions { State = WaitForSelectorState.Attached });

    // The browser reports on a thread of its own.
    private void Keep(string error, string where)
    {
        lock (_errors)
        {
            _errors.Add((error, where));
        }
    }
}

/// <summary>
/// Where a test holds the page's requests of one kind until it lets them go.
/// </summary>
public sealed class Gate
{
    private readonly TaskCompletionSource _reached = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly TaskCompletionSource _opened = new(TaskCreationOptions.RunContinuationsAsynchronously);

    /// <summary>Done once a request has come to the gate: the page has sent it, and has no answer yet.</summary>
    public Task Reached => _reached.Task;

    /// <summary>Lets through every request that waits here, and every one that comes later.</summary>
    public void Open() => _opened.TrySetResult();

    internal async Task PassAsync()
    {
        _reached.TrySetResult();
        await _opened.Task;
    }
}
