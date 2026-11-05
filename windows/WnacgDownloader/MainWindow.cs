using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using WnacgDownloader.Core;

namespace WnacgDownloader;

public sealed class MainWindow : Window
{
    private readonly NavigationView _nav = new();
    private readonly DownloadPage _downloadPage = new();
    private readonly BookmarksPage _bookmarksPage = new();
    private readonly SettingsPage _settingsPage = new();

    public MainWindow()
    {
        Title = "wnacg 下载器";
        try
        {
            AppWindow.Resize(new Windows.Graphics.SizeInt32(1400, 950));
        }
        catch
        {
            // Window sizing is best-effort.
        }

        _nav.PaneDisplayMode = NavigationViewPaneDisplayMode.Left;
        _nav.IsSettingsVisible = false;
        _nav.IsBackButtonVisible = NavigationViewBackButtonVisible.Collapsed;
        _nav.MenuItems.Add(
            new NavigationViewItem
            {
                Content = "下载",
                Tag = "download",
                Icon = new SymbolIcon(Symbol.Download),
            }
        );
        _nav.MenuItems.Add(
            new NavigationViewItem
            {
                Content = "书签",
                Tag = "bookmarks",
                Icon = new SymbolIcon(Symbol.Bookmarks),
            }
        );
        _nav.MenuItems.Add(
            new NavigationViewItem
            {
                Content = "设置",
                Tag = "settings",
                Icon = new SymbolIcon(Symbol.Setting),
            }
        );

        _nav.SelectionChanged += OnSelectionChanged;
        _nav.Content = _downloadPage;
        Content = _nav;
        _nav.SelectedItem = _nav.MenuItems[0];
    }

    private void OnSelectionChanged(
        NavigationView sender,
        NavigationViewSelectionChangedEventArgs args
    )
    {
        var tag = (args.SelectedItemContainer?.Tag as string) ?? "download";
        switch (tag)
        {
            case "bookmarks":
                _nav.Content = _bookmarksPage;
                break;
            case "settings":
                _nav.Content = _settingsPage;
                break;
            default:
                _nav.Content = _downloadPage;
                break;
        }
    }

    public void ShowPreview(AlbumPreview album)
    {
        // Hide the navigation pane so the reader-style preview gets the full
        // window width.
        _nav.IsPaneVisible = false;
        _nav.IsPaneToggleButtonVisible = false;
        _nav.Content = new PreviewPage(album);
    }

    public void ShowDownloadPage()
    {
        _nav.IsPaneVisible = true;
        _nav.IsPaneToggleButtonVisible = true;
        _nav.SelectedItem = _nav.MenuItems[0];
        _nav.Content = _downloadPage;
    }
}
