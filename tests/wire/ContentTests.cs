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
}
