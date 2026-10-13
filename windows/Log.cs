using System;
using System.IO;
using System.Text;

namespace PPTClicker
{
    /// <summary>极简文件日志。</summary>
    public static class Log
    {
        private static readonly object Gate = new object();
        private static string path = "";
        private static bool enabled = true;

        public static void Configure(bool on, string target)
        {
            lock (Gate)
            {
                enabled = on;
                path = Config.Expand(target);
                if (!enabled || string.IsNullOrEmpty(path)) return;
                try
                {
                    string dir = Path.GetDirectoryName(path);
                    if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
                }
                catch { }
            }
        }

        public static string Path_ { get { return path; } }

        public static void Write(string message)
        {
            lock (Gate)
            {
                if (!enabled || string.IsNullOrEmpty(path)) return;
                try
                {
                    string line = "[" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff") + "] " + message + Environment.NewLine;
                    File.AppendAllText(path, line, new UTF8Encoding(false));
                }
                catch { }
            }
        }
    }
}
