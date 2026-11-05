using System.Text.Json;

namespace WnacgDownloader.Core;

public static class SettingsStore
{
    private static readonly string Dir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "WnacgDownloader"
    );

    private static readonly string FilePath = Path.Combine(Dir, "settings.json");

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                var json = File.ReadAllText(FilePath);
                var settings = JsonSerializer.Deserialize<AppSettings>(json);
                if (settings != null)
                {
                    settings.DownloadDirectory = Expand(settings.DownloadDirectory);
                    return settings;
                }
            }
        }
        catch
        {
            // Corrupt settings should never prevent the app from starting.
        }

        return new AppSettings();
    }

    public static void Save(AppSettings settings)
    {
        Directory.CreateDirectory(Dir);
        var json = JsonSerializer.Serialize(
            settings,
            new JsonSerializerOptions { WriteIndented = true }
        );
        File.WriteAllText(FilePath, json);
    }

    public static string Expand(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                "Downloads",
                "wnacg"
            );
        }

        var expanded = Environment.ExpandEnvironmentVariables(path.Trim());
        try
        {
            expanded = Path.GetFullPath(expanded);
        }
        catch
        {
            // Keep the original string; the settings page validates it.
        }

        return expanded;
    }
}
