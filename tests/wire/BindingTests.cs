using System.Net;
using System.Text;
using System.Text.Json;
using Shouldly;

namespace Grapevine.WireTests;

public class BindingTests
{
    [Fact(DisplayName = "A request that is right in its body, its route and its query is answered with what the handler read", Timeout = 120_000)]
    public async Task What_is_right_is_read()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = server.CreateClient();
        using var content = new StringContent(
            """{"title":" Ship it ","count":2,"rate":0.5,"level":"high","done":true}""", Encoding.UTF8, "application/json");

        using var response = await client.PostAsync("bind/7?page=3", content, cancellationToken);

        response.StatusCode.ShouldBe(HttpStatusCode.OK);
        (await response.Content.ReadAsStringAsync(cancellationToken))
            .ShouldBe("""{"id":7,"title":"Ship it","count":2,"rate":0.5,"level":"high","done":true,"page":3}""");
    }

    [Fact(DisplayName = "A request that is wrong in several fields is one 400 that lists each of them under errors", Timeout = 120_000)]
    public async Task What_is_wrong_is_listed_by_field()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = server.CreateClient();
        using var content = new StringContent(
            """{"title":"","count":9,"rate":0.5,"level":"sideways"}""", Encoding.UTF8, "application/json");

        using var response = await client.PostAsync("bind/7?page=zero", content, cancellationToken);

        response.StatusCode.ShouldBe(HttpStatusCode.BadRequest);
        response.Content.Headers.ContentType.ShouldNotBeNull().ToString().ShouldBe("application/problem+json; charset=utf-8");
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
        var problem = document.RootElement;
        problem.GetProperty("status").GetInt32().ShouldBe(400);
        problem.GetProperty("detail").GetString().ShouldBe("The request is not valid");
        var errors = problem.GetProperty("errors");
        errors.EnumerateObject().Select(field => field.Name).ShouldBe(["title", "count", "level", "page"]);
        errors.GetProperty("title")[0].GetString().ShouldBe("must not be empty");
        errors.GetProperty("count")[0].GetString().ShouldBe("must be between 1 and 5");
        errors.GetProperty("level")[0].GetString().ShouldBe("must be one of low, high");
        errors.GetProperty("page")[0].GetString().ShouldBe("must be a whole number");
    }
}
