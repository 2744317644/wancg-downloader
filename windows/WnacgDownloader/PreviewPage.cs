using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using WnacgDownloader.Core;

namespace WnacgDownloader;

public sealed class PreviewPage : Page
{
    private readonly AlbumPreview _album;
    private readonly TextBlock _titleBlock = Ui.Text("", 20, bold: true);
    private readonly TextBlock _status = Ui.Secondary("正在读取图片地址…", 12);
    private readonly TextBlock _pageLabel = Ui.Text("", 14, bold: true);
    private readonly ProgressRing _ring = new()
    {
        IsActive = true,
        Width = 44,
        Height = 44,
        HorizontalAlignment = HorizontalAlignment.Center,
        VerticalAlignment = VerticalAlignment.Center,
    };

    private readonly InfoBar _info = Ui.Info();
    private readonly Button _downloadButton = Ui.AccentButton("下载到本地");
    private readonly Button _modeButton = new() { Content = "单页模式" };
    private readonly Grid _imagesGrid = new() { ColumnSpacing = 4 };
    private readonly Image _leftImage = new()
    {
        Stretch = Stretch.Uniform,
        HorizontalAlignment = HorizontalAlignment.Stretch,
        VerticalAlignment = VerticalAlignment.Stretch,
        Margin = new Thickness(2),
    };
    private readonly Image _rightImage = new()
    {
        Stretch = Stretch.Uniform,
        HorizontalAlignment = HorizontalAlignment.Stretch,
        VerticalAlignment = VerticalAlignment.Stretch,
        Margin = new Thickness(2),
    };

    private List<string> _pageUrls = new();
    private Dictionary<int, BitmapImage> _cache = new();
    private List<int> _cacheOrder = new();
    private const int MaxCachedPages = 10;
    private int _index;
    private bool _doublePage = true;
    private bool _loading;
    private CancellationTokenSource? _loadCts;

    public PreviewPage(AlbumPreview album)
    {
        _album = album;

        // Header.
        var header = new Grid { ColumnSpacing = 12 };
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(
            new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) }
        );
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var back = new Button { Content = "← 返回" };
        back.Click += (_, _) => ((MainWindow)App.MainWindow!).ShowDownloadPage();

        var titleStack = new StackPanel { Spacing = 4 };
        titleStack.Children.Add(_titleBlock);
        titleStack.Children.Add(_status);
        _titleBlock.Text = album.Title;

        var headerButtons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
            VerticalAlignment = VerticalAlignment.Center,
        };
        _modeButton.Click += (_, _) => ToggleMode();
        _downloadButton.Click += async (_, _) => await DownloadAsync();
        headerButtons.Children.Add(_modeButton);
        headerButtons.Children.Add(_downloadButton);

        Grid.SetColumn(back, 0);
        Grid.SetColumn(titleStack, 1);
        Grid.SetColumn(headerButtons, 2);
        header.Children.Add(back);
        header.Children.Add(titleStack);
        header.Children.Add(headerButtons);

        // Page area: two images side by side, overlaid by transparent tap zones.
        var pageArea = new Grid();
        pageArea.Children.Add(_imagesGrid);

        var tapGrid = new Grid();
        tapGrid.ColumnDefinitions.Add(
            new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) }
        );
        tapGrid.ColumnDefinitions.Add(
            new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) }
        );
        var prevZone = new Button
        {
            Background = new SolidColorBrush(Windows.UI.Color.FromArgb(1, 0, 0, 0)),
            BorderThickness = new Thickness(0),
            IsTabStop = false,
        };
        prevZone.Click += (_, _) => Navigate(-1);
        var nextZone = new Button
        {
            Background = new SolidColorBrush(Windows.UI.Color.FromArgb(1, 0, 0, 0)),
            BorderThickness = new Thickness(0),
            IsTabStop = false,
        };
        nextZone.Click += (_, _) => Navigate(1);
        Grid.SetColumn(prevZone, 0);
        Grid.SetColumn(nextZone, 1);
        tapGrid.Children.Add(prevZone);
        tapGrid.Children.Add(nextZone);
        pageArea.Children.Add(tapGrid);

        var loadingOverlay = new Border
        {
            Background = new SolidColorBrush(Windows.UI.Color.FromArgb(160, 0, 0, 0)),
            Child = _ring,
            Visibility = Visibility.Collapsed,
        };
        pageArea.Children.Add(loadingOverlay);
        _loadingOverlay = loadingOverlay;

        var pageAreaBorder = new Border
        {
            Background = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 8, 10, 14)),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(6),
            Child = pageArea,
        };

        // Footer.
        var footer = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 12,
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        var prev = new Button { Content = "上一页" };
        prev.Click += (_, _) => Navigate(-1);
        var next = new Button { Content = "下一页" };
        next.Click += (_, _) => Navigate(1);
        footer.Children.Add(prev);
        footer.Children.Add(_pageLabel);
        footer.Children.Add(next);
        footer.Children.Add(Ui.Secondary("点击页面左右两侧也可翻页", 12));

        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(
            new RowDefinition { Height = new GridLength(1, GridUnitType.Star) }
        );
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var headerBorder = new Border
        {
            Padding = new Thickness(24, 18, 24, 8),
            Child = header,
        };
        var pageBorder = new Border
        {
            Padding = new Thickness(24, 6, 24, 6),
            Child = pageAreaBorder,
        };
        var footerBorder = new Border
        {
            Padding = new Thickness(24, 8, 24, 8),
            Child = footer,
        };
        var infoBorder = new Border
        {
            Padding = new Thickness(24, 0, 24, 12),
            Child = _info,
        };
        Grid.SetRow(headerBorder, 0);
        Grid.SetRow(pageBorder, 1);
        Grid.SetRow(footerBorder, 2);
        Grid.SetRow(infoBorder, 3);
        root.Children.Add(headerBorder);
        root.Children.Add(pageBorder);
        root.Children.Add(footerBorder);
        root.Children.Add(infoBorder);

        Content = root;
        _ = LoadPagesAsync();
    }

    private Border? _loadingOverlay;

    private void SetLoading(bool loading)
    {
        _loading = loading;
        _ring.IsActive = loading;
        if (_loadingOverlay != null)
        {
            _loadingOverlay.Visibility = loading ? Visibility.Visible : Visibility.Collapsed;
        }
    }

    private async Task LoadPagesAsync()
    {
        try
        {
            _pageUrls = await AppServices.Instance.Client.GetPageUrlsAsync(_album.Aid);
            _status.Text = $"共 {_pageUrls.Count} 页";
            SetLoading(false);
            _index = 0;
            await ShowCurrentAsync();
        }
        catch (Exception ex)
        {
            SetLoading(false);
            _status.Text = "预览加载失败";
            Ui.ShowInfo(_info, ex.Message, InfoBarSeverity.Error);
        }
    }

    private void ToggleMode()
    {
        _doublePage = !_doublePage;
        _modeButton.Content = _doublePage ? "单页模式" : "双页模式";
        _index = _doublePage ? _index - (_index % 2) : _index;
        _ = ShowCurrentAsync();
    }

    private void Navigate(int direction)
    {
        if (_pageUrls.Count == 0 || _loading)
        {
            return;
        }

        var step = _doublePage ? 2 : 1;
        var next = Math.Clamp(_index + direction * step, 0, _pageUrls.Count - 1);
        if (next == _index)
        {
            return;
        }

        _index = next;
        _ = ShowCurrentAsync();
    }

    private async Task ShowCurrentAsync()
    {
        if (_pageUrls.Count == 0)
        {
            return;
        }

        _loadCts?.Cancel();
        var cts = new CancellationTokenSource();
        _loadCts = cts;
        SetLoading(true);
        _leftImage.Source = null;
        _rightImage.Source = null;

        var leftIndex = _doublePage ? _index + 1 : _index;
        var rightIndex = _index;
        var indices = new List<int>();
        if (_doublePage)
        {
            _imagesGrid.ColumnDefinitions.Clear();
            _imagesGrid.ColumnDefinitions.Add(
                new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) }
            );
            _imagesGrid.ColumnDefinitions.Add(
                new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) }
            );
            _imagesGrid.Children.Clear();
            if (leftIndex < _pageUrls.Count)
            {
                _imagesGrid.Children.Add(_leftImage);
                Grid.SetColumn(_leftImage, 0);
                indices.Add(leftIndex);
            }

            _imagesGrid.Children.Add(_rightImage);
            Grid.SetColumn(_rightImage, leftIndex < _pageUrls.Count ? 1 : 0);
            indices.Add(rightIndex);
        }
        else
        {
            _imagesGrid.ColumnDefinitions.Clear();
            _imagesGrid.ColumnDefinitions.Add(
                new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) }
            );
            _imagesGrid.Children.Clear();
            _imagesGrid.Children.Add(_rightImage);
            Grid.SetColumn(_rightImage, 0);
            indices.Add(rightIndex);
        }

        _pageLabel.Text = _doublePage && leftIndex < _pageUrls.Count
            ? $"{rightIndex + 1}-{leftIndex + 1} / {_pageUrls.Count}"
            : $"{rightIndex + 1} / {_pageUrls.Count}";

        try
        {
            var bitmaps = await Task.WhenAll(
                indices.Select(i => LoadBitmapAsync(i, cts.Token))
            );
            if (cts.IsCancellationRequested)
            {
                return;
            }

            var map = new Dictionary<int, BitmapImage?>();
            for (var i = 0; i < indices.Count; i++)
            {
                map[indices[i]] = bitmaps[i];
            }

            if (_doublePage)
            {
                _leftImage.Source = map.GetValueOrDefault(leftIndex);
                _rightImage.Source = map.GetValueOrDefault(rightIndex);
            }
            else
            {
                _rightImage.Source = map.GetValueOrDefault(rightIndex);
            }

            SetLoading(false);
            _ = PrefetchAsync();
        }
        catch (OperationCanceledException)
        {
            // A newer page request superseded this one.
        }
        catch (Exception ex)
        {
            SetLoading(false);
            Ui.ShowInfo(_info, ex.Message, InfoBarSeverity.Error);
        }
    }

    private async Task<BitmapImage?> LoadBitmapAsync(int index, CancellationToken ct)
    {
        if (index < 0 || index >= _pageUrls.Count)
        {
            return null;
        }

        if (_cache.TryGetValue(index, out var cached))
        {
            return cached;
        }

        var bytes = await AppServices.Instance.Client.GetBytesAsync(
            _pageUrls[index],
            _album.PageUrl,
            ct
        );
        var bitmap = await Ui.CreateBitmapAsync(bytes);
        _cache[index] = bitmap;
        _cacheOrder.Add(index);
        while (_cacheOrder.Count > MaxCachedPages)
        {
            var oldest = _cacheOrder[0];
            _cacheOrder.RemoveAt(0);
            _cache.Remove(oldest);
        }

        return bitmap;
    }

    private async Task PrefetchAsync()
    {
        var indices = _doublePage
            ? new[] { _index + 2, _index + 3, _index - 1, _index - 2 }
            : new[] { _index + 1, _index + 2, _index - 1 };
        foreach (var index in indices.Distinct())
        {
            if (index < 0 || index >= _pageUrls.Count || _cache.ContainsKey(index))
            {
                continue;
            }

            try
            {
                await LoadBitmapAsync(index, CancellationToken.None);
            }
            catch
            {
                // Prefetch failures are harmless; the page loads on demand.
            }
        }
    }

    private async Task DownloadAsync()
    {
        _downloadButton.IsEnabled = false;
        _status.Text = "正在准备下载…";
        try
        {
            var folder = await AppServices.Instance.Downloader.DownloadAsync(
                _album,
                AppServices.Instance.Settings
            );
            _status.Text = "下载完成：" + folder;
            Ui.ShowInfo(_info, "下载完成：" + folder, InfoBarSeverity.Success);
        }
        catch (Exception ex)
        {
            _status.Text = "下载失败";
            Ui.ShowInfo(_info, ex.Message, InfoBarSeverity.Error);
        }
        finally
        {
            _downloadButton.IsEnabled = true;
        }
    }
}
