using Microsoft.UI.Dispatching;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Storage.Streams;
using Windows.UI;

namespace WnacgDownloader;

public static class Ui
{
    public static Brush CardBrush =>
        GetBrush("CardBackgroundFillColorDefaultBrush")
        ?? new SolidColorBrush(Color.FromArgb(24, 120, 120, 120));

    public static Brush? GetBrush(string key)
    {
        try
        {
            return Application.Current.Resources[key] as Brush;
        }
        catch
        {
            return null;
        }
    }

    public static Border Card(UIElement child, double padding = 16)
    {
        return new Border
        {
            Background = CardBrush,
            BorderBrush = GetBrush("CardStrokeColorDefaultBrush"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(12),
            Padding = new Thickness(padding),
            Child = child,
        };
    }

    public static TextBlock Text(string text, double size = 14, bool bold = false)
    {
        var block = new TextBlock
        {
            Text = text,
            FontSize = size,
            TextWrapping = TextWrapping.Wrap,
        };
        if (bold) block.FontWeight = FontWeights.SemiBold;
        return block;
    }

    public static TextBlock Secondary(string text, double size = 12) =>
        new()
        {
            Text = text,
            FontSize = size,
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.7,
        };

    public static TextBlock Heading(string text) => Text(text, 26, bold: true);

    public static Button AccentButton(string text)
    {
        var button = new Button { Content = text };
        try
        {
            if (Application.Current.Resources["AccentButtonStyle"] is Style style)
            {
                button.Style = style;
            }
        }
        catch
        {
            // Default style is fine.
        }

        return button;
    }

    public static InfoBar Info() =>
        new()
        {
            IsOpen = false,
            IsClosable = true,
            Severity = InfoBarSeverity.Informational,
        };

    public static void ShowInfo(
        InfoBar bar,
        string message,
        InfoBarSeverity severity = InfoBarSeverity.Informational
    )
    {
        bar.Severity = severity;
        bar.Message = message;
        bar.IsOpen = true;
    }

    public static async Task<BitmapImage> CreateBitmapAsync(byte[] bytes)
    {
        using var stream = new InMemoryRandomAccessStream();
        using (var writer = new DataWriter(stream.GetOutputStreamAt(0)))
        {
            writer.WriteBytes(bytes);
            await writer.StoreAsync();
            await writer.FlushAsync();
            writer.DetachStream();
        }

        stream.Seek(0);
        var bitmap = new BitmapImage();
        await bitmap.SetSourceAsync(stream);
        return bitmap;
    }

    public static Task OnUIAsync(Func<Task> action)
    {
        var tcs = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var dispatcher = App.MainWindow?.DispatcherQueue;
        if (dispatcher == null)
        {
            tcs.SetException(new InvalidOperationException("窗口尚未初始化"));
            return tcs.Task;
        }

        dispatcher.TryEnqueue(
            async () =>
            {
                try
                {
                    await action();
                    tcs.TrySetResult();
                }
                catch (Exception ex)
                {
                    tcs.TrySetException(ex);
                }
            }
        );
        return tcs.Task;
    }

    public static void OnUI(Action action)
    {
        var dispatcher = App.MainWindow?.DispatcherQueue;
        dispatcher?.TryEnqueue(() => action());
    }
}
