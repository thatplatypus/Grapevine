// The same Todo sample as samples/todo/*.🍇, written as an ASP.NET Core minimal API is
// written: where the framework has the thing, this uses it. comparison/parity.sh asks both
// programs the same things and compares the answers, and the README lists where they differ.
using System.ComponentModel.DataAnnotations;
using System.Globalization;
using System.Net;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.FileProviders;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;

// Where the program runs is the sample's setting too: a deployment unless it is told that it
// is being tried out.
var environment = Environment.GetEnvironmentVariable("GRAPEVINE_APP_ENVIRONMENT") ?? "Production";
if (environment is not ("Development" or "Production"))
    throw new InvalidOperationException($"app.environment must be Development or Production, got {environment}");
var builder = WebApplication.CreateBuilder(new WebApplicationOptions { Args = args, EnvironmentName = environment });
var development = builder.Environment.IsDevelopment();

// The sample's settings, from the sample's variables: GRAPEVINE_TODO_CAPACITY and the rest.
builder.Configuration.AddEnvironmentVariables("GRAPEVINE_");
var settings = builder.Configuration;
var capacity = settings.GetValue("TODO_CAPACITY", 1000);
var webRoot = Path.GetFullPath(settings["TODO_WEBROOT"] ?? "../../samples/todo/web");
var apiUrl = settings["TODO_APIURL"] ?? "";
var allowedOrigins = (settings["TODO_ALLOWEDORIGINS"] ?? "")
    .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
var adminUser = (settings["TODO_ADMINUSER"] ?? "admin").Trimmed();
var adminPassword = (settings["TODO_ADMINPASSWORD"] ?? "vineyard").Trimmed();
var tokenSeconds = settings.GetValue("AUTH_TOKENSECONDS", 3600);
var leewaySeconds = settings.GetValue("AUTH_LEEWAYSECONDS", 60);
var issuer = settings["AUTH_ISSUER"] ?? "";
var audience = settings["AUTH_AUDIENCE"] ?? "";
var configuredKey = settings["AUTH_TOKENKEY"] ?? "";
var trustedProxies = (settings["SERVER_TRUSTEDPROXIES"] ?? "0").Trim();

// A setting that makes no sense stops the start, as it does in the sample.
if (capacity is < 1 or > 1_000_000) throw new InvalidOperationException("todo.capacity must be 1 to 1000000");
if (adminUser.Length == 0) throw new InvalidOperationException("todo.adminUser is blank: there has to be a name to sign in with");
if (adminPassword.Length == 0) throw new InvalidOperationException("todo.adminPassword is blank: a password of nothing keeps nobody out. Give it one");
if (apiUrl.Length > 0 && !(Uri.TryCreate(apiUrl, UriKind.Absolute, out var api) && api.GetLeftPart(UriPartial.Authority) == apiUrl))
    throw new InvalidOperationException($"todo.apiUrl must be an origin, such as https://api.example.com, and is not: {apiUrl}");
if (!Directory.Exists(webRoot)) throw new InvalidOperationException($"todo.webRoot must be a directory, and is not: {webRoot}");
if (configuredKey.Length > 0 && Encoding.UTF8.GetByteCount(configuredKey) < 32)
    throw new InvalidOperationException("auth.tokenKey is too short to sign with; give it 32 bytes or more");
if (tokenSeconds is < 1 or > 31_536_000) throw new InvalidOperationException("auth.tokenSeconds must be 1 to 31536000");
if (leewaySeconds is < 0 or > 600) throw new InvalidOperationException("auth.leewaySeconds must be 0 to 600");
// Tried out, a server takes the README's password and makes a key for the run. Deployed, it
// does not start with either: anyone has read the one, and the other ends with the run.
if (!development && configuredKey.Length == 0)
    throw new InvalidOperationException("auth.tokenKey is not set: a deployment needs a key that outlasts it");
if (!development && adminPassword == "vineyard")
    throw new InvalidOperationException("todo.adminPassword is the one in the README: a deployment needs its own");

// The server's own proxies: a number of them, or their addresses and networks.
var proxyCount = 0;
var proxyNetworks = new List<System.Net.IPNetwork>();
if (int.TryParse(trustedProxies, NumberStyles.None, CultureInfo.InvariantCulture, out var hops))
{
    if (hops > 16) throw new InvalidOperationException($"server.trustedProxies must be 0 to 16, got {trustedProxies}");
    proxyCount = hops;
}
else
{
    foreach (var entry in trustedProxies.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
    {
        // An address by itself is a network of one. .NET reads a network that is written as one of
        // its hosts as the network; here that is a mistake, as it is in the sample.
        var written = entry.Contains('/') ? entry : entry + (entry.Contains(':') ? "/128" : "/32");
        if (!System.Net.IPNetwork.TryParse(written, out var network) || !IPAddress.Parse(written.Split('/')[0]).Equals(network.BaseAddress))
            throw new InvalidOperationException($"server.trustedProxies names {entry}, which is no address and no network");
        proxyNetworks.Add(network);
    }
    if (proxyNetworks.Count == 0) throw new InvalidOperationException("server.trustedProxies names no proxy");
}

// Without a key, one made for this run: tokens end with it, and no other server takes them.
var key = new SymmetricSecurityKey(configuredKey.Length > 0 ? Encoding.UTF8.GetBytes(configuredKey) : RandomNumberGenerator.GetBytes(32));

builder.WebHost.ConfigureKestrel(kestrel => kestrel.Limits.MaxRequestBodySize = 16 * 1024);
builder.Services.AddSingleton(new TodoStore(capacity));
builder.Services.AddProblemDetails();
builder.Services.AddValidation();
builder.Services.AddOpenApi();
builder.Services.AddHealthChecks();
builder.Services.AddResponseCompression();
builder.Services.AddCors(options => options.AddDefaultPolicy(policy => policy
    .WithOrigins(allowedOrigins)
    .WithMethods("GET", "HEAD", "POST", "PUT", "DELETE")
    .WithHeaders("content-type", "authorization")
    .WithExposedHeaders("X-Request-Id", "Location")
    .SetPreflightMaxAge(TimeSpan.FromMinutes(10))));
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(options =>
{
    options.MapInboundClaims = false;
    options.TokenValidationParameters = new TokenValidationParameters
    {
        IssuerSigningKey = key,
        ValidAlgorithms = [SecurityAlgorithms.HmacSha256],
        ValidateIssuer = issuer.Length > 0,
        ValidIssuer = issuer,
        ValidateAudience = audience.Length > 0,
        ValidAudience = audience,
        RoleClaimType = "roles",
        ClockSkew = TimeSpan.FromSeconds(leewaySeconds),
    };
});
builder.Services.AddAuthorizationBuilder().AddPolicy("admin", policy => policy.RequireRole("admin"));
// Five tries a minute at signing in for each client, and no more: a password is guessed by trying.
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.OnRejected = (rejected, _) =>
    {
        if (rejected.Lease.TryGetMetadata(MetadataName.RetryAfter, out var wait))
            rejected.HttpContext.Response.Headers.RetryAfter = ((int)Math.Ceiling(wait.TotalSeconds)).ToString();
        return ValueTask.CompletedTask;
    };
    options.AddPolicy("sign-in", context => RateLimitPartition.GetFixedWindowLimiter(
        context.Connection.RemoteIpAddress?.ToString() ?? "",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = 5, Window = TimeSpan.FromMinutes(1) }));
});
// Behind proxies of its own the server takes their word for who is calling, and over what.
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    options.KnownIPNetworks.Clear();
    options.KnownProxies.Clear();
    // A number: whoever connects is believed, that many entries deep. Addresses: only what one
    // of them passed on is read, as far as they wrote it.
    options.ForwardLimit = proxyNetworks.Count > 0 ? null : proxyCount;
    foreach (var network in proxyNetworks) options.KnownIPNetworks.Add(network);
});

var app = builder.Build();

if (development && adminPassword == "vineyard")
    app.Logger.LogWarning("todo.adminPassword is the one in the sample's README: anyone who has read it can sign in. Set GRAPEVINE_TODO_ADMINPASSWORD before anyone else can reach this server");
if (development && configuredKey.Length == 0)
    app.Logger.LogWarning("auth.tokenKey is not set: tokens are signed with a key made for this run. They end with it, and no other server takes them");

if (proxyCount > 0 || proxyNetworks.Count > 0) app.UseForwardedHeaders();
app.UseResponseCompression();

// The headers that make a browser careful, a content security policy made for the page, and
// the ID of the request, which the page shows when something is refused. ASP.NET has no
// middleware for these.
var policy = $"default-src 'self'; connect-src 'self'{(apiUrl.Length > 0 ? " " + apiUrl : "")}; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";
app.Use(async (context, next) =>
{
    var headers = context.Response.Headers;
    headers.XContentTypeOptions = "nosniff";
    headers.XFrameOptions = "DENY";
    headers["Referrer-Policy"] = "same-origin";
    headers.ContentSecurityPolicy = policy;
    headers["X-Request-Id"] = context.TraceIdentifier;
    headers.XPoweredBy = "ASP.NET";
    await next(context);
});

app.UseExceptionHandler();
app.UseStatusCodePages();
app.UseCors();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

// The page is the sample's own, served from where the sample keeps it.
var page = new PhysicalFileProvider(webRoot);
app.UseDefaultFiles(new DefaultFilesOptions { FileProvider = page });
app.UseStaticFiles(new StaticFileOptions { FileProvider = page });

app.MapGet("/config.json", (HttpResponse response) =>
{
    response.Headers.CacheControl = "no-store";
    return TypedResults.Json(new { api = apiUrl });
}).WithSummary("Tells the page where the API is").WithTags("The page");

app.MapHealthChecks("/health", new HealthCheckOptions
{
    ResponseWriter = async (context, report) =>
        await context.Response.WriteAsJsonAsync(new { status = report.Status == HealthStatus.Healthy ? "ok" : "failing" }),
});

app.MapGet("/hello/{name}", (string name, string? greeting) =>
        TypedResults.Json(new { message = $"{greeting ?? "Hello"}, {name}!" }))
    .WithSummary("Greets whoever the path names").WithTags("Samples");

app.MapPost("/echo", async (HttpRequest request) =>
    {
        using var reader = new StreamReader(request.Body);
        return TypedResults.Text(await reader.ReadToEndAsync(), "text/plain");
    })
    .WithSummary("Answers with what it was sent").WithTags("Samples");

var todos = app.MapGroup("/todos").WithTags("Todos");

todos.MapGet("", (TodoStore store, bool? done) =>
        TypedResults.Ok(store.All().Where(todo => done is null || todo.Done == done)))
    .WithSummary("Lists the todos");

todos.MapGet("/{id:long}", Results<Ok<Todo>, ProblemHttpResult> (long id, TodoStore store) =>
        store.Find(id) is { } todo ? TypedResults.Ok(todo) : Missing(id))
    .WithSummary("Gives one todo");

todos.MapPost("", Results<Created<Todo>, ProblemHttpResult> (NewTodo body, TodoStore store) =>
        store.Add(body.Title!.Trimmed()) is { } todo
            ? TypedResults.Created($"/todos/{todo.Id}", todo)
            : TypedResults.Problem($"The list is full: it holds {capacity} todos", statusCode: StatusCodes.Status409Conflict))
    .WithSummary("Adds a todo");

todos.MapPut("/{id:long}", Results<Ok<Todo>, ProblemHttpResult> (long id, TodoChange body, TodoStore store) =>
        store.Change(id, body.Title?.Trimmed(), body.Done) is { } todo ? TypedResults.Ok(todo) : Missing(id))
    .WithSummary("Changes a todo's title, whether it is done, or both");

todos.MapDelete("/{id:long}", Results<NoContent, ProblemHttpResult> (long id, TodoStore store) =>
        store.Remove(id) ? TypedResults.NoContent() : Missing(id))
    .WithSummary("Deletes a todo");

// A wrong name and a wrong password are told the same thing and take the same work: each is
// compared by its digest, in constant time, and both are compared whatever the first says.
var userDigest = SHA256.HashData(Encoding.UTF8.GetBytes(adminUser));
var passwordDigest = SHA256.HashData(Encoding.UTF8.GetBytes(adminPassword));
app.MapPost("/login", Results<Ok<Token>, ProblemHttpResult> (SignIn body, HttpResponse response) =>
    {
        response.Headers.CacheControl = "no-store";
        var rightUser = CryptographicOperations.FixedTimeEquals(SHA256.HashData(Encoding.UTF8.GetBytes(body.User!.Trimmed())), userDigest);
        var rightPassword = CryptographicOperations.FixedTimeEquals(SHA256.HashData(Encoding.UTF8.GetBytes(body.Password!.Trimmed())), passwordDigest);
        if (!(rightUser & rightPassword))
        {
            response.Headers.WWWAuthenticate = "Bearer";
            return TypedResults.Problem("The name or the password is not right", statusCode: StatusCodes.Status401Unauthorized);
        }

        var now = DateTime.UtcNow;
        var token = new JsonWebTokenHandler().CreateToken(new SecurityTokenDescriptor
        {
            Claims = new Dictionary<string, object> { ["sub"] = adminUser, ["roles"] = "admin" },
            Issuer = issuer.Length > 0 ? issuer : null,
            Audience = audience.Length > 0 ? audience : null,
            IssuedAt = now,
            Expires = now.AddSeconds(tokenSeconds),
            SigningCredentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256),
        });
        return TypedResults.Ok(new Token(token, tokenSeconds));
    })
    .RequireRateLimiting("sign-in")
    .WithSummary("Signs in: a name and a password for a token").WithTags("Signing in");

app.MapGet("/admin/stats", (ClaimsPrincipal caller, TodoStore store) =>
    {
        var all = store.All();
        return TypedResults.Ok(new Numbers(all.Count, all.Count(todo => !todo.Done), caller.FindFirstValue("roles") ?? ""));
    })
    .RequireAuthorization("admin")
    .WithSummary("The list in numbers").WithTags("Admin");

app.MapOpenApi("/openapi.json");

app.Run($"http://0.0.0.0:{settings["PORT"] ?? "8080"}");

static ProblemHttpResult Missing(long id) =>
    TypedResults.Problem($"Todo {id} not found", statusCode: StatusCodes.Status404NotFound);

public record NewTodo(
    [Required(AllowEmptyStrings = true, ErrorMessage = "is required"), MinLength(1, ErrorMessage = "must not be empty"),
     RegularExpression(Text.NotBlank, ErrorMessage = "must not be empty"), MaxLength(200, ErrorMessage = "must be at most 200 characters")] string? Title);

public record TodoChange(
    [MinLength(1, ErrorMessage = "must not be empty"), RegularExpression(Text.NotBlank, ErrorMessage = "must not be empty"),
     MaxLength(200, ErrorMessage = "must be at most 200 characters")] string? Title = null,
    bool? Done = null);

public record SignIn(
    [Required(AllowEmptyStrings = true, ErrorMessage = "is required"), MaxLength(200, ErrorMessage = "must be at most 200 characters")] string? User,
    [Required(AllowEmptyStrings = true, ErrorMessage = "is required"), MaxLength(200, ErrorMessage = "must be at most 200 characters")] string? Password);

record Token([property: System.Text.Json.Serialization.JsonPropertyName("token")] string Value, int ExpiresIn);

record Numbers(int Total, int Open, string Role);

record Todo(long Id, string Title, bool Done);

// A text is kept without the spaces, tabs and line ends around it, and one of nothing but
// those is no text. The attributes look at a text before the handler takes them off, so
// the second is asked of them in a pattern.
public static class Text
{
    public const string NotBlank = @"(?s).*[^ \t\r\n].*";

    public static string Trimmed(this string text) => text.Trim(' ', '\t', '\r', '\n');
}

// In memory, and asked by many requests at once. A todo never changes once made: a change
// puts a new one in its place.
class TodoStore(int capacity)
{
    private readonly List<Todo> _todos = [];
    private readonly Lock _lock = new();
    private long _nextId = 1;

    public List<Todo> All() { lock (_lock) return [.. _todos]; }

    public Todo? Find(long id) { lock (_lock) return _todos.Find(todo => todo.Id == id); }

    public Todo? Add(string title)
    {
        lock (_lock)
        {
            if (_todos.Count >= capacity) return null;
            var todo = new Todo(_nextId++, title, false);
            _todos.Add(todo);
            return todo;
        }
    }

    public Todo? Change(long id, string? title, bool? done)
    {
        lock (_lock)
        {
            var index = _todos.FindIndex(todo => todo.Id == id);
            if (index < 0) return null;
            var todo = _todos[index];
            return _todos[index] = todo with { Title = title ?? todo.Title, Done = done ?? todo.Done };
        }
    }

    public bool Remove(long id) { lock (_lock) return _todos.RemoveAll(todo => todo.Id == id) > 0; }
}
