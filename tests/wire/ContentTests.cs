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

    [Fact(DisplayName = "A second request that brings the first one's ETag is answered 304 with no body, and one with another tag gets the body", Timeout = 120_000)]
    public async Task A_client_that_has_it_is_told_so()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = new HttpClient { BaseAddress = server.BaseAddress };

        using var first = await client.GetAsync("tagged?body=hello", cancellationToken);
        var tag = first.Headers.ETag.ShouldNotBeNull();
        using var again = new HttpRequestMessage(HttpMethod.Get, "tagged?body=hello");
        again.Headers.IfNoneMatch.Add(tag);
        using var second = await client.SendAsync(again, cancellationToken);
        using var other = new HttpRequestMessage(HttpMethod.Get, "tagged?body=hello");
        other.Headers.IfNoneMatch.Add(new System.Net.Http.Headers.EntityTagHeaderValue("\"something-else\""));
        using var third = await client.SendAsync(other, cancellationToken);

        tag.IsWeak.ShouldBeTrue();
        tag.Tag.ShouldBe("\"5-a430d84680aabd0b\"");
        second.StatusCode.ShouldBe(HttpStatusCode.NotModified);
        second.Headers.ETag.ShouldBe(tag);
        (await second.Content.ReadAsByteArrayAsync(cancellationToken)).ShouldBeEmpty();
        third.StatusCode.ShouldBe(HttpStatusCode.OK);
        (await third.Content.ReadAsStringAsync(cancellationToken)).ShouldBe("hello");
    }

    [Fact(DisplayName = "A body of 300,000 bytes that the server writes in pieces of 7,000 arrives whole, with its length, and the connection serves the next request", Timeout = 120_000)]
    public async Task A_sized_body_arrives_whole()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = new HttpClient { BaseAddress = server.BaseAddress };

        using var response = await client.GetAsync("sized/300000?piece=7000", cancellationToken);
        var body = await response.Content.ReadAsByteArrayAsync(cancellationToken);
        var next = await client.GetStringAsync("", cancellationToken);

        response.StatusCode.ShouldBe(HttpStatusCode.OK);
        response.Headers.TransferEncodingChunked.ShouldNotBe(true);
        response.Content.Headers.ContentLength.ShouldBe(300_000);
        body.Length.ShouldBe(300_000);
        Enumerable.Range(0, body.Length).All(index => body[index] == (byte)('0' + index % 10)).ShouldBeTrue();
        next.ShouldBe("ok");
    }

    [Fact(DisplayName = "A download's name reaches the client as it was, accents and all", Timeout = 120_000)]
    public async Task A_download_has_its_name()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = new HttpClient { BaseAddress = server.BaseAddress };

        using var response = await client.GetAsync("download?name=r%C3%A9sum%C3%A9.pdf", cancellationToken);

        var disposition = response.Content.Headers.ContentDisposition.ShouldNotBeNull();
        disposition.DispositionType.ShouldBe("attachment");
        disposition.FileNameStar.ShouldBe("résumé.pdf");
        disposition.FileName.ShouldBe("\"r_sum_.pdf\"");
    }
}
