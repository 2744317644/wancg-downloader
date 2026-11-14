using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using WnacgDownloader.Core;

namespace WnacgDownloader;

public sealed class QueueRow
{
    private readonly TextBlock _title;
    private readonly TextBlock _status;
    private readonly ProgressBar _bar;
    private readonly Button _cancel;
    private readonly Button _open;
    private string? _folder;

    public Border Root { get; }

    public event Action? CancelRequested;

    public QueueRow(string title, string referer)
    {
        _title = Ui.Text(title, 14, bold: true);
        _status = Ui.Secondary("等待中…", 12);
        _bar = new ProgressBar
        {
            IsIndeterminate = true,
            HorizontalAlignment = HorizontalAlignment.Stretch,
        };
        _cancel = new Button { Content = "取消" };
        _cancel.Click += (_, _) => CancelRequested?.Invoke();
        _open = new Button { Content = "打开文件夹", IsEnabled = false };
        _open.Click += async (_, _) =>
        {
            if (_folder != null)
            {
                await AppServices.Instance.Downloader.OpenFolderAsync(_folder);
            }
        };

        var text = new StackPanel { Spacing = 6 };
        text.Children.Add(_title);
        text.Children.Add(_status);
        text.Children.Add(_bar);

        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
            VerticalAlignment = VerticalAlignment.Center,
        };
        buttons.Children.Add(_open);
        buttons.Children.Add(_cancel);

        var grid = new Grid { ColumnSpacing = 12 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(text, 0);
        Grid.SetColumn(buttons, 1);
        grid.Children.Add(text);
        grid.Children.Add(buttons);

        Root = new Border
        {
            Background = Ui.CardBrush,
            CornerRadius = new CornerRadius(10),
            Padding = new Thickness(14),
            Child = grid,
        };
    }

    public void UpdateTitle(string title)
    {
        Ui.OnUI(() => _title.Text = title);
    }

    public void Update(DownloadProgress progress)
    {
        Ui.OnUI(() =>
        {
            _bar.IsIndeterminate = progress.Total <= 0;
            if (progress.Total > 0)
            {
                _bar.Value = progress.Fraction * 100;
            }

            _status.Text =
                progress.Total > 0
                    ? $"{progress.Status}  ·  {progress.Done}/{progress.Total}  ·  {FormatBytes(progress.Bytes)}"
                    : progress.Status;
        });
    }

    public void Complete(string folder)
    {
        _folder = folder;
        Ui.OnUI(() =>
        {
            _bar.IsIndeterminate = false;
            _bar.Value = 100;
            _status.Text = "下载完成：" + folder;
            _cancel.IsEnabled = false;
            _open.IsEnabled = true;
        });
    }

    public void Fail(string message)
    {
        Ui.OnUI(() =>
        {
            _bar.IsIndeterminate = false;
            _bar.ShowError = true;
            _status.Text = "失败：" + message;
            _cancel.IsEnabled = false;
        });
    }

    public void Cancelled()
    {
        Ui.OnUI(() =>
        {
            _bar.IsIndeterminate = false;
            _status.Text = "已取消";
            _cancel.IsEnabled = false;
        });
    }

    private static string FormatBytes(long bytes)
    {
        if (bytes <= 0) return "0 B";
        string[] units = { "B", "KB", "MB", "GB" };
        var value = (double)bytes;
        var unit = 0;
        while (value >= 1024 && unit < units.Length - 1)
        {
            value /= 1024;
            unit++;
        }

        return $"{value:0.#} {units[unit]}";
    }
}
