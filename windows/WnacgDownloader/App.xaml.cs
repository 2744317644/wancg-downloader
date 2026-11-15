using Microsoft.UI.Xaml;

namespace WnacgDownloader;

public partial class App : Application
{
    public static Window? MainWindow { get; private set; }

    public App()
    {
        InitializeComponent();
        AppDiagnostics.Log("app", "App constructed");

        UnhandledException += (_, e) =>
        {
            AppDiagnostics.Exception("xaml-unhandled", e.Exception);
            // A UI event handler throwing should not silently take the whole
            // downloader down; keep the window alive where possible.
            e.Handled = true;
        };
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
        {
            AppDiagnostics.Log("domain-unhandled", e.ExceptionObject?.ToString() ?? "unknown");
        };
        TaskScheduler.UnobservedTaskException += (_, e) =>
        {
            AppDiagnostics.Exception("unobserved-task", e.Exception);
            e.SetObserved();
        };
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        AppDiagnostics.Log("app", "OnLaunched");
        try
        {
            MainWindow = new MainWindow();
            MainWindow.Activate();
        }
        catch (Exception ex)
        {
            AppDiagnostics.Exception("app-launch", ex);
            throw;
        }
    }
}
