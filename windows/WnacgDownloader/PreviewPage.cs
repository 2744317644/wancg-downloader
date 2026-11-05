using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using WnacgDownloader.Core;

namespace WnacgDownloader;

public sealed class PreviewPage : Page
{
    private readonly StackPanel _pagesPanel = new() { Spacing = 4 };
    private readonly TextBlock _titleBlock = Ui.Text("", 20, bold: true);
    private readonly TextBlock _status = Ui.Secondary("正在读取图片地址…", 12);
    private readonly ProgressRing _ring = new()
    {
        IsActive = true,
        Width = 20,
        Height = 20,
        VerticalAlignment = VerticalAlignment.Center,
    };

    private readonly InfoBar _info = Ui.Info();
    private readonly Button _downloadButton = Ui.AccentButton("下载到本地");
    private readonly AlbumPreview _album;

    public PreviewPage(AlbumPreview album)
    {
        _album = album;

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
        var statusRow = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
        };
        statusRow.Children.Add(_ring);
        statusRow.Children.Add(_status);
        titleStack.Children.Add(statusRow);

        _downloadButton.Click += async (_, _) => await DownloadAsync();
        Grid.SetColumn(back, 0);
        Grid.SetColumn(titleStack, 1);
        Grid.SetColumn(_downloadButton, 2);
        header.Children.Add(back);
        header.Children.Add(titleStack);
        header.Children.Add(_downloadButton);

        var pagesScroll = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Padding = new Thickness(24, 8, 24, 24),
            Content = _pagesPanel,
        };

        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(
            new RowDefinition { Height = new GridLength(1, GridUnitType.Star) }
        );
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var headerBorder = new Border
        {
            Padding = new Thickness(24, 20, 24, 8),
            Child = header,
        };
        var infoBorder = new Border
        {
            Padding = new Thickness(24, 0, 24, 12),
            Child = _info,
        };
        Grid.SetRow(headerBorder, 0);
        Grid.SetRow(pagesScroll, 1);
        Grid.SetRow(infoBorder, 2);
        root.Children.Add(headerBorder);
        root.Children.Add(pagesScroll);
        root.Children.Add(infoBorder);

        Content = root;
        _titleBlock.Text = album.Title;
        _ = LoadPagesAsync(album);
    }

    private async Task LoadPagesAsync(AlbumPreview album)
    {
        try
        {
            var urls = await AppServices.Instance.Client.GetPageUrlsAsync(album.Aid);
            var images = new List<Image>();

            await Ui.OnUIAsync(async () =>
            {
                _status.Text = $"共 {urls.Count} 页 · 向下滚动预览";
                _ring.IsActive = false;
                _pagesPanel.Children.Clear();
                for (var i = 0; i < urls.Count; i++)
                {
                    var pageNumber = new TextBlock
                    {
                        Text = $"第 {i + 1} 页",
                        FontSize = 11,
                        Opacity = 0.55,
                        Margin = new Thickness(0, 8, 0, 2),
                    };
                    var image = new Image
                    {
                        Stretch = Stretch.Uniform,
                        HorizontalAlignment = HorizontalAlignment.Center,
                        VerticalAlignment = VerticalAlignment.Top,
                        MinHeight = 180,
                        MaxWidth = 1000,
                    };
                    images.Add(image);
                    _pagesPanel.Children.Add(pageNumber);
                    _pagesPanel.Children.Add(image);
                }

                await Task.CompletedTask;
            });

            var gate = new SemaphoreSlim(
                Math.Clamp(AppServices.Instance.Settings.ImageConcurrency, 1, 6)
            );
            var tasks = new List<Task>();
            for (var index = 0; index < urls.Count; index++)
            {
                var pageIndex = index;
                var url = urls[index];
                tasks.Add(
                    Task.Run(
                        async () =>
                        {
                            await gate.WaitAsync();
                            try
                            {
                                var bytes = await AppServices.Instance.Client.GetBytesAsync(
                                    url,
                                    album.PageUrl
                                );
                                await Ui.OnUIAsync(
                                    async () =>
                                    {
                                        images[pageIndex].Source =
                                            await Ui.CreateBitmapAsync(bytes);
                                    }
                                );
                            }
                            catch
                            {
                                // Leave this page blank; the rest still loads.
                            }
                            finally
                            {
                                gate.Release();
                            }
                        }
                    )
                );
            }

            await Task.WhenAll(tasks);
            Ui.ShowInfo(_info, "预览已加载完成。", InfoBarSeverity.Success);
        }
        catch (Exception ex)
        {
            _ring.IsActive = false;
            _status.Text = "预览加载失败";
            Ui.ShowInfo(_info, ex.Message, InfoBarSeverity.Error);
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
