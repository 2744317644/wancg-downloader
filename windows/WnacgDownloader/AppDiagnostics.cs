using System.Text;

namespace WnacgDownloader;

/// <summary>
/// Minimal file logger for diagnosing crashes / silent download stops.
/// Logs live under %LOCALAPPDATA%\WnacgDownloader\logs\app.log.
/// </summary>
public static class AppDiagnostics
{
    private static readonly object Gate = new();

    public static string LogPath
    {
        get
        {
            var dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "WnacgDownloader",
                "logs"
            );
            return Path.Combine(dir, "app.log");
        }
    }

    public static void Log(string area, string message)
    {
        try
        {
            lock (Gate)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(LogPath)!);
                if (File.Exists(LogPath) && new FileInfo(LogPath).Length > 2 * 1024 * 1024)
                {
                    File.Move(LogPath, LogPath + ".old", overwrite: true);
                }

                File.AppendAllText(
                    LogPath,
                    $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} [{area}] {message}{Environment.NewLine}",
                    Encoding.UTF8
                );
            }
        }
        catch
        {
            // Logging must never take down the app.
        }
    }

    public static void Exception(string area, Exception ex)
    {
        Log(
            area,
            ex.GetType().FullName + ": " + ex.Message + Environment.NewLine + ex
        );
    }
}
