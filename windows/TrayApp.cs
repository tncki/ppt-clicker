using System;
using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;
using Microsoft.Win32;

namespace PPTClicker
{
    /// <summary>用来收 WM_HOTKEY 的隐藏消息窗口。</summary>
    public sealed class HotkeyWindow : NativeWindow, IDisposable
    {
        public event Action Pressed;

        public HotkeyWindow()
        {
            CreateHandle(new CreateParams());
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == Native.WM_HOTKEY)
            {
                Action handler = Pressed;
                if (handler != null) handler();
            }
            base.WndProc(ref m);
        }

        public void Dispose()
        {
            DestroyHandle();
        }
    }

    /// <summary>托盘应用主体：钩子、快捷键、指示灯、配置、开机自启。</summary>
    public sealed class TrayApp : ApplicationContext
    {
        private const int HotkeyId = 1;
        private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string RunValueName = "PPTClicker";

        private Config config = new Config();
        private UiState state = new UiState();
        private readonly MouseHook mouseHook = new MouseHook();
        private readonly KeyboardHook keyboardHook = new KeyboardHook();
        private HotkeyWindow hotkeyWindow;
        private NotifyIcon tray;
        private ContextMenuStrip menu;
        private IndicatorForm indicator;
        private Timer refreshTimer;

        private bool enabled;
        private bool hotkeyRegistered;
        private double lastToggleAt = double.NegativeInfinity;

        private Icon iconOn;
        private Icon iconOff;
        private Icon iconWarning;
        private Icon currentIcon;

        private ToolStripMenuItem headerItem;
        private ToolStripMenuItem toggleItem;
        private ToolStripMenuItem closeHintItem;
        private ToolStripMenuItem scopeItem;
        private ToolStripMenuItem indicatorItem;
        private ToolStripMenuItem hookItem;
        private ToolStripMenuItem hotkeyItem;
        private ToolStripMenuItem statsItem;
        private ToolStripMenuItem debugItem;
        private ToolStripMenuItem autostartItem;

        public TrayApp()
        {
            config = Config.Load();
            state = UiState.Load();
            Log.Configure(config.DebugLog, config.LogPath);
            Log.Write("启动 PPT Clicker " + VersionString + "（config: " + Config.ConfigPath() + "）");
            Log.Write("滚轮方向：设置=" + config.ScrollDirection.ToString().ToLowerInvariant()
                + " → 物理向下滚时 delta " + (Mapping.PhysicalDownIsPositive(config.ScrollDirection) ? "为正" : "为负"));

            iconOn = AppIcons.Create(true, false);
            iconOff = AppIcons.Create(false, false);
            iconWarning = AppIcons.Create(false, true);

            BuildMenu();
            BuildTray();
            WireHooks();

            hotkeyWindow = new HotkeyWindow();
            hotkeyWindow.Pressed += delegate { Toggle(L.S("快捷键", "shortcut")); };
            RegisterHotkey();

            mouseHook.Enabled = enabled;
            ApplyIndicatorVisibility();

            refreshTimer = new Timer();
            refreshTimer.Interval = 1500;
            refreshTimer.Tick += delegate { Tick(); };
            refreshTimer.Start();

            UpdateUi();
            Log.Write("事件钩子：" + (mouseHook.Installed ? "已安装" : "安装失败")
                + "；全局快捷键：" + (hotkeyRegistered ? "已注册 " + config.Hotkey.Display() : "注册失败"));
        }

        public static string VersionString
        {
            get
            {
                try { return Application.ProductVersion; }
                catch { return "dev"; }
            }
        }

        // ---------- 菜单 / 托盘 ----------

        private void BuildMenu()
        {
            menu = new ContextMenuStrip();

            headerItem = new ToolStripMenuItem("");
            headerItem.Enabled = false;
            menu.Items.Add(headerItem);

            toggleItem = new ToolStripMenuItem("");
            toggleItem.Click += delegate { Toggle(L.S("菜单", "menu")); };
            menu.Items.Add(toggleItem);

            closeHintItem = new ToolStripMenuItem("");
            closeHintItem.Enabled = false;
            menu.Items.Add(closeHintItem);

            menu.Items.Add(new ToolStripSeparator());

            scopeItem = new ToolStripMenuItem(L.S("仅在前台是演示程序时生效", "Only inside presentation apps"));
            scopeItem.Click += delegate
            {
                config.Scope = config.Scope == "apps" ? "global" : "apps";
                Log.Write("生效范围：" + (config.Scope == "apps" ? "仅演示程序" : "全局"));
                UpdateUi();
            };
            menu.Items.Add(scopeItem);

            indicatorItem = new ToolStripMenuItem(L.S("显示屏幕角落的指示灯", "Show corner indicator dot"));
            indicatorItem.Click += delegate
            {
                config.ShowIndicator = !config.ShowIndicator;
                ApplyIndicatorVisibility();
                Log.Write("角落指示灯：" + (config.ShowIndicator ? "显示" : "隐藏"));
                UpdateUi();
            };
            menu.Items.Add(indicatorItem);

            menu.Items.Add(new ToolStripSeparator());

            ToolStripMenuItem reload = new ToolStripMenuItem(L.S("重新载入配置", "Reload config"));
            reload.Click += delegate { ReloadConfig(); };
            menu.Items.Add(reload);

            ToolStripMenuItem openConfig = new ToolStripMenuItem(L.S("打开配置文件…", "Open config file…"));
            openConfig.Click += delegate { OpenConfigFile(); };
            menu.Items.Add(openConfig);

            ToolStripMenuItem openLog = new ToolStripMenuItem(L.S("打开日志…", "Open log…"));
            openLog.Click += delegate { OpenLogFile(); };
            menu.Items.Add(openLog);

            menu.Items.Add(new ToolStripSeparator());

            hookItem = new ToolStripMenuItem("");
            hookItem.Enabled = false;
            menu.Items.Add(hookItem);

            hotkeyItem = new ToolStripMenuItem("");
            hotkeyItem.Enabled = false;
            menu.Items.Add(hotkeyItem);

            statsItem = new ToolStripMenuItem("");
            statsItem.Enabled = false;
            menu.Items.Add(statsItem);

            debugItem = new ToolStripMenuItem(L.S("记录原始事件到日志（诊断用）", "Log raw events (diagnostics)"));
            debugItem.Click += delegate
            {
                config.DebugEvents = !config.DebugEvents;
                mouseHook.Verbose = config.DebugEvents;
                Log.Write("原始事件诊断日志：" + (config.DebugEvents ? "开启" : "关闭"));
                UpdateUi();
            };
            menu.Items.Add(debugItem);

            menu.Items.Add(new ToolStripSeparator());

            autostartItem = new ToolStripMenuItem(L.S("开机自动启动", "Launch at login"));
            autostartItem.Click += delegate { ToggleAutostart(); };
            menu.Items.Add(autostartItem);

            ToolStripMenuItem quit = new ToolStripMenuItem(L.S("退出", "Quit"));
            quit.Click += delegate { ExitThread(); };
            menu.Items.Add(quit);

            // 菜单打开期间暂停拦截，否则菜单点不动
            menu.Opening += delegate { mouseHook.Bypass = true; };
            menu.Closed += delegate { mouseHook.Bypass = false; };
        }

        private void BuildTray()
        {
            tray = new NotifyIcon();
            tray.ContextMenuStrip = menu;
            tray.Visible = true;
            tray.DoubleClick += delegate { Toggle(L.S("托盘图标", "tray icon")); };
        }

        // ---------- 钩子 / 快捷键 ----------

        private void WireHooks()
        {
            mouseHook.Bindings = config.Bindings;
            mouseHook.ScrollDownIsPositive = Mapping.PhysicalDownIsPositive(config.ScrollDirection);
            mouseHook.ThrottleInterval = config.ThrottleInterval;
            mouseHook.MiddleDoubleClickToggles = config.MiddleDoubleClickToggles;
            mouseHook.Verbose = config.DebugEvents;
            mouseHook.ScopeAllows = ScopeAllows;
            mouseHook.Perform = PerformAction;
            mouseHook.ToggleRequested = delegate { Toggle(L.S("滚轮键双击", "middle double-click")); };

            keyboardHook.ShouldHandleEscape = delegate { return enabled && config.EscapeDisables; };
            keyboardHook.EscapePressed = delegate { SetEnabled(false, "ESC"); };

            if (!mouseHook.Install()) Log.Write("鼠标钩子安装失败（SetWindowsHookEx 返回 0）");
            if (config.EscapeDisables && !keyboardHook.Install()) Log.Write("键盘钩子安装失败（ESC 关闭将不可用）");
        }

        private void RegisterHotkey()
        {
            if (hotkeyWindow == null) return;
            Native.UnregisterHotKey(hotkeyWindow.Handle, HotkeyId);
            hotkeyRegistered = Native.RegisterHotKey(
                hotkeyWindow.Handle, HotkeyId, config.Hotkey.NativeModifiers(), config.Hotkey.VirtualKey());
            if (!hotkeyRegistered) Log.Write("全局快捷键注册失败（可能已被其它程序占用）：" + config.Hotkey.Display());
        }

        private void PerformAction(ClickerAction action, string label)
        {
            byte? vk = Mapping.VirtualKey(action);
            if (vk.HasValue)
            {
                Native.SendKey(vk.Value);
                if (config.DebugEvents || mouseHook.Intercepted <= 5)
                    Log.Write(label + " → " + action.ToString().ToLowerInvariant() + "（vk=0x" + vk.Value.ToString("X2") + "）");
            }
            else if (config.DebugEvents)
            {
                Log.Write(label + " → none（已拦截，无动作）");
            }
        }

        private bool ScopeAllows()
        {
            string process = Foreground.ProcessName();
            if (IsSystemWindow(process)) return false;   // 系统设置/开始菜单等一律放行
            if (config.Scope == "apps")
            {
                foreach (AppRule rule in config.Apps)
                    if (rule.Matches(process)) return true;
                return false;
            }
            return true;
        }

        private static bool IsSystemWindow(string process)
        {
            if (string.IsNullOrEmpty(process)) return false;
            switch (process.ToLowerInvariant())
            {
                case "systemsettings.exe":
                case "shellexperiencehost.exe":
                case "startmenuexperiencehost.exe":
                case "searchhost.exe":
                case "applicationframehost.exe":
                case "consent.exe":
                    return true;
                default:
                    return false;
            }
        }

        // ---------- 开关 ----------

        private void Toggle(string reason)
        {
            double now = Native.Now();
            if (now - lastToggleAt < 0.35) return;   // 防抖
            lastToggleAt = now;
            SetEnabled(!enabled, reason);
        }

        private void SetEnabled(bool value, string reason)
        {
            if (value == enabled) return;
            enabled = value;
            mouseHook.Enabled = value;
            if (!value) mouseHook.ResetPending();
            Log.Write("翻页笔模式：" + (value ? "开启" : "关闭") + "（来自" + reason + "）");
            UpdateUi();
        }

        // ---------- 指示灯 ----------

        private void ApplyIndicatorVisibility()
        {
            if (config.ShowIndicator)
            {
                if (indicator == null)
                {
                    indicator = new IndicatorForm();
                    indicator.Clicked += delegate { Toggle(L.S("指示灯", "indicator")); };
                    indicator.RightClicked += delegate { menu.Show(Cursor.Position); };
                    indicator.Moved += delegate(Point p)
                    {
                        state.IndicatorX = p.X;
                        state.IndicatorY = p.Y;
                        state.Save();
                    };
                    PositionIndicator();
                }
                indicator.SetState(enabled, !mouseHook.Installed);
                indicator.Show();
            }
            else if (indicator != null)
            {
                indicator.Hide();
            }
        }

        private void PositionIndicator()
        {
            if (indicator == null) return;
            Screen screen = Screen.PrimaryScreen;
            int right = screen != null ? screen.WorkingArea.Right : 1280;
            int top = screen != null ? screen.WorkingArea.Top : 0;
            int x = state.IndicatorX >= 0 ? state.IndicatorX : right - indicator.Width - 12;
            int y = state.IndicatorY >= 0 ? state.IndicatorY : top + 12;
            if (!IsOnAnyScreen(x, y))
            {
                x = right - indicator.Width - 12;
                y = top + 12;
            }
            indicator.Location = new Point(x, y);
        }

        private static bool IsOnAnyScreen(int x, int y)
        {
            foreach (Screen s in Screen.AllScreens)
            {
                if (s.Bounds.Contains(x + 4, y + 4)) return true;
            }
            return false;
        }

        // ---------- 状态刷新 ----------

        private void Tick()
        {
            if (!mouseHook.Installed) mouseHook.Install();
            if (config.EscapeDisables && !keyboardHook.Installed) keyboardHook.Install();
            UpdateUi();
        }

        private void UpdateUi()
        {
            bool working = mouseHook.Installed;
            Icon icon = working ? (enabled ? iconOn : iconOff) : iconWarning;
            if (tray != null)
            {
                tray.Icon = icon;
                string tooltip = L.S("PPT Clicker：", "PPT Clicker: ") + (enabled ? L.S("已开启", "ON") : L.S("已关闭", "OFF"))
                    + "（" + config.Hotkey.Display() + L.S(" 切换）", " to toggle)");
                if (tooltip.Length > 62) tooltip = tooltip.Substring(0, 62);
                tray.Text = tooltip;
            }
            currentIcon = icon;

            if (indicator != null) indicator.SetState(enabled, !working);

            if (headerItem != null)
            {
                headerItem.Text = L.S("翻页笔模式：", "Clicker: ") + (enabled ? L.S("已开启", "ON") : L.S("已关闭", "OFF"));
                toggleItem.Text = L.S("切换翻页笔模式", "Toggle clicker mode") + "（" + config.Hotkey.Display() + "）";
                toggleItem.Checked = enabled;
                closeHintItem.Text = L.S("关闭方式：再按一次快捷键 ・ ESC ・ 双击滚轮键",
                                          "To turn off: press the shortcut again / ESC / double-click the wheel");
                scopeItem.Checked = config.Scope == "apps";
                indicatorItem.Checked = config.ShowIndicator;
                hookItem.Text = L.S("事件钩子：", "Mouse hook: ") + (working ? L.S("正常", "active") : L.S("未安装", "not installed"));
                hotkeyItem.Text = L.S("全局快捷键 ", "Global shortcut ") + config.Hotkey.Display() + "："
                    + (hotkeyRegistered ? L.S("已注册", "registered") : L.S("注册失败", "registration failed"));
                statsItem.Text = L.S("已拦截事件：", "Events intercepted: ") + mouseHook.Intercepted;
                debugItem.Checked = config.DebugEvents;
                autostartItem.Checked = AutostartInstalled();
            }
        }

        // ---------- 配置 / 文件 ----------

        private void ReloadConfig()
        {
            config = Config.Load();
            ApplyConfigToHooks();
            Log.Configure(config.DebugLog, config.LogPath);
            RegisterHotkey();
            ApplyIndicatorVisibility();
            Log.Write("已重新载入配置：" + Config.ConfigPath());
            UpdateUi();
        }

        private void ApplyConfigToHooks()
        {
            mouseHook.Bindings = config.Bindings;
            mouseHook.ScrollDownIsPositive = Mapping.PhysicalDownIsPositive(config.ScrollDirection);
            mouseHook.ThrottleInterval = config.ThrottleInterval;
            mouseHook.MiddleDoubleClickToggles = config.MiddleDoubleClickToggles;
            mouseHook.Verbose = config.DebugEvents;
        }

        private void OpenConfigFile()
        {
            try
            {
                string path = Config.ConfigPath();
                if (!System.IO.File.Exists(path)) Config.Save(config);
                Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
            }
            catch (Exception ex) { Log.Write("打开配置文件失败：" + ex.Message); }
        }

        private void OpenLogFile()
        {
            try
            {
                string path = Config.Expand(config.LogPath);
                if (!System.IO.File.Exists(path)) System.IO.File.WriteAllText(path, "");
                Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
            }
            catch (Exception ex) { Log.Write("打开日志失败：" + ex.Message); }
        }

        // ---------- 开机自启 ----------

        private static bool AutostartInstalled()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(RunKeyPath, false))
                {
                    return key != null && key.GetValue(RunValueName) != null;
                }
            }
            catch { return false; }
        }

        private void ToggleAutostart()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(RunKeyPath, true))
                {
                    if (key == null) return;
                    if (AutostartInstalled())
                    {
                        key.DeleteValue(RunValueName, false);
                        Log.Write("已取消开机自启");
                    }
                    else
                    {
                        string exe = Environment.ProcessPath;
                        key.SetValue(RunValueName, "\"" + exe + "\"");
                        Log.Write("已设置开机自启：" + exe);
                    }
                }
            }
            catch (Exception ex) { Log.Write("设置开机自启失败：" + ex.Message); }
            UpdateUi();
        }

        // ---------- 退出 ----------

        protected override void ExitThreadCore()
        {
            Log.Write("退出");
            try
            {
                if (refreshTimer != null) refreshTimer.Stop();
                if (tray != null) { tray.Visible = false; tray.Dispose(); }
                mouseHook.Dispose();
                keyboardHook.Dispose();
                if (hotkeyWindow != null)
                {
                    Native.UnregisterHotKey(hotkeyWindow.Handle, HotkeyId);
                    hotkeyWindow.Dispose();
                }
                if (indicator != null) indicator.Dispose();
            }
            catch { }
            base.ExitThreadCore();
        }
    }
}
