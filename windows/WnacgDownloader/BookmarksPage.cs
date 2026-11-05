using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using Windows.Storage.Pickers;
using WnacgDownloader.Core;

namespace WnacgDownloader;

public sealed class BookmarksPage : Page
{
    private readonly ListView _list = new()
    {
        SelectionMode = ListViewSelectionMode.Multiple,
        Height = 280,
        HorizontalAlignment = HorizontalAlignment.Stretch,
    };

    private readonly TextBox _pasteBox = new()
    {
        AcceptsReturn = true,
        TextWrapping = TextWrapping.Wrap,
        Height = 84,
        PlaceholderText = "也可以直接粘贴多个作品链接，每行一个",
    };

    private readonly InfoBar _info = Ui.Info();
    private readonly TextBlock _status = Ui.Secondary("尚未导入书签。", 12);
    private readonly ProgressBar _progress = new() { Minimum = 0, Maximum = 100 };
    private readonly Button _downloadSelected = Ui.AccentButton("下载选中");
    private readonly Button _downloadAll = new() { Content = "下载全部" };
    private readonly Button _cancel = new() { Content = "停止", IsEnabled = false };

    private List<BookmarkItem> _items = new();
    private Dictionary<string, BookmarkItem> _displayMap = new();
    private CancellationTokenSource? _cts;

    public BookmarksPage()
    {
        NavigationCacheMode = NavigationCacheMode.Required;
        var scroll = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Padding = new Thickness(24),
        };
        var stack = new StackPanel { Spacing = 14 };
        stack.Children.Add(Ui.Heading("书签下载"));
        stack.Children.Add(
            Ui.Secondary(
                "导入浏览器导出的书签 HTML（Chrome / Edge / Firefox），或直接粘贴链接列表；勾选后可以批量下载。"
            )
        );

        var importRow = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
        };
        var importFile = Ui.AccentButton("导入书签文件");
        importFile.Click += async (_, _) => await ImportFileAsync();
        var selectAll = new Button { Content = "全选" };
        selectAll.Click += (_, _) => _list.SelectAll();
        var clear = new Button { Content = "清空" };
        clear.Click += (_, _) => ApplyItems(new List<BookmarkItem>());
        importRow.Children.Add(importFile);
        importRow.Children.Add(selectAll);
        importRow.Children.Add(clear);
        stack.Children.Add(Ui.Card(importRow));

        var pasteCard = new StackPanel { Spacing = 8 };
        pasteCard.Children.Add(Ui.Text("粘贴链接", 14, bold: true));
        pasteCard.Children.Add(_pasteBox);
        var addPasted = new Button { Content = "添加到列表" };
        addPasted.Click += (_, _) => AddPastedLinks();
        pasteCard.Children.Add(addPasted);
        stack.Children.Add(Ui.Card(pasteCard));

        var actionRow = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
        };
        _downloadSelected.Click += async (_, _) => await DownloadSelectedAsync();
        _downloadAll.Click += async (_, _) => await DownloadAllAsync();
        _cancel.Click += (_, _) =>
        {
            try
            {
                _cts?.Cancel();
            }
            catch
            {
                // Already finished.
            }
        };
        actionRow.Children.Add(_downloadSelected);
        actionRow.Children.Add(_downloadAll);
        actionRow.Children.Add(_cancel);
        stack.Children.Add(actionRow);

        stack.Children.Add(_progress);
        stack.Children.Add(_status);
        stack.Children.Add(_info);
        stack.Children.Add(_list);

        scroll.Content = stack;
        Content = scroll;
        UpdateButtons();
    }

    private async Task ImportFileAsync()
    {
        try
        {
            var picker = new FileOpenPicker
            {
                SuggestedStartLocation = PickerLocationId.Downloads,
            };
            picker.FileTypeFilter.Add(".html");
            picker.FileTypeFilter.Add(".htm");
            picker.FileTypeFilter.Add(".txt");
            if (App.MainWindow != null)
            {
                WinRT.Interop.InitializeWithWindow.Initialize(
                    picker,
                    WinRT.Interop.WindowNative.GetWindowHandle(App.MainWindow)
                );
            }

            var file = await picker.PickSingleFileAsync();
            if (file == null)
            {
                return;
            }

            var items = BookmarkParser.ParseFile(file.Path);
            ApplyItems(items);
            Ui.ShowInfo(
                _info,
                items.Count > 0
                    ? $"从 {file.Name} 解析到 {items.Count} 个作品。"
                    : "文件里没有找到 wnacg 作品链接。",
                items.Count > 0 ? InfoBarSeverity.Success : InfoBarSeverity.Warning
            );
        }
        catch (Exception ex)
        {
            Ui.ShowInfo(_info, "导入失败：" + ex.Message, InfoBarSeverity.Error);
        }
    }

    private void AddPastedLinks()
    {
        var parsed = BookmarkParser.ParseText(_pasteBox.Text ?? "");
        if (parsed.Count == 0)
        {
            Ui.ShowInfo(_info, "没有识别到作品链接。", InfoBarSeverity.Warning);
            return;
        }

        var merged = _items.ToList();
        foreach (var item in parsed)
        {
            if (!merged.Any(x => x.Aid == item.Aid))
            {
                merged.Add(item);
            }
        }

        ApplyItems(merged);
        _pasteBox.Text = "";
        Ui.ShowInfo(_info, $"已添加 {parsed.Count} 个链接。", InfoBarSeverity.Success);
    }

    private void ApplyItems(List<BookmarkItem> items)
    {
        _items = items;
        _displayMap = new Dictionary<string, BookmarkItem>();
        var displays = new List<string>();
        foreach (var item in items)
        {
            var display = item.Display;
            if (_displayMap.ContainsKey(display))
            {
                display = $"{display}  (#{items.IndexOf(item) + 1})";
            }

            _displayMap[display] = item;
            displays.Add(display);
        }

        _list.ItemsSource = displays;
        _status.Text =
            items.Count == 0 ? "尚未导入书签。" : $"共 {items.Count} 个作品，勾选后下载。";
        UpdateButtons();
    }

    private void UpdateButtons()
    {
        _downloadAll.IsEnabled = _items.Count > 0 && _cts == null;
        _downloadSelected.IsEnabled = _items.Count > 0 && _cts == null;
    }

    private async Task DownloadSelectedAsync()
    {
        var selected = GetSelectedItems();
        if (selected.Count == 0)
        {
            Ui.ShowInfo(_info, "请先在列表里选择作品。", InfoBarSeverity.Warning);
            return;
        }

        await DownloadItemsAsync(selected);
    }

    private async Task DownloadAllAsync()
    {
        if (_items.Count == 0)
        {
            Ui.ShowInfo(_info, "列表为空。", InfoBarSeverity.Warning);
            return;
        }

        await DownloadItemsAsync(_items.ToList());
    }

    private List<BookmarkItem> GetSelectedItems()
    {
        var selected = new List<BookmarkItem>();
        foreach (var display in _list.SelectedItems)
        {
            if (display is string key && _displayMap.TryGetValue(key, out var item))
            {
                selected.Add(item);
            }
        }

        return selected;
    }

    private async Task DownloadItemsAsync(List<BookmarkItem> items)
    {
        _cts = new CancellationTokenSource();
        var token = _cts.Token;
        _downloadSelected.IsEnabled = false;
        _downloadAll.IsEnabled = false;
        _cancel.IsEnabled = true;
        _progress.IsIndeterminate = false;
        _progress.Value = 0;
        var succeeded = 0;
        var failed = 0;

        try
        {
            for (var i = 0; i < items.Count; i++)
            {
                token.ThrowIfCancellationRequested();
                var item = items[i];
                _status.Text = $"[{i + 1}/{items.Count}] 正在解析 {item.Display}";
                try
                {
                    var preview = await AppServices.Instance.Client.GetPreviewAsync(
                        item.Url,
                        token
                    );
                    _status.Text = $"[{i + 1}/{items.Count}] 正在下载 {preview.Title}";
                    var folder = await AppServices.Instance.Downloader.DownloadAsync(
                        preview,
                        AppServices.Instance.Settings,
                        progress: null,
                        token
                    );
                    succeeded++;
                    _status.Text = $"[{i + 1}/{items.Count}] 完成：{folder}";
                }
                catch (OperationCanceledException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    failed++;
                    _status.Text = $"[{i + 1}/{items.Count}] 失败：{ex.Message}";
                }

                _progress.Value = (i + 1) * 100.0 / items.Count;
            }

            Ui.ShowInfo(
                _info,
                $"批量下载结束：成功 {succeeded}，失败 {failed}。",
                failed == 0 ? InfoBarSeverity.Success : InfoBarSeverity.Warning
            );
        }
        catch (OperationCanceledException)
        {
            Ui.ShowInfo(_info, "已停止批量下载。", InfoBarSeverity.Warning);
        }
        finally
        {
            _cts.Dispose();
            _cts = null;
            _cancel.IsEnabled = false;
            UpdateButtons();
        }
    }
}
