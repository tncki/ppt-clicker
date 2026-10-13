using System;
using System.Runtime.InteropServices;

namespace PPTClicker
{
    /// <summary>
    /// 低级键盘钩子，只用来"旁听" ESC —— 永远调用 CallNextHookEx 放行，
    /// 所以 PowerPoint 自己的"按 ESC 结束放映"不受影响。
    /// </summary>
    public sealed class KeyboardHook : IDisposable
    {
        private const int WM_KEYDOWN = 0x0100;
        private const int WM_SYSKEYDOWN = 0x0104;

        private Native.HookProc proc;
        private IntPtr handle = IntPtr.Zero;

        public Func<bool> ShouldHandleEscape;
        public Action EscapePressed;

        // 自检统计
        public long SeenKeyDowns;
        public ushort LastVirtualKey;

        public bool Installed { get { return handle != IntPtr.Zero; } }

        public bool Install()
        {
            if (Installed) return true;
            proc = Callback;
            handle = Native.SetWindowsHookEx(Native.WH_KEYBOARD_LL, proc, Native.GetModuleHandle(null), 0);
            return Installed;
        }

        public void Uninstall()
        {
            if (handle != IntPtr.Zero)
            {
                Native.UnhookWindowsHookEx(handle);
                handle = IntPtr.Zero;
            }
        }

        public void Dispose() { Uninstall(); }

        private IntPtr Callback(int nCode, IntPtr wParam, IntPtr lParam)
        {
            try
            {
                if (nCode >= 0)
                {
                    Native.KBDLLHOOKSTRUCT data = (Native.KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(Native.KBDLLHOOKSTRUCT));
                    int msg = wParam.ToInt32();
                    bool isDown = msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN;
                    if (isDown)
                    {
                        SeenKeyDowns++;
                        LastVirtualKey = (ushort)data.vkCode;
                        bool ours = data.dwExtraInfo == Native.MagicExtraInfo;
                        if (!ours && data.vkCode == Native.VK_ESCAPE)
                        {
                            Func<bool> gate = ShouldHandleEscape;
                            if (gate != null && gate())
                            {
                                Action handler = EscapePressed;
                                if (handler != null) handler();
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                try { Log.Write("键盘钩子异常：" + ex.Message); } catch { }
            }
            // 只旁听，永远放行
            return Native.CallNextHookEx(handle, nCode, wParam, lParam);
        }
    }
}
