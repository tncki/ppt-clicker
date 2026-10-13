using System;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;

namespace PPTClicker
{
    /// <summary>前台窗口/进程查询（用于 scope=apps 与排除系统窗口）。</summary>
    public static class Foreground
    {
        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        /// <summary>返回前台进程的可执行文件名，例如 "POWERPNT.EXE"；取不到时返回空串。</summary>
        public static string ProcessName()
        {
            try
            {
                IntPtr hwnd = GetForegroundWindow();
                if (hwnd == IntPtr.Zero) return "";
                uint pid;
                GetWindowThreadProcessId(hwnd, out pid);
                if (pid == 0) return "";
                using (Process p = Process.GetProcessById((int)pid))
                {
                    return p.ProcessName + ".exe";
                }
            }
            catch { return ""; }
        }
    }

    /// <summary>托盘/窗口图标：按状态现画，避免额外资源文件。</summary>
    public static class AppIcons
    {
        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool DestroyIcon(IntPtr hIcon);

        public static Icon Create(bool on, bool warning)
        {
            using (Bitmap bmp = new Bitmap(32, 32))
            {
                using (Graphics g = Graphics.FromImage(bmp))
                {
                    g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                    g.Clear(Color.Transparent);

                    Color fill;
                    if (warning) fill = Color.FromArgb(255, 149, 0);
                    else if (on) fill = Color.FromArgb(52, 199, 89);
                    else fill = Color.FromArgb(150, 160, 172);

                    using (SolidBrush b = new SolidBrush(fill))
                        g.FillEllipse(b, new Rectangle(1, 1, 30, 30));

                    // 中间一个白色右箭头
                    using (SolidBrush w = new SolidBrush(Color.White))
                    {
                        g.FillRectangle(w, new Rectangle(9, 14, 9, 4));
                        Point[] tri = new Point[] {
                            new Point(17, 9), new Point(25, 16), new Point(17, 23)
                        };
                        g.FillPolygon(w, tri);
                    }
                }

                IntPtr handle = bmp.GetHicon();
                try
                {
                    // Icon.FromHandle 不拥有句柄，克隆一份后把原句柄释放掉，避免泄漏
                    using (Icon temp = Icon.FromHandle(handle))
                    {
                        return (Icon)temp.Clone();
                    }
                }
                finally
                {
                    DestroyIcon(handle);
                }
            }
        }
    }
}
