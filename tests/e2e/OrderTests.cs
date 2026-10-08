namespace Grapevine.E2E;

/// <summary>
/// What the page does when a person is quicker than the network: answers that are slow, that
/// come in another order than they were asked for, or that do not come. Each test holds the
/// requests it is about and lets them go when it wants to.
/// </summary>
public class OrderTests(BrowserFixture browser)
{
    [Fact(DisplayName = "A title that is sent twice before the first answer comes is added once", Timeout = 180_000)]
    public async Task A_title_sent_twice_is_added_once()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);
        var posts = await page.HoldAsync("POST", "/todos");

        await page.TitleInput.FillAsync("Once");
        await page.TitleInput.PressAsync("Enter");
        await posts.Reached.WaitAsync(cancellationToken);
        await page.TitleInput.PressAsync("Enter");
        await page.AddButton.ClickAsync();
        posts.Open();
        await page.SettledAsync();
        var titles = await page.TitlesAsync();

        titles.ShouldBe(["Once"]);
        page.Requests.Count(request => request == $"POST {server.Origin}/todos").ShouldBe(1);
        page.Complaints.ShouldBeEmpty();
    }

    [Fact(DisplayName = "What is typed while a title is on its way stays in the field", Timeout = 180_000)]
    public async Task What_is_typed_meanwhile_stays()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);
        var posts = await page.HoldAsync("POST", "/todos");

        await page.TitleInput.FillAsync("First");
        await page.TitleInput.PressAsync("Enter");
        await posts.Reached.WaitAsync(cancellationToken);
        await page.TitleInput.FillAsync("Second, half typed");
        posts.Open();
        await page.SettledAsync();
        var titles = await page.TitlesAsync();
        var field = await page.TitleInput.InputValueAsync();

        titles.ShouldBe(["First"]);
        field.ShouldBe("Second, half typed");
        page.Complaints.ShouldBeEmpty();
    }

    [Fact(DisplayName = "The list on the page is the one the pressed filter asks for, whichever answer comes last", Timeout = 180_000)]
    public async Task The_last_filter_pressed_is_the_one_shown()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);
        await page.AddAsync("Pick");
        await page.AddAsync("Press");
        await page.SetDoneAsync("Pick", true);
        var done = await page.HoldAsync("GET", "/todos?done=true");

        await page.Page.GetByTestId("filter-done").ClickAsync();
        await done.Reached.WaitAsync(cancellationToken);
        await page.Page.GetByTestId("filter-open").ClickAsync();
        // Long enough for an answer about the open ones to have come first, were it asked for
        // while the one about the done ones is still out.
        await Task.Delay(TimeSpan.FromMilliseconds(300), cancellationToken);
        done.Open();
        await page.SettledAsync();
        var titles = await page.TitlesAsync();
        var count = await page.Count.InnerTextAsync();
        var pressed = await page.Page.GetByTestId("filter-open").GetAttributeAsync("aria-pressed");

        pressed.ShouldBe("true");
        titles.ShouldBe(["Press"]);
        count.ShouldBe("1 open");
        page.Complaints.ShouldBeEmpty();
    }

    [Fact(DisplayName = "A todo that is ticked from the keyboard keeps the keyboard where it was", Timeout = 180_000)]
    public async Task Ticking_keeps_the_focus()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);
        await page.AddAsync("Pick");
        await page.AddAsync("Press");
        await page.AddAsync("Pour");

        await page.Row("Press").GetByTestId("todo-done").FocusAsync();
        await page.Page.Keyboard.PressAsync("Space");
        await page.SettledAsync();
        var afterTicking = await page.FocusAsync();
        var ticked = await page.Row("Press").GetByTestId("todo-done").IsCheckedAsync();
        // The same key again, with nothing done about the focus in between: it reaches the
        // same box only if the keyboard is still on it.
        await page.Page.Keyboard.PressAsync("Space");
        await page.SettledAsync();
        var afterUnticking = await page.FocusAsync();
        var unticked = await page.Row("Press").GetByTestId("todo-done").IsCheckedAsync();

        afterTicking.ShouldBe("todo-done of Press");
        ticked.ShouldBeTrue();
        afterUnticking.ShouldBe("todo-done of Press");
        unticked.ShouldBeFalse();
        page.Complaints.ShouldBeEmpty();
    }

    [Fact(DisplayName = "When the row the keyboard was on goes away, the keyboard is on the row that took its place", Timeout = 180_000)]
    public async Task A_row_that_goes_hands_the_focus_on()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        await using var page = await TodoPage.OpenAsync(browser, server.Origin);
        await page.AddAsync("Pick");
        await page.AddAsync("Press");
        await page.AddAsync("Pour");

        await page.Row("Press").GetByTestId("todo-delete").FocusAsync();
        await page.Page.Keyboard.PressAsync("Enter");
        await page.SettledAsync();
        var afterTheMiddle = await page.FocusAsync();
        await page.Page.Keyboard.PressAsync("Enter");
        await page.SettledAsync();
        var afterTheLast = await page.FocusAsync();
        // Under the filter for what is open, a todo that is ticked leaves the list as well.
        await page.ShowAsync("open");
        await page.Row("Pick").GetByTestId("todo-done").FocusAsync();
        await page.Page.Keyboard.PressAsync("Space");
        await page.SettledAsync();
        var afterTheOnlyOne = await page.FocusAsync();
        var titles = await page.TitlesAsync();

        afterTheMiddle.ShouldBe("todo-delete of Pour");
        afterTheLast.ShouldBe("todo-delete of Pick");
        afterTheOnlyOne.ShouldBe("title-input");
        titles.ShouldBeEmpty();
        page.Complaints.ShouldBeEmpty();
    }

    [Fact(DisplayName = "An answer that does not come is given up on, and the changes after it take their turn", Timeout = 180_000)]
    public async Task An_answer_that_does_not_come_is_given_up_on()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await SampleServer.StartAsync(cancellationToken);
        // The page's clock is the test's to move, so that half a minute of waiting takes none.
        await using var page = await TodoPage.OpenAsync(browser, server.Origin, before: opened => opened.Page.Clock.InstallAsync());
        await page.AddAsync("Kept");
        var posts = await page.HoldAsync("POST", "/todos");

        await page.TitleInput.FillAsync("Never answered");
        await page.TitleInput.PressAsync("Enter");
        await posts.Reached.WaitAsync(cancellationToken);
        await page.Page.GetByTestId("filter-open").ClickAsync();
        await page.Page.Clock.FastForwardAsync(31_000);
        await page.SettledAsync();
        var said = await page.MessageLinesAsync();
        var titles = await page.TitlesAsync();
        var count = await page.Count.InnerTextAsync();
        var field = await page.TitleInput.InputValueAsync();

        said.ShouldBe([$"The API at {server.Origin} did not answer in time."]);
        // The filter that was pressed while the page waited got its turn afterwards.
        titles.ShouldBe(["Kept"]);
        count.ShouldBe("1 open");
        field.ShouldBe("Never answered");
        page.Complaints.ShouldBeEmpty();
    }
}
