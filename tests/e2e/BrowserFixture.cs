namespace Grapevine.E2E;

/// <summary>
/// One headless Chromium for the whole run. A test opens a context of its own in it, so that
/// no test sees what another left in the browser.
/// </summary>
public sealed class BrowserFixture : IAsyncLifetime
{
    private IPlaywright? _playwright;
    private IBrowser? _browser;

    public async ValueTask InitializeAsync()
    {
        // Downloads the browser this version of Playwright wants when it is not there yet, and
        // does nothing when it is.
        var exitCode = Microsoft.Playwright.Program.Main(["install", "chromium"]);
        if (exitCode != 0)
        {
            throw new InvalidOperationException($"Installing Chromium for Playwright failed with exit code {exitCode}.");
        }

        _playwright = await Playwright.CreateAsync();
        _browser = await _playwright.Chromium.LaunchAsync();
    }

    public async Task<IBrowserContext> NewContextAsync()
    {
        var browser = _browser ?? throw new InvalidOperationException("The browser was not started.");
        return await browser.NewContextAsync();
    }

    public async ValueTask DisposeAsync()
    {
        if (_browser is not null)
        {
            await _browser.DisposeAsync();
        }

        _playwright?.Dispose();
    }
}
