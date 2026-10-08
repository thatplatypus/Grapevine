namespace Grapevine.E2E;

/// <summary>
/// Signing in on the page: a name and a password for a token, which the page keeps in its
/// memory and sends with what it asks, and which opens the list's numbers. The servers here
/// have the password of the sample's README, as one has that was told nothing.
/// </summary>
public class SignInTests(BrowserFixture browser)
{
    private const string User = "admin";
    private const string Password = "vineyard";

    [Fact(DisplayName = "Signed out, the page offers a sign-in at its foot and shows no numbers", Timeout = 180_000)]
    public async Task Signed_out_the_page_offers_a_sign_in()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);

        var form = await page.SignInForm.IsVisibleAsync();
        var user = await page.UserInput.IsVisibleAsync();
        var password = await page.PasswordInput.GetAttributeAsync("type");
        var button = await page.SignInButton.InnerTextAsync();
        var signedIn = await page.SignedIn.IsVisibleAsync();
        var said = await page.AccountMessageLinesAsync();
        var listAuthorizations = await page.AuthorizationsAsync("GET", $"{server.Origin}/todos");

        form.ShouldBeTrue();
        user.ShouldBeTrue();
        password.ShouldBe("password");
        button.ShouldBe("Sign in");
        signedIn.ShouldBeFalse();
        said.ShouldBeEmpty();
        // Nobody is signed in, so nothing the page asks says that anyone is, and the numbers
        // are not asked for at all.
        listAuthorizations.ShouldBe([null]);
        page.Requests.ShouldNotContain($"GET {server.Origin}/admin/stats");
        page.Complaints.ShouldBeEmpty();
    }

    [Fact(DisplayName = "The right name and password sign in: the page says who is signed in, shows the list's numbers and offers to sign out", Timeout = 180_000)]
    public async Task The_right_name_and_password_sign_in()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);
        await page.AddAsync("Prune the vines");
        await page.AddAsync("Press the grapes");
        await page.SetDoneAsync("Press the grapes", true);

        await page.SignInAsync(User, Password);
        var form = await page.SignInForm.IsVisibleAsync();
        var who = await page.Who.InnerTextAsync();
        var numbers = await page.Numbers.InnerTextAsync();
        var signOut = await page.SignOutButton.IsVisibleAsync();
        var passwordField = await page.PasswordInput.InputValueAsync();
        var said = await page.AccountMessageLinesAsync();
        var statsAuthorizations = await page.AuthorizationsAsync("GET", $"{server.Origin}/admin/stats");
        var log = await server.LogWithAsync(line => line.Contains("GET /admin/stats 200"), cancellationToken);

        form.ShouldBeFalse();
        who.ShouldBe("Signed in as admin");
        numbers.ShouldBe("2 todos, 1 open");
        signOut.ShouldBeTrue();
        passwordField.ShouldBeEmpty();
        said.ShouldBeEmpty();
        statsAuthorizations.ShouldHaveSingleItem().ShouldNotBeNull().ShouldStartWith("Bearer ");
        log.ShouldContain(line => line.Contains("POST /login 200"));
        log.ShouldContain(line => line.Contains("GET /admin/stats 200"));
        // Neither the password nor the token is anything a log line has.
        log.ShouldNotContain(line => line.Contains(Password));
        log.ShouldNotContain(line => line.Contains("eyJ"));
        page.Complaints.ShouldBeEmpty();
        page.ConsoleErrors.ShouldBeEmpty();
    }

    [Fact(DisplayName = "The numbers follow the list: after a todo is added, done and deleted they are what the list is", Timeout = 180_000)]
    public async Task The_numbers_follow_the_list()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);
        await page.SignInAsync(User, Password);

        var atFirst = await page.Numbers.InnerTextAsync();
        await page.AddAsync("Bottle the wine");
        var afterAdding = await page.Numbers.InnerTextAsync();
        await page.SetDoneAsync("Bottle the wine", true);
        var afterDoing = await page.Numbers.InnerTextAsync();
        await page.ShowAsync("open");
        var whileFiltered = await page.Numbers.InnerTextAsync();
        await page.ShowAsync("all");
        await page.DeleteAsync("Bottle the wine");
        var afterDeleting = await page.Numbers.InnerTextAsync();

        atFirst.ShouldBe("0 todos, 0 open");
        afterAdding.ShouldBe("1 todo, 1 open");
        afterDoing.ShouldBe("1 todo, 0 open");
        // The numbers are the whole list's, whatever part of it is shown.
        whileFiltered.ShouldBe("1 todo, 0 open");
        afterDeleting.ShouldBe("0 todos, 0 open");
        page.Complaints.ShouldBeEmpty();
    }

    [Fact(DisplayName = "A wrong password: the page shows what the API said, stays signed out and empties the password", Timeout = 180_000)]
    public async Task A_wrong_password_is_refused()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);

        await page.SignInAsync(User, "not the password");
        var said = await page.AccountMessageLinesAsync();
        var form = await page.SignInForm.IsVisibleAsync();
        var signedIn = await page.SignedIn.IsVisibleAsync();
        var userField = await page.UserInput.InputValueAsync();
        var passwordField = await page.PasswordInput.InputValueAsync();
        var listMessage = await page.MessageLinesAsync();

        said.Count.ShouldBe(2);
        said[0].ShouldBe("The name or the password is not right");
        said[1].ShouldMatch("^Request [0-9a-f]{32}$");
        form.ShouldBeTrue();
        signedIn.ShouldBeFalse();
        userField.ShouldBe(User);
        passwordField.ShouldBeEmpty();
        // It is said where the sign-in is, and not where the list's troubles are.
        listMessage.ShouldBeEmpty();
        page.Requests.ShouldNotContain($"GET {server.Origin}/admin/stats");
        page.Refused.ShouldBe([$"POST {server.Origin}/login 401"]);
        page.Complaints.ShouldBeEmpty();
    }

    [Fact(DisplayName = "Signing out brings the sign-in back, takes the numbers away, and the next request says nothing of anyone", Timeout = 180_000)]
    public async Task Signing_out()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);
        await page.SignInAsync(User, Password);
        await page.AddAsync("While signed in");

        await page.SignOutAsync();
        var form = await page.SignInForm.IsVisibleAsync();
        var signedIn = await page.SignedIn.IsVisibleAsync();
        var numbers = await page.Numbers.InnerTextAsync();
        var statsBefore = page.Requests.Count(request => request == $"GET {server.Origin}/admin/stats");
        await page.AddAsync("After signing out");
        var statsAfter = page.Requests.Count(request => request == $"GET {server.Origin}/admin/stats");
        var posts = await page.AuthorizationsAsync("POST", $"{server.Origin}/todos");
        var titles = await page.TitlesAsync();

        form.ShouldBeTrue();
        signedIn.ShouldBeFalse();
        numbers.ShouldBeEmpty();
        statsAfter.ShouldBe(statsBefore);
        // The first todo was added by someone who was signed in, and said so. The second was not.
        posts.Count.ShouldBe(2);
        posts[0].ShouldNotBeNull().ShouldStartWith("Bearer ");
        posts[1].ShouldBeNull();
        titles.ShouldBe(["While signed in", "After signing out"]);
        page.Complaints.ShouldBeEmpty();
    }

    [Fact(DisplayName = "A reload signs out: the token was in the page's memory, and nowhere a script or a later visit could find it", Timeout = 180_000)]
    public async Task A_reload_signs_out()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);
        await page.SignInAsync(User, Password);

        var kept = await page.Page.EvaluateAsync<string>(
            "() => JSON.stringify([localStorage.length, sessionStorage.length, document.cookie, location.href.includes('eyJ')])");
        var cookies = await page.Page.Context.CookiesAsync();
        await page.ReloadAsync();
        var form = await page.SignInForm.IsVisibleAsync();
        var signedIn = await page.SignedIn.IsVisibleAsync();
        var numbers = await page.Numbers.InnerTextAsync();
        var statsAfterReload = page.Requests.Count(request => request == $"GET {server.Origin}/admin/stats");

        kept.ShouldBe("""[0,0,"",false]""");
        cookies.ShouldBeEmpty();
        form.ShouldBeTrue();
        signedIn.ShouldBeFalse();
        numbers.ShouldBeEmpty();
        // Asked for once, when the sign-in was made, and not again by the page that came back.
        statsAfterReload.ShouldBe(1);
        page.Complaints.ShouldBeEmpty();
    }

    [Fact(DisplayName = "A token that the server no longer takes signs the page out, and the page says so", Timeout = 240_000)]
    public async Task A_token_the_server_no_longer_takes_signs_out()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        var port = SampleServer.FreePorts(1)[0];
        var origin = SampleServer.OriginOn(port);
        // Neither server is given a key, so each makes one of its own, and the second does not
        // take what the first signed: what a restart without a key does to those signed in.
        var first = await SampleServer.StartOnAsync(port, cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, origin);
        try
        {
            await page.SignInAsync(User, Password);
        }
        finally
        {
            await first.DisposeAsync();
        }

        await using var second = await SampleServer.StartOnAsync(port, cancellationToken);
        await page.AddAsync("After the restart");
        var form = await page.SignInForm.IsVisibleAsync();
        var signedIn = await page.SignedIn.IsVisibleAsync();
        var numbers = await page.Numbers.InnerTextAsync();
        var said = await page.AccountMessageLinesAsync();
        var titles = await page.TitlesAsync();
        var listMessage = await page.MessageLinesAsync();

        form.ShouldBeTrue();
        signedIn.ShouldBeFalse();
        numbers.ShouldBeEmpty();
        said.Count.ShouldBe(3);
        said[0].ShouldBe("You have been signed out.");
        said[1].ShouldBe("The token is not taken: the token's signature is not ours");
        said[2].ShouldMatch("^Request [0-9a-f]{32}$");
        // The list is open to anyone, and a token that does not hold is no reason to refuse
        // there: the todo was added.
        titles.ShouldBe(["After the restart"]);
        listMessage.ShouldBeEmpty();
        page.Refused.ShouldBe([$"GET {origin}/admin/stats 401"]);
        page.Complaints.ShouldBeEmpty();
    }

    [Fact(DisplayName = "A page on another origin that is allowed signs in, and is shown the numbers", Timeout = 240_000)]
    public async Task A_page_on_another_origin_signs_in()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        var ports = SampleServer.FreePorts(2);
        var pageOrigin = SampleServer.OriginOn(ports[0]);
        var apiOrigin = SampleServer.OriginOn(ports[1]);
        await using var api = await SampleServer.StartOnAsync(ports[1], cancellationToken, ("todo.allowedOrigins", pageOrigin));
        await using var web = await SampleServer.StartOnAsync(ports[0], cancellationToken, ("todo.apiUrl", apiOrigin));
        await using var page = await TodoPage.OpenAsync(browser, web.Origin);
        await page.AddAsync("Across origins");

        await page.SignInAsync(User, Password);
        var who = await page.Who.InnerTextAsync();
        var numbers = await page.Numbers.InnerTextAsync();
        await page.SignOutAsync();
        await page.SignInAsync(User, "not the password");
        var refused = await page.AccountMessageLinesAsync();
        var apiLog = await api.LogWithAsync(line => line.Contains("POST /login 401"), cancellationToken);
        var webLog = await web.LogWithAsync(line => line.Contains("GET /config.json 200"), cancellationToken);

        who.ShouldBe("Signed in as admin");
        numbers.ShouldBe("1 todo, 1 open");
        // The refusal, and the ID of the request that was refused, are read across origins.
        refused.Count.ShouldBe(2);
        refused[0].ShouldBe("The name or the password is not right");
        refused[1].ShouldMatch("^Request [0-9a-f]{32}$");
        // The browser asked before it sent a token, and the API said yes.
        apiLog.ShouldContain(line => line.Contains("OPTIONS /login 204"));
        apiLog.ShouldContain(line => line.Contains("POST /login 200"));
        apiLog.ShouldContain(line => line.Contains("OPTIONS /admin/stats 204"));
        apiLog.ShouldContain(line => line.Contains("GET /admin/stats 200"));
        webLog.ShouldNotContain(line => line.Contains("requestId=") && line.Contains("path=/login"));
        webLog.ShouldNotContain(line => line.Contains("requestId=") && line.Contains("path=/admin/stats"));
        page.Requests.ShouldContain($"POST {apiOrigin}/login");
        page.Requests.ShouldNotContain($"POST {pageOrigin}/login");
        page.Complaints.ShouldBeEmpty();
    }

    [Fact(DisplayName = "A sixth try within the minute is turned away, and the page shows when to try again", Timeout = 240_000)]
    public async Task A_sixth_try_is_turned_away()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);

        for (var tried = 0; tried < 5; tried++)
        {
            await page.SignInAsync(User, "a guess");
        }

        var fifth = await page.AccountMessageLinesAsync();
        await page.SignInAsync(User, Password);
        var sixth = await page.AccountMessageLinesAsync();
        var form = await page.SignInForm.IsVisibleAsync();
        await page.AddAsync("Not counted");
        var titles = await page.TitlesAsync();

        fifth[0].ShouldBe("The name or the password is not right");
        // The right password, and one try too many: it is not looked at.
        sixth[0].ShouldMatch("^Too many requests: try again in [0-9]+ seconds?$");
        form.ShouldBeTrue();
        // The list is nothing the limit counts.
        titles.ShouldBe(["Not counted"]);
        page.Refused.Count(refused => refused == $"POST {server.Origin}/login 401").ShouldBe(5);
        page.Refused.Count(refused => refused == $"POST {server.Origin}/login 429").ShouldBe(1);
        page.Complaints.ShouldBeEmpty();
    }

    [Fact(DisplayName = "A sign-in that is sent twice before the first answer comes is sent once", Timeout = 180_000)]
    public async Task A_sign_in_sent_twice_is_sent_once()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);
        var logins = await page.HoldAsync("POST", "/login");

        await page.UserInput.FillAsync(User);
        await page.PasswordInput.FillAsync(Password);
        await page.PasswordInput.PressAsync("Enter");
        await logins.Reached.WaitAsync(cancellationToken);
        await page.PasswordInput.PressAsync("Enter");
        await page.SignInButton.ClickAsync();
        logins.Open();
        await page.SettledAsync();
        var who = await page.Who.InnerTextAsync();

        who.ShouldBe("Signed in as admin");
        page.Requests.Count(request => request == $"POST {server.Origin}/login").ShouldBe(1);
        page.Complaints.ShouldBeEmpty();
    }

    [Fact(DisplayName = "Signing out while the numbers are on their way leaves the page signed out, whatever comes back", Timeout = 180_000)]
    public async Task Signing_out_while_the_numbers_are_on_their_way()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);
        await page.AddAsync("Counted by nobody");
        var numbers = await page.HoldAsync("GET", "/admin/stats");

        await page.UserInput.FillAsync(User);
        await page.PasswordInput.FillAsync(Password);
        await page.SignInButton.ClickAsync();
        await numbers.Reached.WaitAsync(cancellationToken);
        // Signed in already, with the numbers still to come.
        var whoMeanwhile = await page.Who.InnerTextAsync();
        await page.SignOutButton.ClickAsync();
        numbers.Open();
        await page.SettledAsync();
        var form = await page.SignInForm.IsVisibleAsync();
        var signedIn = await page.SignedIn.IsVisibleAsync();
        var shown = await page.Numbers.InnerTextAsync();
        var said = await page.AccountMessageLinesAsync();

        whoMeanwhile.ShouldBe("Signed in as admin");
        form.ShouldBeTrue();
        signedIn.ShouldBeFalse();
        shown.ShouldBeEmpty();
        said.ShouldBeEmpty();
        page.Complaints.ShouldBeEmpty();
    }

    [Fact(DisplayName = "A todo that is added while a sign-in is on its way is added after it, and counted", Timeout = 180_000)]
    public async Task A_todo_added_while_signing_in()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);
        var logins = await page.HoldAsync("POST", "/login");

        await page.UserInput.FillAsync(User);
        await page.PasswordInput.FillAsync(Password);
        await page.SignInButton.ClickAsync();
        await logins.Reached.WaitAsync(cancellationToken);
        await page.TitleInput.FillAsync("Meanwhile");
        await page.AddButton.ClickAsync();
        logins.Open();
        await page.SettledAsync();
        var titles = await page.TitlesAsync();
        var numbers = await page.Numbers.InnerTextAsync();
        var posts = await page.AuthorizationsAsync("POST", $"{server.Origin}/todos");

        titles.ShouldBe(["Meanwhile"]);
        numbers.ShouldBe("1 todo, 1 open");
        // It waited its turn, so it was sent by someone who was signed in by then.
        posts.ShouldHaveSingleItem().ShouldNotBeNull().ShouldStartWith("Bearer ");
        page.Complaints.ShouldBeEmpty();
    }

    [Fact(DisplayName = "With the keyboard alone: a name, Tab, a password and Enter sign in, and the keyboard is on Sign out; Enter there, and it is back on the name", Timeout = 180_000)]
    public async Task With_the_keyboard_alone()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);

        await page.UserInput.FocusAsync();
        await page.Page.Keyboard.TypeAsync(User);
        await page.Page.Keyboard.PressAsync("Tab");
        var afterTab = await page.FocusAsync();
        await page.Page.Keyboard.TypeAsync(Password);
        await page.Page.Keyboard.PressAsync("Enter");
        await page.SettledAsync();
        var who = await page.Who.InnerTextAsync();
        var afterSigningIn = await page.FocusAsync();
        await page.Page.Keyboard.PressAsync("Enter");
        await page.SettledAsync();
        var form = await page.SignInForm.IsVisibleAsync();
        var afterSigningOut = await page.FocusAsync();
        var userField = await page.UserInput.InputValueAsync();

        afterTab.ShouldBe("password-input");
        who.ShouldBe("Signed in as admin");
        afterSigningIn.ShouldBe("sign-out-button");
        form.ShouldBeTrue();
        afterSigningOut.ShouldBe("user-input");
        userField.ShouldBe(User);
        page.Complaints.ShouldBeEmpty();
    }
}
