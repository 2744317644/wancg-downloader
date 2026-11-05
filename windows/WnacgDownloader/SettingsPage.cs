using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using Windows.Storage.Pickers;
using WnacgDownloader.Core;

namespace WnacgDownloader;

public sealed class SettingsPage : Page
{
    private readonly TextBox _dirBox = new()
    {
        HorizontalAlignment = HorizontalAlignment.Stretch,
    };

    private readonly ComboBox _modeBox = new()
    {
        ItemsSource = new List<string> { "系统代理", "DoH 直连" },
        SelectedIndex = 0,
    };

    private readonly CheckBox _customPortBox = new()
    {
        Content = "使用自定义代理端口（127.0.0.1）",
    };

    private readonly NumberBox _portBox = new()
    {
        Minimum = 1,
        Maximum = 65535,
        SmallChange = 1,
        Value = 7890,
        SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact,
    };

    private readonly TextBox _dohBox = new()
    {
        HorizontalAlignment = HorizontalAlignment.Stretch,
    };

    private readonly NumberBox _concurrencyBox = new()
    {
        Minimum = 1,
        Maximum = 12,
        SmallChange = 1,
        Value = 4,
        SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact,
    };

    private readonly CheckBox _zipBox = new()
    {
        Content = "下载完成后额外打包一份 ZIP",
        IsChecked = true,
    };

    private readonly InfoBar _info = Ui.Info();

    public SettingsPage()
    {
        NavigationCacheMode = NavigationCacheMode.Required;
        var scroll = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Padding = new Thickness(24),
        };
        var stack = new StackPanel { Spacing = 14 };
        stack.Children.Add(Ui.Heading("设置"));
        stack.Children.Add(
            Ui.Secondary(
                "下载目录、网络模式和代理端口会保存在 %LOCALAPPDATA%\\WnacgDownloader\\settings.json。"
            )
        );

        // Download directory.
        var dirStack = new StackPanel { Spacing = 8 };
        dirStack.Children.Add(Ui.Text("下载目录", 15, bold: true));
        var dirRow = new Grid { ColumnSpacing = 8 };
        dirRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        dirRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var browse = new Button { Content = "浏览…" };
        browse.Click += async (_, _) => await PickFolderAsync();
        Grid.SetColumn(_dirBox, 0);
        Grid.SetColumn(browse, 1);
        dirRow.Children.Add(_dirBox);
        dirRow.Children.Add(browse);
        dirStack.Children.Add(dirRow);
        dirStack.Children.Add(
            Ui.Secondary("每部作品会在该目录下创建同名文件夹；勾选 ZIP 时还会生成同名 .zip。", 12)
        );
        stack.Children.Add(Ui.Card(dirStack));

        // Network.
        var netStack = new StackPanel { Spacing = 8 };
        netStack.Children.Add(Ui.Text("网络", 15, bold: true));
        netStack.Children.Add(Ui.Secondary("系统代理：使用 Windows 系统代理；DoH 直连：通过 DoH 解析真实 IP 后直连。", 12));
        netStack.Children.Add(_modeBox);
        netStack.Children.Add(_customPortBox);
        netStack.Children.Add(_portBox);
        var dohLabel = Ui.Text("DoH 端点（{host} 会被替换为域名）", 13, bold: true);
        netStack.Children.Add(dohLabel);
        netStack.Children.Add(_dohBox);
        stack.Children.Add(Ui.Card(netStack));

        // Performance.
        var perfStack = new StackPanel { Spacing = 8 };
        perfStack.Children.Add(Ui.Text("下载", 15, bold: true));
        var concurrencyRow = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 10,
        };
        concurrencyRow.Children.Add(Ui.Text("图片并发数", 13));
        concurrencyRow.Children.Add(_concurrencyBox);
        perfStack.Children.Add(concurrencyRow);
        perfStack.Children.Add(_zipBox);
        stack.Children.Add(Ui.Card(perfStack));

        var save = Ui.AccentButton("保存设置");
        save.Click += (_, _) => Save();
        stack.Children.Add(save);
        stack.Children.Add(_info);

        scroll.Content = stack;
        Content = scroll;

        _modeBox.SelectionChanged += (_, _) => UpdateNetworkControls();
        _customPortBox.Checked += (_, _) => UpdateNetworkControls();
        _customPortBox.Unchecked += (_, _) => UpdateNetworkControls();
        LoadSettings();
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        LoadSettings();
    }

    private void LoadSettings()
    {
        var settings = AppServices.Instance.Settings;
        _dirBox.Text = settings.DownloadDirectory;
        _modeBox.SelectedIndex = settings.NetworkMode == NetworkMode.Doh ? 1 : 0;
        _customPortBox.IsChecked = settings.UseCustomProxyPort;
        _portBox.Value = settings.ProxyPort;
        _dohBox.Text = settings.DohEndpoint;
        _concurrencyBox.Value = settings.ImageConcurrency;
        _zipBox.IsChecked = settings.CreateZip;
        UpdateNetworkControls();
    }

    private void UpdateNetworkControls()
    {
        var systemProxyMode = _modeBox.SelectedIndex == 0;
        _customPortBox.IsEnabled = systemProxyMode;
        _portBox.IsEnabled = systemProxyMode && _customPortBox.IsChecked == true;
    }

    private async Task PickFolderAsync()
    {
        try
        {
            var picker = new FolderPicker
            {
                SuggestedStartLocation = PickerLocationId.Downloads,
            };
            picker.FileTypeFilter.Add("*");
            if (App.MainWindow != null)
            {
                WinRT.Interop.InitializeWithWindow.Initialize(
                    picker,
                    WinRT.Interop.WindowNative.GetWindowHandle(App.MainWindow)
                );
            }

            var folder = await picker.PickSingleFolderAsync();
            if (folder != null)
            {
                _dirBox.Text = folder.Path;
            }
        }
        catch (Exception ex)
        {
            Ui.ShowInfo(_info, "选择目录失败：" + ex.Message, InfoBarSeverity.Error);
        }
    }

    private void Save()
    {
        try
        {
            var directory = SettingsStore.Expand(_dirBox.Text ?? "");
            if (string.IsNullOrWhiteSpace(directory))
            {
                throw new InvalidOperationException("下载目录不能为空。");
            }

            Directory.CreateDirectory(directory);
            var settings = new AppSettings
            {
                DownloadDirectory = directory,
                NetworkMode = _modeBox.SelectedIndex == 1
                    ? NetworkMode.Doh
                    : NetworkMode.SystemProxy,
                UseCustomProxyPort = _customPortBox.IsChecked == true,
                ProxyPort = (int)Math.Clamp(_portBox.Value, 1, 65535),
                DohEndpoint = string.IsNullOrWhiteSpace(_dohBox.Text)
                    ? new AppSettings().DohEndpoint
                    : _dohBox.Text.Trim(),
                ImageConcurrency = (int)Math.Clamp(_concurrencyBox.Value, 1, 12),
                CreateZip = _zipBox.IsChecked == true,
            };
            AppServices.Instance.SaveSettings(settings);
            _dirBox.Text = directory;
            Ui.ShowInfo(_info, "设置已保存，新的网络配置已生效。", InfoBarSeverity.Success);
        }
        catch (Exception ex)
        {
            Ui.ShowInfo(_info, "保存失败：" + ex.Message, InfoBarSeverity.Error);
        }
    }
}
