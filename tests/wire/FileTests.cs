using System.Net;
using System.Net.Http.Headers;
using Shouldly;

namespace Grapevine.WireTests;

public class FileTests
{
    private const string Served = "packages/grapevine/tests/unit/files/served/";

    [Fact(DisplayName = "A file is served with the type of its name, its length and its bytes", Timeout = 120_000)]
    public async Task A_file_is_served()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = new HttpClient { BaseAddress = server.BaseAddress };

        using var response = await client.GetAsync($"file?path={Served}site/style.css", cancellationToken);

        response.StatusCode.ShouldBe(HttpStatusCode.OK);
        response.Content.Headers.ContentType.ShouldNotBeNull().ToString().ShouldBe("text/css; charset=utf-8");
        response.Content.Headers.ContentLength.ShouldBe(23);
        response.Headers.AcceptRanges.ShouldContain("bytes");
        (await response.Content.ReadAsStringAsync(cancellationToken)).ShouldBe("h1 { color: #6b2d5c; }\n");
    }

    [Fact(DisplayName = "A range of a file is a 206 with that part, and a second request with the first one's tag is a 304", Timeout = 120_000)]
    public async Task A_part_and_then_nothing()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = new HttpClient { BaseAddress = server.BaseAddress };
        using var ranged = new HttpRequestMessage(HttpMethod.Get, $"file?path={Served}a.txt");
        ranged.Headers.Range = new RangeHeaderValue(2, 5);

        using var part = await client.SendAsync(ranged, cancellationToken);
        var tag = part.Headers.ETag.ShouldNotBeNull();
        using var again = new HttpRequestMessage(HttpMethod.Get, $"file?path={Served}a.txt");
        again.Headers.IfNoneMatch.Add(tag);
        using var unchanged = await client.SendAsync(again, cancellationToken);

        part.StatusCode.ShouldBe(HttpStatusCode.PartialContent);
        part.Content.Headers.ContentRange.ShouldNotBeNull().ToString().ShouldBe("bytes 2-5/26");
        (await part.Content.ReadAsStringAsync(cancellationToken)).ShouldBe("cdef");
        tag.IsWeak.ShouldBeFalse();
        unchanged.StatusCode.ShouldBe(HttpStatusCode.NotModified);
        (await unchanged.Content.ReadAsByteArrayAsync(cancellationToken)).ShouldBeEmpty();
    }

    [Fact(DisplayName = "A file of 50 MB arrives whole, and the server does not hold it in memory to send it", Timeout = 300_000)]
    public async Task A_large_file_is_not_held_in_memory()
    {
        const int size = 50 * 1024 * 1024;
        var cancellationToken = TestContext.Current.CancellationToken;
        var local = Path.Combine(Path.GetTempPath(), $"grapevine-large-{Guid.NewGuid():N}.bin");
        try
        {
            var pattern = new byte[1024 * 1024];
            for (var index = 0; index < pattern.Length; index++)
            {
                pattern[index] = (byte)(index % 251);
            }

            await using (var file = File.Create(local))
            {
                for (var megabyte = 0; megabyte < size / pattern.Length; megabyte++)
                {
                    await file.WriteAsync(pattern, cancellationToken);
                }
            }

            await using var server = await ServerFixture.StartWithFileAsync(cancellationToken, local, "/tmp/served/large.bin");
            using var client = new HttpClient { BaseAddress = server.BaseAddress };
            // Once before the measurement, so that what the first request of any kind costs is not counted.
            (await client.GetStringAsync("", cancellationToken)).ShouldBe("ok");
            var before = await server.PeakMemoryKilobytesAsync(cancellationToken);

            using var response = await client.GetAsync("file?path=/tmp/served/large.bin", HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            await using var body = await response.Content.ReadAsStreamAsync(cancellationToken);
            var buffer = new byte[pattern.Length];
            long received = 0;
            var intact = true;
            while (true)
            {
                var read = await body.ReadAsync(buffer, cancellationToken);
                if (read == 0)
                {
                    break;
                }

                for (var index = 0; index < read; index++)
                {
                    intact &= buffer[index] == (byte)((received + index) % pattern.Length % 251);
                }

                received += read;
            }

            var after = await server.PeakMemoryKilobytesAsync(cancellationToken);

            response.StatusCode.ShouldBe(HttpStatusCode.OK);
            response.Content.Headers.ContentLength.ShouldBe(size);
            received.ShouldBe(size);
            intact.ShouldBeTrue();
            // The most the server has ever held. Had it read the file whole, that would be 50 MB more.
            (after - before).ShouldBeLessThan(8 * 1024);
        }
        finally
        {
            File.Delete(local);
        }
    }

    [Fact(DisplayName = "A name that a client gives is looked for under the directory and nowhere else", Timeout = 120_000)]
    public async Task A_name_cannot_lead_out_of_the_directory()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = new HttpClient { BaseAddress = server.BaseAddress };

        var inside = await client.GetStringAsync("files-by-name/a.txt", cancellationToken);
        using var escaped = await client.GetAsync("files-by-name/..%2F..%2F..%2F..%2F..%2F..%2Fetc%2Fpasswd", cancellationToken);
        using var beside = await client.GetAsync("files-by-name/..%2Foutside%2Fsecret.txt", cancellationToken);
        using var linked = await client.GetAsync("under/link-out.txt", cancellationToken);
        using var hidden = await client.GetAsync("under/.env", cancellationToken);

        inside.ShouldBe("abcdefghijklmnopqrstuvwxyz");
        escaped.StatusCode.ShouldBe(HttpStatusCode.NotFound);
        (await escaped.Content.ReadAsStringAsync(cancellationToken)).ShouldNotContain("root:");
        beside.StatusCode.ShouldBe(HttpStatusCode.NotFound);
        (await beside.Content.ReadAsStringAsync(cancellationToken)).ShouldNotContain("top secret");
        linked.StatusCode.ShouldBe(HttpStatusCode.NotFound);
        hidden.StatusCode.ShouldBe(HttpStatusCode.NotFound);
    }

    [Fact(DisplayName = "A page, its stylesheet and its script come from a static directory, each with its type, and a client that asks again is told it has them", Timeout = 120_000)]
    public async Task A_static_site_is_served()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var handler = new HttpClientHandler { AllowAutoRedirect = false };
        using var client = new HttpClient(handler) { BaseAddress = server.BaseAddress };

        using var bare = await client.GetAsync("site", cancellationToken);
        using var page = await client.GetAsync("site/", cancellationToken);
        using var sheet = await client.GetAsync("site/style.css", cancellationToken);
        using var script = await client.GetAsync("site/app.js", cancellationToken);
        using var again = new HttpRequestMessage(HttpMethod.Get, "site/style.css");
        again.Headers.IfNoneMatch.Add(sheet.Headers.ETag.ShouldNotBeNull());
        using var unchanged = await client.SendAsync(again, cancellationToken);
        using var ranged = new HttpRequestMessage(HttpMethod.Get, "site/app.js");
        ranged.Headers.Range = new RangeHeaderValue(0, 7);
        using var part = await client.SendAsync(ranged, cancellationToken);

        bare.StatusCode.ShouldBe(HttpStatusCode.MovedPermanently);
        bare.Headers.Location.ShouldNotBeNull().OriginalString.ShouldBe("/site/");
        page.StatusCode.ShouldBe(HttpStatusCode.OK);
        page.Content.Headers.ContentType.ShouldNotBeNull().ToString().ShouldBe("text/html; charset=utf-8");
        (await page.Content.ReadAsStringAsync(cancellationToken)).ShouldContain("<h1>Served by Grapevine</h1>");
        sheet.Content.Headers.ContentType.ShouldNotBeNull().ToString().ShouldBe("text/css; charset=utf-8");
        sheet.Headers.CacheControl.ShouldNotBeNull().ToString().ShouldBe("public, max-age=0");
        script.Content.Headers.ContentType.ShouldNotBeNull().ToString().ShouldBe("text/javascript; charset=utf-8");
        (await script.Content.ReadAsStringAsync(cancellationToken)).ShouldBe("document.title = \"Grapevine 🍇\";\n");
        unchanged.StatusCode.ShouldBe(HttpStatusCode.NotModified);
        part.StatusCode.ShouldBe(HttpStatusCode.PartialContent);
        (await part.Content.ReadAsStringAsync(cancellationToken)).ShouldBe("document");
    }

    [Fact(DisplayName = "A static directory serves nothing that is hidden in it or linked out of it", Timeout = 120_000)]
    public async Task A_static_directory_keeps_to_itself()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        await using var server = await ServerFixture.StartAsync(cancellationToken);
        using var client = new HttpClient { BaseAddress = server.BaseAddress };

        using var served = await client.GetAsync("assets/a.txt", cancellationToken);
        using var hidden = await client.GetAsync("assets/.env", cancellationToken);
        using var linked = await client.GetAsync("assets/link-out.txt", cancellationToken);
        using var through = await client.GetAsync("assets/link-dir/secret.txt", cancellationToken);
        using var escaped = await client.GetAsync("assets/..%2Foutside%2Fsecret.txt", cancellationToken);

        served.StatusCode.ShouldBe(HttpStatusCode.OK);
        served.Headers.CacheControl.ShouldNotBeNull().ToString().ShouldBe("public, max-age=3600");
        hidden.StatusCode.ShouldBe(HttpStatusCode.NotFound);
        linked.StatusCode.ShouldBe(HttpStatusCode.NotFound);
        through.StatusCode.ShouldBe(HttpStatusCode.NotFound);
        escaped.StatusCode.ShouldBe(HttpStatusCode.NotFound);
    }
}
