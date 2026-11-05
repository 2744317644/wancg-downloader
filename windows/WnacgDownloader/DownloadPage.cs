using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Navigation;
using WnacgDownloader.Core;

namespace WnacgDownloader;

public sealed class DownloadPage : Page
{
    private readonly TextBox _urlBox = new()
    {
        PlaceholderText = "https://www.wnacg.com/photos-index-aid-383877.html",
        HorizontalAlignment = HorizontalAlignment.Stretch,
    };

    private readonly Button _parseButton = Ui.AccentButton("解析作品");
    private readonly InfoBar _info = Ui.Info();
    private readonly StackPanel _previewHost = new() { Spacing = 14 };
    private readonly StackPanel _queueHost = new() { Spacing = 8 };
    private AlbumPreview? _preview;

    public DownloadPage()
    {
        NavigationCacheMode = NavigationCacheMode.Required;
        var scroll = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Padding = new Thickness(24),
        };
        var stack = new StackPanel { Spacing = 14 };
        stack.Children.Add(Ui.Heading("下载"));
        stack.Children.Add(
            Ui.Secondary(
                "粘贴 wnacg 作品链接，解析后可以预览或下载。下载目录、系统代理 / DoH 直连和代理端口都在「设置」里修改。"
            )
        );
        stack.Children.Add(BuildInputCard());
        stack.Children.Add(_info);
        stack.Children.Add(_previewHost);

        var queueHeader = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 10,
            Margin = new Thickness(0, 8, 0, 0),
        };
        queueHeader.Children.Add(Ui.Text("下载队列", 18, bold: true));
        stack.Children.Add(queueHeader);
        stack.Children.Add(_queueHost);

        scroll.Content = stack;
        Content = scroll;
    }

    private FrameworkElement BuildInputCard()
    {
        var stack = new StackPanel { Spacing = 10 };
        stack.Children.Add(Ui.Text("作品链接", 14, bold: true));

        var row = new Grid { ColumnSpacing = 8 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var paste = new Button { Content = "粘贴" };
        paste.Click += async (_, _) =>
        {
            try
            {
                var content = Windows.ApplicationModel.DataTransfer.Clipboard.GetContent();
                if (content.Contains(Windows.ApplicationModel.DataTransfer.StandardDataFormats.Text))
                {
                    var text = await content.GetTextAsync();
                    if (!string.IsNullOrWhiteSpace(text))
                    {
                        _urlBox.Text = text.Trim();
                    }
                }
            }
            catch
            {
                // Clipboard can fail when another app is locking it.
            }
        };

        _parseButton.Click += async (_, _) => await ParseAsync();
        Grid.SetColumn(_urlBox, 0);
        Grid.SetColumn(paste, 1);
        Grid.SetColumn(_parseButton, 2);
        row.Children.Add(_urlBox);
        row.Children.Add(paste);
        row.Children.Add(_parseButton);

        stack.Children.Add(row);
        stack.Children.Add(
            Ui.Secondary("支持作品页、阅读页链接，也可以直接粘贴 aid 数字（例如 383877）。")
        );
        return Ui.Card(stack);
    }

    private async Task ParseAsync()
    {
        var input = _urlBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(input))
        {
            Ui.ShowInfo(_info, "请先粘贴作品链接。", InfoBarSeverity.Warning);
            return;
        }

        _parseButton.IsEnabled = false;
        Ui.ShowInfo(_info, "正在解析…", InfoBarSeverity.Informational);
        _previewHost.Children.Clear();

        try
        {
            var preview = await AppServices.Instance.Client.GetPreviewAsync(input);
            _preview = preview;
            _previewHost.Children.Add(BuildPreviewCard(preview));
            Ui.ShowInfo(
                _info,
                $"解析成功：{preview.Title}",
                InfoBarSeverity.Success
            );
        }
        catch (Exception ex)
        {
            Ui.ShowInfo(_info, ex.Message, InfoBarSeverity.Error);
        }
        finally
        {
            _parseButton.IsEnabled = true;
        }
    }

    private FrameworkElement BuildPreviewCard(AlbumPreview preview)
    {
        var grid = new Grid { ColumnSpacing = 16 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var coverImage = new Image
        {
            Width = 140,
            Height = 187,
            Stretch = Stretch.UniformToFill,
        };
        var coverBorder = new Border
        {
            Width = 140,
            Height = 187,
            CornerRadius = new CornerRadius(10),
            Background = Ui.GetBrush("ControlFillColorSecondaryBrush"),
            Child = coverImage,
        };
        _ = LoadImageAsync(coverImage, preview.CoverUrl, preview.PageUrl);

        var right = new StackPanel { Spacing = 8 };
        right.Children.Add(Ui.Text(preview.Title, 20, bold: true));
        if (!string.IsNullOrWhiteSpace(preview.MetaLine))
        {
            right.Children.Add(Ui.Secondary(preview.MetaLine, 13));
        }

        if (preview.Tags.Count > 0)
        {
            right.Children.Add(Ui.Secondary(string.Join("  ", preview.Tags.Take(12)), 12));
        }

        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
            Margin = new Thickness(0, 6, 0, 0),
        };
        var previewButton = new Button { Content = "预览漫画" };
        previewButton.Click += (_, _) =>
            ((MainWindow)App.MainWindow!).ShowPreview(preview);
        var downloadButton = Ui.AccentButton("下载到本地");
        downloadButton.Click += (_, _) => StartDownload(preview);
        buttons.Children.Add(previewButton);
        buttons.Children.Add(downloadButton);
        right.Children.Add(buttons);

        Grid.SetColumn(coverBorder, 0);
        Grid.SetColumn(right, 1);
        grid.Children.Add(coverBorder);
        grid.Children.Add(right);
        return Ui.Card(grid);
    }

    private async Task LoadImageAsync(Image image, string? url, string referer)
    {
        if (string.IsNullOrWhiteSpace(url))
        {
            return;
        }

        try
        {
            var bytes = await AppServices.Instance.Client.GetBytesAsync(url, referer);
            image.Source = await Ui.CreateBitmapAsync(bytes);
        }
        catch
        {
            // Keep the placeholder background when the cover fails.
        }
    }

    private void StartDownload(AlbumPreview preview)
    {
        var row = new QueueRow(preview.Title, preview.PageUrl);
        _queueHost.Children.Insert(0, row.Root);
        var cts = new CancellationTokenSource();
        row.CancelRequested += () =>
        {
            try
            {
                cts.Cancel();
            }
            catch
            {
                // Already disposed.
            }
        };

        _ = RunDownloadAsync(preview, row, cts);
    }

    private async Task RunDownloadAsync(
        AlbumPreview preview,
        QueueRow row,
        CancellationTokenSource cts
    )
    {
        try
        {
            var progress = new Progress<DownloadProgress>(row.Update);
            var folder = await AppServices.Instance.Downloader.DownloadAsync(
                preview,
                AppServices.Instance.Settings,
                progress,
                cts.Token
            );
            row.Complete(folder);
        }
        catch (OperationCanceledException)
        {
            row.Cancelled();
        }
        catch (Exception ex)
        {
            row.Fail(ex.Message);
        }
        finally
        {
            cts.Dispose();
        }
    }
}
