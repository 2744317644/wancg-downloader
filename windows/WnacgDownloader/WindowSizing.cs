using System.Runtime.InteropServices;

namespace WnacgDownloader;

/// <summary>
/// Enforces a minimum Win32 window size. AppWindow.Changed is not reliably
/// raised for user resizes in the unpackaged WinUI 3 app, so enforce it at
/// WM_GETMINMAXINFO instead; otherwise the NavigationView plus cards can be
/// clipped at small sizes.
/// </summary>
internal static class WindowSizing
{
    private const int WmGetMinMaxInfo = 0x0024;
    private const uint SubclassId = 1;
    private const int MinWidth = 1100;
    private const int MinHeight = 700;

    private delegate IntPtr SubclassProc(
        IntPtr hWnd,
        uint msg,
        IntPtr wParam,
        IntPtr lParam,
        UIntPtr uIdSubclass,
        UIntPtr dwRefData
    );

    [StructLayout(LayoutKind.Sequential)]
    private struct Point
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MinMaxInfo
    {
        public Point Reserved;
        public Point MaxSize;
        public Point MaxPosition;
        public Point MinTrackSize;
        public Point MaxTrackSize;
    }

    [DllImport("comctl32.dll", SetLastError = true)]
    private static extern bool SetWindowSubclass(
        IntPtr hWnd,
        SubclassProc pfnSubclass,
        UIntPtr uIdSubclass,
        UIntPtr dwRefData
    );

    [DllImport("comctl32.dll")]
    private static extern IntPtr DefSubclassProc(
        IntPtr hWnd,
        uint msg,
        IntPtr wParam,
        IntPtr lParam
    );

    private static SubclassProc? _proc;

    public static void Apply(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero)
        {
            return;
        }

        _proc = WndProc;
        SetWindowSubclass(hwnd, _proc, (UIntPtr)SubclassId, UIntPtr.Zero);
    }

    private static IntPtr WndProc(
        IntPtr hWnd,
        uint msg,
        IntPtr wParam,
        IntPtr lParam,
        UIntPtr uIdSubclass,
        UIntPtr dwRefData
    )
    {
        if (msg == WmGetMinMaxInfo)
        {
            var info = Marshal.PtrToStructure<MinMaxInfo>(lParam);
            info.MinTrackSize.X = Math.Max(info.MinTrackSize.X, MinWidth);
            info.MinTrackSize.Y = Math.Max(info.MinTrackSize.Y, MinHeight);
            Marshal.StructureToPtr(info, lParam, false);
        }

        return DefSubclassProc(hWnd, msg, wParam, lParam);
    }
}
