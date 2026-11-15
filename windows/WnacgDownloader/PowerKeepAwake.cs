using System.Runtime.InteropServices;

namespace WnacgDownloader;

/// <summary>
/// Keeps Windows awake while a long download is running. Without this the
/// machine can enter connected-standby in the middle of the first download
/// and the network tasks stop.
/// </summary>
internal static class PowerKeepAwake
{
    private const uint EsContinuous = 0x80000000;
    private const uint EsSystemRequired = 0x00000001;

    [DllImport("kernel32.dll")]
    private static extern uint SetThreadExecutionState(uint esFlags);

    public static void Acquire()
    {
        try
        {
            SetThreadExecutionState(EsContinuous | EsSystemRequired);
        }
        catch
        {
            // Power management is best-effort.
        }
    }

    public static void Release()
    {
        try
        {
            SetThreadExecutionState(EsContinuous);
        }
        catch
        {
            // Power management is best-effort.
        }
    }
}
