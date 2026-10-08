using System.Net;
using Shouldly;

namespace Grapevine.WireTests;

public class RoutingTests
{
    [Fact(DisplayName = "The most specific route answers: a literal before an integer parameter before a parameter", Timeout = 120_000)]
    public async Task The_most_specific_route_answers()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = server.CreateClient();

        (await client.GetStringAsync("kinds/new", cancellationToken)).ShouldBe("/kinds/new");
        (await client.GetStringAsync("kinds/42", cancellationToken)).ShouldBe("/kinds/:id:int|id=42");
        (await client.GetStringAsync("kinds/caf%C3%A9", cancellationToken)).ShouldBe("/kinds/:name|name=café");
    }

    [Fact(DisplayName = "A path that is no integer, or a number too large to be one, is a 404 from a route that asks for an integer", Timeout = 120_000)]
    public async Task A_route_that_asks_for_an_integer_refuses_anything_else()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = server.CreateClient();

        using var word = await client.GetAsync("only/seven", cancellationToken);
        using var huge = await client.GetAsync("only/18446744073709551617", cancellationToken);
        var served = await client.GetStringAsync("only/7", cancellationToken);

        word.StatusCode.ShouldBe(HttpStatusCode.NotFound);
        huge.StatusCode.ShouldBe(HttpStatusCode.NotFound);
        served.ShouldBe("/only/:id:int|id=7");
    }

    [Fact(DisplayName = "A catch-all is given the rest of the path, and an optional parameter may be absent", Timeout = 120_000)]
    public async Task Catch_all_and_optional_segments()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = server.CreateClient();

        (await client.GetStringAsync("kinds/rest/a/b%20c", cancellationToken)).ShouldBe("/kinds/rest/*path|path=a/b c");
        (await client.GetStringAsync("kinds/rest", cancellationToken)).ShouldBe("/kinds/rest/*path|path=");
        (await client.GetStringAsync("kinds/opt/x", cancellationToken)).ShouldBe("/kinds/opt/:value?|value=x");
        (await client.GetStringAsync("kinds/opt", cancellationToken)).ShouldBe("/kinds/opt/:value?");
    }

    [Fact(DisplayName = "A method that none of the matching routes has is a 405 whose Allow lists the methods of all of them", Timeout = 120_000)]
    public async Task Allow_lists_the_methods_of_every_matching_route()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = server.CreateClient();

        using var response = await client.PutAsync("kinds/new", content: null, cancellationToken);

        response.StatusCode.ShouldBe(HttpStatusCode.MethodNotAllowed);
        string.Join(", ", response.Content.Headers.Allow).ShouldBe("GET, HEAD, DELETE, OPTIONS");
    }
}
