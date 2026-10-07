// The same Todo API as app/*.🍇, written as an idiomatic ASP.NET Core minimal API.
// Kept behaviourally parallel so the two can be compared line for line and token for token.
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddSingleton<TodoStore>();
var app = builder.Build();

// Middleware runs in registration order, wrapping everything after it.
app.Use(async (ctx, next) =>
{
    await next();
    Console.WriteLine($"  {ctx.Request.Method} {ctx.Request.Path} → {ctx.Response.StatusCode}");
});

app.Use(async (ctx, next) =>
{
    ctx.Response.OnStarting(() =>
    {
        ctx.Response.Headers["X-Powered-By"] = "ASP.NET";
        return Task.CompletedTask;
    });
    await next();
});

app.Use(async (ctx, next) =>
{
    if (ctx.Request.Path.StartsWithSegments("/admin"))
    {
        if (ctx.Request.Headers["x-api-key"] != "vineyard")
        {
            await Problem(401, "Missing or invalid x-api-key").ExecuteAsync(ctx);
            return;
        }
        ctx.Items["role"] = "admin";
    }
    await next();
});

// Minimal-API style routes.
app.MapGet("/", () => "Hello from ASP.NET");

app.MapGet("/hello/{name}", (string name, string? greeting) =>
    Results.Json(new { message = $"{greeting ?? "Hello"}, {name}!" }));

app.MapPost("/echo", async (HttpRequest request) =>
    Results.Text(await new StreamReader(request.Body).ReadToEndAsync(), "text/plain"));

// Controller-style group with an injected service.
var todos = app.MapGroup("/todos");

todos.MapGet("", (TodoStore store, bool? done) =>
    Results.Ok(store.All().Where(t => done is null || t.Done == done)));

todos.MapGet("/{id}", (int id, TodoStore store) =>
    store.Find(id) is { } todo ? Results.Ok(todo) : Problem(404, $"Todo {id} not found"));

todos.MapPost("", (CreateTodo body, TodoStore store) =>
{
    if (string.IsNullOrWhiteSpace(body.Title))
        return Problem(400, "Expected a JSON body with a non-empty \"title\"");
    var todo = store.Add(body.Title.Trim());
    return Results.Created($"/todos/{todo.Id}", todo);
});

todos.MapPut("/{id}", (int id, UpdateTodo body, TodoStore store) =>
{
    if (store.Find(id) is not { } todo) return Problem(404, $"Todo {id} not found");
    if (body.Title is not null) todo.Title = body.Title;
    if (body.Done is { } done) todo.Done = done;
    return Results.Ok(todo);
});

todos.MapDelete("/{id}", (int id, TodoStore store) =>
    store.Remove(id) ? Results.NoContent() : Problem(404, $"Todo {id} not found"));

// Route group behind the API-key middleware.
var admin = app.MapGroup("/admin");

admin.MapGet("/stats", (HttpContext ctx, TodoStore store) =>
{
    var all = store.All();
    return Results.Json(new { total = all.Count, open = all.Count(t => !t.Done), role = ctx.Items["role"] as string });
});

app.Run($"http://localhost:{Environment.GetEnvironmentVariable("PORT") ?? "8080"}");

static IResult Problem(int status, string error) =>
    Results.Json(new { status, error }, statusCode: status, contentType: "application/problem+json; charset=utf-8");

record CreateTodo(string? Title);
record UpdateTodo(string? Title, bool? Done);

class Todo
{
    public int Id { get; init; }
    public string Title { get; set; } = "";
    public bool Done { get; set; }
}

// In-memory store. Kestrel serves requests concurrently, so access is locked;
// Grapevine's accept loop is single-threaded and doesn't need this.
class TodoStore
{
    private readonly List<Todo> _todos = [];
    private int _nextId = 1;

    public List<Todo> All() { lock (_todos) return [.. _todos]; }

    public Todo? Find(int id) { lock (_todos) return _todos.FirstOrDefault(t => t.Id == id); }

    public Todo Add(string title)
    {
        lock (_todos)
        {
            var todo = new Todo { Id = _nextId++, Title = title };
            _todos.Add(todo);
            return todo;
        }
    }

    public bool Remove(int id) { lock (_todos) return _todos.RemoveAll(t => t.Id == id) > 0; }
}
