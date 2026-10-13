using System;
using System.Runtime.InteropServices;

namespace PPTClicker
{
    /// <summary>
    /// 低级鼠标钩子（WH_MOUSE_LL）：这就是 Windows 上对应 macOS CGEventTap 的东西。
    /// 命中映射就返回 1 吞掉事件，再用 SendInput 补一个方向键。
    /// </summary>
    public sealed class MouseHook : IDisposable
    {
        private Native.HookProc proc;      // 必须持有引用，否则会被 GC 回收导致钩子失效
        private IntPtr handle = IntPtr.Zero;

        public bool Enabled;
        public bool Bypass;                 // 菜单打开期间暂停拦截
        public bool Verbose;
        public bool MiddleDoubleClickToggles = true;
        public double DoubleClickInterval = 0.45;
        public double ThrottleInterval = 0.3;
        public bool ScrollDownIsPositive = false;
        public Bindings Bindings = new Bindings();

        /// <summary>由外部判断当前是否应该生效（scope / 白名单 / 排除系统窗口）。</summary>
        public Func<bool> ScopeAllows;

        /// <summary>执行一个动作（发按键）。参数：动作、日志用描述。</summary>
        public Action<ClickerAction, string> Perform;

        /// <summary>双击滚轮键请求切换模式。</summary>
        public Action ToggleRequested;

        // 自检/统计
        public long SeenEvents;
        public long Intercepted;
        public long LastEventInjected;

        private readonly Throttle scrollThrottle = new Throttle();
        private MouseKind? lastScrollKind;
        private readonly DoubleClickDetector middleDetector = new DoubleClickDetector();
        private bool pendingLeftUp;
        private bool pendingRightUp;
        private bool pendingMiddleUp;
        private bool pendingXUp;

        public bool Installed { get { return handle != IntPtr.Zero; } }

        public bool Install()
        {
            if (Installed) return true;
            proc = Callback;
            handle = Native.SetWindowsHookEx(Native.WH_MOUSE_LL, proc, Native.GetModuleHandle(null), 0);
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

        public void ResetPending()
        {
            pendingLeftUp = false;
            pendingRightUp = false;
            pendingMiddleUp = false;
            pendingXUp = false;
            scrollThrottle.Reset();
            middleDetector.Reset();
        }

        private IntPtr Callback(int nCode, IntPtr wParam, IntPtr lParam)
        {
            // 钩子回调里抛出异常会直接崩掉进程，所以全程兜住
            try
            {
                if (nCode < 0) return Native.CallNextHookEx(handle, nCode, wParam, lParam);

                Native.MSLLHOOKSTRUCT data = (Native.MSLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(Native.MSLLHOOKSTRUCT));
                SeenEvents++;
                LastEventInjected = data.dwExtraInfo == Native.MagicExtraInfo ? 1 : 0;
                if (LastEventInjected == 1) return Native.CallNextHookEx(handle, nCode, wParam, lParam);

                int msg = wParam.ToInt32();

                // 双击滚轮键切换：必须在"是否开启"之前判断，否则关着的时候没法用它开启
                if (MiddleDoubleClickToggles && msg == Native.WM_MBUTTONDOWN)
                {
                    if (middleDetector.Register(Native.Now(), DoubleClickInterval))
                    {
                        if (Verbose) Log.Write("滚轮键双击 → 切换模式");
                        Action toggle = ToggleRequested;
                        if (toggle != null) toggle();
                        return (IntPtr)1;
                    }
                }

                if (Bypass) return Native.CallNextHookEx(handle, nCode, wParam, lParam);
                if (!Enabled) { ResetPending(); return Native.CallNextHookEx(handle, nCode, wParam, lParam); }

                Func<bool> scope = ScopeAllows;
                if (scope != null && !scope()) return Native.CallNextHookEx(handle, nCode, wParam, lParam);

                switch (msg)
                {
                    case Native.WM_LBUTTONDOWN:
                        if (HandleButton(MouseKind.LeftClick)) { pendingLeftUp = true; return (IntPtr)1; }
                        return Native.CallNextHookEx(handle, nCode, wParam, lParam);
                    case Native.WM_LBUTTONUP:
                        if (pendingLeftUp) { pendingLeftUp = false; return (IntPtr)1; }
                        return Native.CallNextHookEx(handle, nCode, wParam, lParam);

                    case Native.WM_RBUTTONDOWN:
                        if (HandleButton(MouseKind.RightClick)) { pendingRightUp = true; return (IntPtr)1; }
                        return Native.CallNextHookEx(handle, nCode, wParam, lParam);
                    case Native.WM_RBUTTONUP:
                        if (pendingRightUp) { pendingRightUp = false; return (IntPtr)1; }
                        return Native.CallNextHookEx(handle, nCode, wParam, lParam);

                    case Native.WM_MBUTTONDOWN:
                        if (HandleButton(MouseKind.MiddleClick)) { pendingMiddleUp = true; return (IntPtr)1; }
                        return Native.CallNextHookEx(handle, nCode, wParam, lParam);
                    case Native.WM_MBUTTONUP:
                        if (pendingMiddleUp) { pendingMiddleUp = false; return (IntPtr)1; }
                        return Native.CallNextHookEx(handle, nCode, wParam, lParam);

                    case Native.WM_XBUTTONDOWN:
                    {
                        int button = (int)((data.mouseData >> 16) & 0xFFFF);
                        MouseKind kind = button == 1 ? MouseKind.BackButton : MouseKind.ForwardButton;
                        if (HandleButton(kind)) { pendingXUp = true; return (IntPtr)1; }
                        return Native.CallNextHookEx(handle, nCode, wParam, lParam);
                    }
                    case Native.WM_XBUTTONUP:
                        if (pendingXUp) { pendingXUp = false; return (IntPtr)1; }
                        return Native.CallNextHookEx(handle, nCode, wParam, lParam);

                    case Native.WM_MOUSEWHEEL:
                    {
                        short delta = unchecked((short)((data.mouseData >> 16) & 0xFFFF));
                        return HandleScroll(0, delta, wParam, nCode, lParam);
                    }
                    case Native.WM_MOUSEHWHEEL:
                    {
                        short delta = unchecked((short)((data.mouseData >> 16) & 0xFFFF));
                        return HandleScroll(delta, 0, wParam, nCode, lParam);
                    }
                }
            }
            catch (Exception ex)
            {
                try { Log.Write("鼠标钩子异常：" + ex.Message); } catch { }
            }
            return Native.CallNextHookEx(handle, nCode, wParam, lParam);
        }

        private bool HandleButton(MouseKind kind)
        {
            ClickerAction action = Bindings.ActionFor(kind);
            if (!Mapping.Swallows(action)) return false;
            Intercepted++;
            Action<ClickerAction, string> perform = Perform;
            if (perform != null) perform(action, Mapping.Describe(kind));
            return true;
        }

        private IntPtr HandleScroll(double axis1, double axis2, IntPtr wParam, int nCode, IntPtr lParam)
        {
            MouseKind? kind = Mapping.ScrollKind(axis1, axis2, ScrollDownIsPositive);
            if (!kind.HasValue) return Native.CallNextHookEx(handle, nCode, wParam, lParam);

            ClickerAction action = Bindings.ActionFor(kind.Value);
            if (!Mapping.Swallows(action)) return Native.CallNextHookEx(handle, nCode, wParam, lParam);

            double now = Native.Now();
            if (kind.Value != lastScrollKind)
            {
                // 方向一变立刻放行，方便快速来回翻
                scrollThrottle.Reset();
                lastScrollKind = kind.Value;
            }
            if (scrollThrottle.Allow(now, ThrottleInterval))
            {
                Intercepted++;
                Action<ClickerAction, string> perform = Perform;
                string label = "滚轮(axis=" + (axis1 >= 0 ? "+" : "") + ((int)axis1) + ")";
                if (perform != null) perform(action, label);
            }
            return (IntPtr)1;
        }
    }
}
