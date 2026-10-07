using System.Net;
using Shouldly;

namespace Grapevine.WireTests;

public class ContentTests
{
    [Fact(DisplayName = "A client that follows redirects ends up where a 302 sent it", Timeout = 120_000)]
    public async Task A_redirect_is_followed()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = new HttpClient { BaseAddress = server.BaseAddress };

        using var response = await client.GetAsync("go?to=/", cancellationToken);

        response.StatusCode.ShouldBe(HttpStatusCode.OK);
        response.RequestMessage.ShouldNotBeNull().RequestUri.ShouldBe(server.BaseAddress);
        (await response.Content.ReadAsStringAsync(cancellationToken)).ShouldBe("ok");
    }

    [Fact(DisplayName = "A client that does not follow redirects sees the status and the Location", Timeout = 120_000)]
    public async Task A_redirect_has_its_status_and_location()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var handler = new HttpClientHandler { AllowAutoRedirect = false };
        using var client = new HttpClient(handler) { BaseAddress = server.BaseAddress };

        using var response = await client.GetAsync("go?to=/next%3Fa=1&status=308", cancellationToken);

        response.StatusCode.ShouldBe(HttpStatusCode.PermanentRedirect);
        response.Headers.Location.ShouldNotBeNull().OriginalString.ShouldBe("/next?a=1");
        (await response.Content.ReadAsByteArrayAsync(cancellationToken)).ShouldBeEmpty();
    }

    [Fact(DisplayName = "A cookie whose value has a space, a semicolon and an accent is set, sent back by the client and read as the text it was", Timeout = 120_000)]
    public async Task A_cookie_comes_back_as_it_went()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        var cookies = new CookieContainer();
        using var handler = new HttpClientHandler { CookieContainer = cookies };
        using var client = new HttpClient(handler) { BaseAddress = server.BaseAddress };

        using var set = await client.GetAsync("cookie?name=note&value=a%20b%3B%20caf%C3%A9", cancellationToken);
        var sentBack = await client.GetStringAsync("cookie", cancellationToken);

        set.Headers.GetValues("Set-Cookie").ShouldHaveSingleItem()
            .ShouldBe("note=a%20b%3B%20caf%C3%A9; Path=/; HttpOnly; SameSite=Lax");
        cookies.GetCookies(server.BaseAddress)["note"].ShouldNotBeNull().HttpOnly.ShouldBeTrue();
        sentBack.ShouldBe("note=a b; café");
    }
}
