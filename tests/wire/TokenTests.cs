using System.Net;
using System.Net.Http.Headers;
using System.Text;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using Shouldly;

namespace Grapevine.WireTests;

/// <summary>
/// The server's tokens against a library that is not ours: what one of them writes the other
/// has to read, with one key between them.
/// </summary>
public class TokenTests
{
    private const string Key = "a key the wire tests share with the server: 32 bytes and more";
    private const string OtherKey = "another key, which the server was never told of: 32 bytes+";
    private const string Issuer = "https://grapevine.test";
    private const string Audience = "wire-tests";

    private static async Task<ServerFixture> StartAsync(CancellationToken cancellationToken) =>
        await ServerFixture.StartAsync(
            cancellationToken, ("auth.tokenKey", Key), ("auth.issuer", Issuer), ("auth.audience", Audience));

    private static SigningCredentials SignedWith(string key) =>
        new(new SymmetricSecurityKey(Encoding.UTF8.GetBytes(key)), SecurityAlgorithms.HmacSha256);

    private static TokenValidationParameters CheckedWith(string key) => new()
    {
        IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(key)),
        ValidAlgorithms = [SecurityAlgorithms.HmacSha256],
        ValidIssuer = Issuer,
        ValidAudience = Audience,
        ValidateIssuerSigningKey = true,
        ValidateIssuer = true,
        ValidateAudience = true,
        ValidateLifetime = true,
        RequireExpirationTime = true,
        RequireSignedTokens = true,
    };

    /// <summary>A token as the library writes it, for grace, with these roles as a list.</summary>
    private static string Issue(string key, string audience, DateTime notBefore, DateTime expires, params string[] roles) =>
        new JsonWebTokenHandler().CreateToken(new SecurityTokenDescriptor
        {
            Issuer = Issuer,
            Audience = audience,
            NotBefore = notBefore,
            IssuedAt = notBefore,
            Expires = expires,
            Claims = new Dictionary<string, object> { ["sub"] = "grace", ["roles"] = roles },
            SigningCredentials = SignedWith(key),
        });

    private static async Task<HttpResponseMessage> AskAsync(
        HttpClient client, string path, string token, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return await client.SendAsync(request, cancellationToken);
    }

    [Fact(DisplayName = "A token that the server issues is taken by .NET's JWT library: its signature, its lifetime, its issuer and its audience, and not with another key", Timeout = 120_000)]
    public async Task A_token_the_server_issues_holds_for_another_library()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await StartAsync(cancellationToken);
        using var client = server.CreateClient();
        var handler = new JsonWebTokenHandler();

        var token = await client.GetStringAsync("guarded/issue?sub=ada&roles=admin%20editor&scope=todos.write", cancellationToken);
        var held = await handler.ValidateTokenAsync(token, CheckedWith(Key));
        var refused = await handler.ValidateTokenAsync(token, CheckedWith(OtherKey));

        held.IsValid.ShouldBeTrue(held.Exception?.ToString());
        var read = held.SecurityToken.ShouldBeOfType<JsonWebToken>();
        read.Alg.ShouldBe(SecurityAlgorithms.HmacSha256);
        read.Typ.ShouldBe("JWT");
        read.Subject.ShouldBe("ada");
        read.Issuer.ShouldBe(Issuer);
        read.Audiences.ShouldBe([Audience]);
        read.GetClaim("roles").Value.ShouldBe("admin editor");
        read.GetClaim("scope").Value.ShouldBe("todos.write");
        // An hour, as auth.tokenSeconds has it unless it is set.
        (read.ValidTo - read.IssuedAt).ShouldBe(TimeSpan.FromHours(1));
        refused.IsValid.ShouldBeFalse();
        refused.Exception.ShouldBeAssignableTo<SecurityTokenInvalidSignatureException>();
    }

    [Fact(DisplayName = "A token that .NET's JWT library issues with the server's key is taken by a guarded route, with its roles as a list", Timeout = 120_000)]
    public async Task A_token_another_library_issues_is_taken()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await StartAsync(cancellationToken);
        using var client = server.CreateClient();
        var now = DateTime.UtcNow;
        var token = Issue(Key, Audience, now.AddMinutes(-1), now.AddMinutes(5), "editor", "admin");

        using var admin = await AskAsync(client, "guarded/admin", token, cancellationToken);
        using var write = await AskAsync(client, "guarded/write", token, cancellationToken);

        admin.StatusCode.ShouldBe(HttpStatusCode.OK);
        var told = await admin.Content.ReadAsStringAsync(cancellationToken);
        told.ShouldContain("subject=grace\n");
        told.ShouldContain("roles=editor admin\n");
        admin.Headers.Vary.ShouldContain("Authorization");
        // It holds, and has no scope: bringing it again will not help.
        write.StatusCode.ShouldBe(HttpStatusCode.Forbidden);
        write.Headers.WwwAuthenticate.ShouldHaveSingleItem().Parameter.ShouldBe("error=\"insufficient_scope\"");
    }

    [Theory(DisplayName = "A token that .NET's JWT library issues and that does not hold is answered 401, with the reason", Timeout = 120_000)]
    [InlineData("another key", "the token's signature is not ours")]
    [InlineData("expired", "the token has expired")]
    [InlineData("not yet", "the token is not good yet")]
    [InlineData("another audience", "the token is for another audience")]
    public async Task A_token_that_does_not_hold_is_refused(string what, string reason)
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await StartAsync(cancellationToken);
        using var client = server.CreateClient();
        var now = DateTime.UtcNow;
        var token = what switch
        {
            "another key" => Issue(OtherKey, Audience, now.AddMinutes(-1), now.AddMinutes(5), "admin"),
            "expired" => Issue(Key, Audience, now.AddMinutes(-30), now.AddMinutes(-20), "admin"),
            "not yet" => Issue(Key, Audience, now.AddMinutes(20), now.AddMinutes(30), "admin"),
            _ => Issue(Key, "someone-else", now.AddMinutes(-1), now.AddMinutes(5), "admin"),
        };

        using var response = await AskAsync(client, "guarded/admin", token, cancellationToken);

        response.StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
        response.Headers.WwwAuthenticate.ShouldHaveSingleItem().Parameter
            .ShouldBe($"error=\"invalid_token\", error_description=\"{reason}\"");
        response.Headers.CacheControl.ShouldNotBeNull().NoStore.ShouldBeTrue();
        response.Content.Headers.ContentType.ShouldNotBeNull().MediaType.ShouldBe("application/problem+json");
        (await response.Content.ReadAsStringAsync(cancellationToken)).ShouldContain($"\"detail\":\"The token is not taken: {reason}\"");
    }

    // A tenant's own role called "billing admin" is not the role admin. The library writes a
    // list of roles as a JSON array, and an item of it is one name, whole.
    [Fact(DisplayName = "A role in a list that has a space in it is not the roles it is made of, and is not told to the handler", Timeout = 120_000)]
    public async Task A_role_with_a_space_in_it_is_no_role()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await StartAsync(cancellationToken);
        using var client = server.CreateClient();
        var now = DateTime.UtcNow;
        var token = Issue(Key, Audience, now.AddMinutes(-1), now.AddMinutes(5), "not admin", "billing admin", "editor");

        using var admin = await AskAsync(client, "guarded/admin", token, cancellationToken);
        using var open = await AskAsync(client, "guarded/open", token, cancellationToken);

        admin.StatusCode.ShouldBe(HttpStatusCode.Forbidden);
        admin.Headers.WwwAuthenticate.ShouldHaveSingleItem().Parameter.ShouldBe("error=\"insufficient_scope\"");
        open.StatusCode.ShouldBe(HttpStatusCode.OK);
        (await open.Content.ReadAsStringAsync(cancellationToken)).ShouldContain("roles=editor\n");
    }

    // The diagnostic app has a layer behind its guard that answers /guarded/alias and
    // /guarded/carried as /guarded/admin, with a request of its own making. The guard let the
    // first request through to a path that asks for nothing, which says nothing of the second.
    [Fact(DisplayName = "A request that a layer behind the guard makes for a guarded route is held to the guard, by the token it carries", Timeout = 120_000)]
    public async Task A_request_a_layer_hands_on_is_held_to_the_guard()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await StartAsync(cancellationToken);
        using var client = server.CreateClient();
        var now = DateTime.UtcNow;
        var admin = Issue(Key, Audience, now.AddMinutes(-1), now.AddMinutes(5), "admin");
        var nobody = Issue(Key, Audience, now.AddMinutes(-1), now.AddMinutes(5));

        using var bare = await client.GetAsync("guarded/alias", cancellationToken);
        using var notCarried = await AskAsync(client, "guarded/alias", admin, cancellationToken);
        using var carried = await AskAsync(client, "guarded/carried", admin, cancellationToken);
        using var lacking = await AskAsync(client, "guarded/carried", nobody, cancellationToken);
        using var carriedNothing = await client.GetAsync("guarded/carried", cancellationToken);

        bare.StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
        bare.Headers.WwwAuthenticate.ShouldHaveSingleItem().ToString().ShouldBe("Bearer");
        // The layer made a request without the token: the first request's is not the second's.
        notCarried.StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
        notCarried.Headers.WwwAuthenticate.ShouldHaveSingleItem().ToString().ShouldBe("Bearer");
        carried.StatusCode.ShouldBe(HttpStatusCode.OK);
        (await carried.Content.ReadAsStringAsync(cancellationToken)).ShouldContain("subject=grace\nroles=admin\n");
        carried.Headers.Vary.ShouldContain("Authorization");
        lacking.StatusCode.ShouldBe(HttpStatusCode.Forbidden);
        carriedNothing.StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
    }

    // Without a signature such a token is refused for its shape, before its header is read: a
    // token has three parts. With one, for what its header says.
    [Theory(DisplayName = "A token made by hand whose header says that it is not signed is answered 401, with a signature or without", Timeout = 120_000)]
    [InlineData("", "the token is not three parts with dots between")]
    [InlineData("c2ln", "the token is not signed with HS256")]
    public async Task A_token_that_says_none_is_refused(string signature, string reason)
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await StartAsync(cancellationToken);
        using var client = server.CreateClient();
        var expires = DateTimeOffset.UtcNow.AddMinutes(5).ToUnixTimeSeconds();
        var header = Base64UrlEncoder.Encode("""{"alg":"none","typ":"JWT"}""");
        var claims = Base64UrlEncoder.Encode($$"""{"sub":"mallory","roles":"admin","iss":"{{Issuer}}","aud":"{{Audience}}","exp":{{expires}}}""");

        using var response = await AskAsync(client, "guarded/admin", $"{header}.{claims}.{signature}", cancellationToken);
        using var open = await AskAsync(client, "guarded/open", $"{header}.{claims}.{signature}", cancellationToken);

        response.StatusCode.ShouldBe(HttpStatusCode.Unauthorized);
        response.Headers.WwwAuthenticate.ShouldHaveSingleItem().Parameter
            .ShouldBe($"error=\"invalid_token\", error_description=\"{reason}\"");
        // An open route answers, and is told nothing of who such a token says it is.
        open.StatusCode.ShouldBe(HttpStatusCode.OK);
        (await open.Content.ReadAsStringAsync(cancellationToken)).ShouldStartWith("subject=\n");
    }
}
