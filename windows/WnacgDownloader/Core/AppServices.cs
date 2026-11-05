namespace WnacgDownloader.Core;

public sealed class AppServices
{
    public static AppServices Instance { get; } = new();

    public AppSettings Settings { get; private set; }
    public WnacgClient Client { get; private set; }
    public DownloadService Downloader { get; private set; }

    public event EventHandler? SettingsChanged;

    private AppServices()
    {
        Settings = SettingsStore.Load();
        Client = new WnacgClient(Settings);
        Downloader = new DownloadService(Client);
    }

    public void SaveSettings(AppSettings settings)
    {
        var old = Client;
        Settings = settings;
        SettingsStore.Save(settings);
        Client = new WnacgClient(settings);
        Downloader = new DownloadService(Client);
        old.Dispose();
        SettingsChanged?.Invoke(this, EventArgs.Empty);
    }

    public void ReloadClient()
    {
        var old = Client;
        Client = new WnacgClient(Settings);
        Downloader = new DownloadService(Client);
        old.Dispose();
    }
}
