using System;
using System.IO;
using System.Threading;
using System.Windows.Forms;

namespace PPTClicker
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            if (HasFlag(args, "--selftest")) return SelfTest.Run();
            if (HasFlag(args, "--hooktest")) return HookTest.Run();
            if (HasFlag(args, "--print-default-config"))
            {
                WriteConsole(Config.DefaultJson);
                return 0;
            }

            bool createdNew;
            using (Mutex mutex = new Mutex(true, "PPTClicker.SingleInstance", out createdNew))
            {
                if (!createdNew) return 0;   // 已有实例在运行
                try { Application.SetHighDpiMode(HighDpiMode.PerMonitorV2); } catch { }
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new TrayApp());
            }
            return 0;
        }

        private static bool HasFlag(string[] args, string flag)
        {
            if (args == null) return false;
            foreach (string a in args)
            {
                if (string.Equals(a, flag, StringComparison.OrdinalIgnoreCase)) return true;
            }
            return false;
        }

        /// <summary>
        /// 命令行模式下把结果写出来：WinExe 没有自己的控制台，
        /// 这里尝试附着到父进程控制台（从 cmd/PowerShell 运行时可见）。
        /// </summary>
        public static void WriteConsole(string text)
        {
            try
            {
                bool attached = Native.AttachConsole(Native.ATTACH_PARENT_PROCESS);
                if (!attached) attached = Native.AllocConsole();
                if (attached)
                {
                    StreamWriter writer = new StreamWriter(Console.OpenStandardOutput());
                    writer.AutoFlush = true;
                    Console.SetOut(writer);
                }
            }
            catch { }
            try { Console.WriteLine(text); } catch { }
        }
    }
}
