using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.OpenApi;
using Shouldly;

namespace Grapevine.WireTests;

/// <summary>
/// The app's description of itself, read by a reader that is not ours: .NET's own OpenAPI
/// library has to take the document as it is served, and what the document says of a body
/// has to be what the server holds a body to.
/// </summary>
public class DocumentTests
{
    private static async Task<string> DocumentAsync(HttpClient client, CancellationToken cancellationToken)
    {
        using var response = await client.GetAsync("openapi.json", cancellationToken);
        response.StatusCode.ShouldBe(HttpStatusCode.OK);
        response.Content.Headers.ContentType.ShouldNotBeNull().MediaType.ShouldBe("application/json");
        return await response.Content.ReadAsStringAsync(cancellationToken);
    }

    [Fact(DisplayName = ".NET's OpenAPI reader takes the document as OpenAPI 3.1, without an error or a warning", Timeout = 120_000)]
    public async Task The_document_is_read_without_a_complaint()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = server.CreateClient();

        var text = await DocumentAsync(client, cancellationToken);
        var read = OpenApiDocument.Parse(text, "json");

        var diagnostic = read.Diagnostic.ShouldNotBeNull();
        diagnostic.Errors.Select(error => $"{error.Pointer}: {error.Message}").ShouldBeEmpty();
        diagnostic.Warnings.Select(warning => $"{warning.Pointer}: {warning.Message}").ShouldBeEmpty();
        diagnostic.SpecificationVersion.ShouldBe(OpenApiSpecVersion.OpenApi3_1);
        var document = read.Document.ShouldNotBeNull();
        document.Info.Title.ShouldBe("The diagnostic app");
        document.Info.Version.ShouldBe("1.0.0");
    }

    [Fact(DisplayName = "What .NET's OpenAPI reader finds in the document is what the app declared: the paths, a body's schema, a query's parameters and the scheme a token comes by", Timeout = 120_000)]
    public async Task The_document_holds_what_the_app_declared()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = server.CreateClient();

        var text = await DocumentAsync(client, cancellationToken);
        var document = OpenApiDocument.Parse(text, "json").Document.ShouldNotBeNull();
        var shaped = document.Paths["/shaped"].Operations.ShouldNotBeNull();
        var post = shaped[HttpMethod.Post];
        var get = shaped[HttpMethod.Get];
        var schemas = document.Components.ShouldNotBeNull().Schemas.ShouldNotBeNull();
        var body = schemas["Shaped"];
        var properties = body.Properties.ShouldNotBeNull();

        document.Paths.Keys.ShouldContain("/who");
        document.Paths.Keys.ShouldContain("/bind/{id}");
        document.Paths.Keys.ShouldContain("/guarded/admin");
        document.Paths.Keys.ShouldNotContain("/openapi.json");
        post.OperationId.ShouldBe("postShaped");
        post.Summary.ShouldBe("Reads a body by a shape");
        post.RequestBody.ShouldNotBeNull().Required.ShouldBeTrue();
        post.RequestBody.Content.ShouldNotBeNull().Keys.ShouldBe(["application/json"]);
        post.Responses.ShouldNotBeNull().Keys.ShouldBe(["200", "400", "415", "default"]);
        get.Parameters.ShouldNotBeNull().Select(parameter => $"{parameter.Name} in {parameter.In} required {parameter.Required}")
            .ShouldBe(["page in Query required False", "sort in Query required False"]);
        properties.Keys.ShouldBe(["title", "count", "rate", "level", "done"]);
        body.Required.ShouldNotBeNull().ShouldBe(["title", "count", "rate", "level"], ignoreOrder: true);
        properties["title"].MaxLength.ShouldBe(20);
        properties["title"].MinLength.ShouldBe(1);
        properties["level"].Enum.ShouldNotBeNull().Select(choice => choice.GetValue<string>()).ShouldBe(["low", "high"]);
        schemas.Keys.ShouldContain("Problem");
        // A route that asks for a role names the scheme, and can be refused two ways.
        var admin = document.Paths["/guarded/admin"].Operations.ShouldNotBeNull()[HttpMethod.Get];
        admin.Security.ShouldNotBeNull().ShouldHaveSingleItem();
        admin.Responses.ShouldNotBeNull().Keys.ShouldContain("401");
        admin.Responses.Keys.ShouldContain("403");
        var open = document.Paths["/guarded/open"].Operations.ShouldNotBeNull()[HttpMethod.Get];
        (open.Security ?? []).ShouldBeEmpty();
        open.Responses.ShouldNotBeNull().Keys.ShouldNotContain("401");
        var scheme = document.Components.SecuritySchemes.ShouldNotBeNull()["bearer"];
        scheme.Type.ShouldBe(SecuritySchemeType.Http);
        scheme.Scheme.ShouldBe("bearer");
        scheme.BearerFormat.ShouldBe("JWT");
    }

    [Fact(DisplayName = ".NET's OpenAPI reader takes the sample's document without an error or a warning, and finds in it the paths, the schemas and the scheme the sample declared", Timeout = 120_000)]
    public async Task The_samples_document_is_read()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartSampleAsync(cancellationToken);
        using var client = server.CreateClient();

        var text = await DocumentAsync(client, cancellationToken);
        var read = OpenApiDocument.Parse(text, "json");

        var diagnostic = read.Diagnostic.ShouldNotBeNull();
        diagnostic.Errors.Select(error => $"{error.Pointer}: {error.Message}").ShouldBeEmpty();
        diagnostic.Warnings.Select(warning => $"{warning.Pointer}: {warning.Message}").ShouldBeEmpty();
        diagnostic.SpecificationVersion.ShouldBe(OpenApiSpecVersion.OpenApi3_1);
        var document = read.Document.ShouldNotBeNull();
        document.Info.Title.ShouldBe("Todo API");
        document.Paths.Keys.ShouldBe(["/login", "/config.json", "/health", "/hello/{name}", "/echo", "/todos", "/todos/{id}", "/admin/stats"]);
        var components = document.Components.ShouldNotBeNull();
        var schemas = components.Schemas.ShouldNotBeNull();
        schemas.Keys.ShouldBe(["SignIn", "Token", "Health", "Todo", "NewTodo", "TodoChange", "Numbers", "Problem"]);
        components.SecuritySchemes.ShouldNotBeNull().Keys.ShouldBe(["bearer"]);
        // Who may call: the numbers ask for a token and a role, and nothing else asks for either.
        var numbers = document.Paths["/admin/stats"].Operations.ShouldNotBeNull()[HttpMethod.Get];
        numbers.Security.ShouldNotBeNull().ShouldHaveSingleItem();
        numbers.Responses.ShouldNotBeNull().Keys.ShouldBe(["200", "401", "403", "default"]);
        var guarded = document.Paths
            .SelectMany(path => path.Value.Operations ?? [], (path, operation) => (Path: path.Key, operation.Value.Security))
            .Where(operation => operation.Security is { Count: > 0 })
            .Select(operation => operation.Path);
        guarded.ShouldBe(["/admin/stats"]);
        // What a todo is, as the reader has it: the bound that the sample's binder holds a title to.
        var title = schemas["NewTodo"].Properties.ShouldNotBeNull()["title"];
        title.MinLength.ShouldBe(1);
        title.MaxLength.ShouldBe(200);
        schemas["Todo"].Properties.ShouldNotBeNull().Keys.ShouldBe(["id", "title", "done"]);
        var todos = document.Paths["/todos"].Operations.ShouldNotBeNull();
        todos.Keys.ShouldBe([HttpMethod.Get, HttpMethod.Post], ignoreOrder: true);
        todos[HttpMethod.Get].Parameters.ShouldNotBeNull().Select(parameter => $"{parameter.Name} in {parameter.In} required {parameter.Required}")
            .ShouldBe(["done in Query required False"]);
        document.Paths["/todos/{id}"].Operations.ShouldNotBeNull().Keys
            .ShouldBe([HttpMethod.Get, HttpMethod.Put, HttpMethod.Delete], ignoreOrder: true);
    }

    [Fact(DisplayName = "The bounds the document gives for a body are the bounds the server holds it to: read from the document, and tried on both sides of each", Timeout = 120_000)]
    public async Task The_documents_bounds_are_the_servers()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = server.CreateClient();
        using var document = JsonDocument.Parse(await DocumentAsync(client, cancellationToken));
        var properties = document.RootElement.GetProperty("components").GetProperty("schemas").GetProperty("Shaped").GetProperty("properties");
        var longest = properties.GetProperty("title").GetProperty("maxLength").GetInt32();
        var fewest = properties.GetProperty("count").GetProperty("minimum").GetInt32();
        var most = properties.GetProperty("count").GetProperty("maximum").GetInt32();
        var highest = properties.GetProperty("rate").GetProperty("maximum").GetDouble();
        var levels = properties.GetProperty("level").GetProperty("enum").EnumerateArray().Select(level => level.GetString()).ToArray();

        async Task<(HttpStatusCode Status, string Body)> PostAsync(object body)
        {
            using var response = await client.PostAsJsonAsync("shaped", body, cancellationToken);
            return (response.StatusCode, await response.Content.ReadAsStringAsync(cancellationToken));
        }

        var atTheBounds = await PostAsync(new { title = new string('x', longest), count = most, rate = highest, level = levels[^1] });
        var atTheLowest = await PostAsync(new { title = "x", count = fewest, rate = 0, level = levels[0] });
        var tooLong = await PostAsync(new { title = new string('x', longest + 1), count = most, rate = highest, level = levels[0] });
        var tooFew = await PostAsync(new { title = "x", count = fewest - 1, rate = highest, level = levels[0] });
        var tooMany = await PostAsync(new { title = "x", count = most + 1, rate = highest, level = levels[0] });
        var tooHigh = await PostAsync(new { title = "x", count = most, rate = highest + 0.01, level = levels[0] });
        var noSuchLevel = await PostAsync(new { title = "x", count = most, rate = highest, level = "neither" });
        var nothing = await PostAsync(new { });

        atTheBounds.Status.ShouldBe(HttpStatusCode.OK, atTheBounds.Body);
        atTheLowest.Status.ShouldBe(HttpStatusCode.OK, atTheLowest.Body);
        tooLong.Status.ShouldBe(HttpStatusCode.BadRequest);
        tooLong.Body.ShouldContain($"\"title\":[\"must be at most {longest} characters\"]");
        tooFew.Status.ShouldBe(HttpStatusCode.BadRequest);
        tooFew.Body.ShouldContain($"\"count\":[\"must be between {fewest} and {most}\"]");
        tooMany.Status.ShouldBe(HttpStatusCode.BadRequest);
        tooHigh.Status.ShouldBe(HttpStatusCode.BadRequest);
        tooHigh.Body.ShouldContain("\"rate\":[\"must be between ");
        noSuchLevel.Status.ShouldBe(HttpStatusCode.BadRequest);
        noSuchLevel.Body.ShouldContain($"\"level\":[\"must be one of {string.Join(", ", levels)}\"]");
        // What the schema calls required is what the server calls required.
        nothing.Status.ShouldBe(HttpStatusCode.BadRequest);
        var required = document.RootElement.GetProperty("components").GetProperty("schemas").GetProperty("Shaped").GetProperty("required")
            .EnumerateArray().Select(name => name.GetString()).ToArray();
        foreach (var name in required)
        {
            nothing.Body.ShouldContain($"\"{name}\":[\"is required\"]");
        }

        nothing.Body.ShouldNotContain("\"done\"");
    }

    [Fact(DisplayName = "A title the sample takes is one its own document takes, and one its document takes the sample takes: the lengths and the pattern, tried with white space of every kind", Timeout = 120_000)]
    public async Task What_the_sample_takes_is_what_its_document_says()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartSampleAsync(cancellationToken);
        using var client = server.CreateClient();
        using var document = JsonDocument.Parse(await DocumentAsync(client, cancellationToken));
        var schemas = document.RootElement.GetProperty("components").GetProperty("schemas");
        var asked = schemas.GetProperty("NewTodo").GetProperty("properties").GetProperty("title");
        var answered = schemas.GetProperty("Todo").GetProperty("properties").GetProperty("title");

        // A schema counts a text in characters, which are code points, and finds its pattern anywhere in the text.
        static bool Fits(JsonElement schema, string text)
        {
            var length = text.EnumerateRunes().Count();
            return length >= schema.GetProperty("minLength").GetInt32()
                && length <= schema.GetProperty("maxLength").GetInt32()
                && Regex.IsMatch(text, schema.GetProperty("pattern").GetString().ShouldNotBeNull());
        }

        string[] titles =
        [
            "x", " x ", "", " ", "\t", "\n", "\r", " \t\r\n ",
            // White space that the binder leaves on a text, so that each of these is a title to it.
            "\u00a0", "\u000b", "\u000c", "\u0085", "\u2028", "\u3000", "\ufeff",
            new string('x', 200), new string('x', 201), " " + new string('x', 200) + " ",
            string.Concat(Enumerable.Repeat("\ud83d\ude00", 200)), string.Concat(Enumerable.Repeat("\ud83d\ude00", 201)),
        ];
        var taken = 0;
        foreach (var title in titles)
        {
            var named = $"a title of {title.Length} units that begins {string.Join(' ', title.Take(4).Select(unit => $"U+{(int)unit:X4}"))}";
            using var response = await client.PostAsJsonAsync("todos", new { title }, cancellationToken);
            if (response.StatusCode == HttpStatusCode.Created)
            {
                taken++;
                var made = await response.Content.ReadFromJsonAsync<JsonElement>(cancellationToken);
                Fits(answered, made.GetProperty("title").GetString().ShouldNotBeNull())
                    .ShouldBeTrue($"the sample answered what its document says no Todo is: {named}");
            }
            else
            {
                response.StatusCode.ShouldBe(HttpStatusCode.BadRequest, named);
                Fits(asked, title).ShouldBeFalse($"the sample refused what its document says a NewTodo may be: {named}");
            }
        }

        // Twelve are titles: the letter, the padded ones, the seven kinds of space a binder leaves on, and the two of 200.
        taken.ShouldBe(12);
    }

    [Fact(DisplayName = "A client that has the document is told 304", Timeout = 120_000)]
    public async Task A_client_that_has_the_document_is_told_so()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = server.CreateClient();
        using var first = await client.GetAsync("openapi.json", cancellationToken);
        var tag = first.Headers.ETag.ShouldNotBeNull();

        using var request = new HttpRequestMessage(HttpMethod.Get, "openapi.json");
        request.Headers.IfNoneMatch.Add(tag);
        using var second = await client.SendAsync(request, cancellationToken);

        second.StatusCode.ShouldBe(HttpStatusCode.NotModified);
        (await second.Content.ReadAsByteArrayAsync(cancellationToken)).ShouldBeEmpty();
        first.Headers.CacheControl.ShouldNotBeNull().NoCache.ShouldBeTrue();
    }
}
