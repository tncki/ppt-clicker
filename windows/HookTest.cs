using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows.Forms;

namespace PPTClicker
{
    /// <summary>
    /// 钩子链路自检：装上低级鼠标钩子 → 合成一次左键 →
    /// 期望钩子吞掉它并发出 → 键，键盘钩子应该看到这个按键。
    /// 这是在没有真人操作的情况下，对"拦截 + 合成按键"整条链路的验证。
    /// </summary>
    public static class HookTest
    {
        private static int failures;
        private static List<string> lines = new List<string>();

        public static string ReportPath
        {
            get { return Path.Combine(Path.GetTempPath(), "pptclicker-hooktest.txt"); }
        }

        private static void Check(bool ok, string name)
        {
            lines.Add((ok ? "  OK   " : "  FAIL ") + name);
            if (!ok) failures++;
        }

        public static int Run()
        {
            lines = new List<string>();
            failures = 0;
            lines.Add("PPT Clicker (Windows) 钩子链路自检");
            lines.Add("流程：安装 WH_MOUSE_LL → SendInput 合成左键 → 钩子应吞掉它并发出 → 键 → 键盘钩子应看到该按键");

            MouseHook mouse = new MouseHook();
            KeyboardHook keyboard = new KeyboardHook();
            try
            {
                mouse.Bindings = new Bindings();          // 左键 → 下一页
                mouse.ScrollDownIsPositive = Mapping.PhysicalDownIsPositive(ScrollDirectionSetting.Auto);
                mouse.Enabled = true;
                mouse.ScopeAllows = delegate { return true; };
                mouse.Perform = delegate(ClickerAction action, string label)
                {
                    byte? vk = Mapping.VirtualKey(action);
                    if (vk.HasValue) Native.SendKey(vk.Value);
                };

                Check(mouse.Install(), "鼠标钩子安装成功");
                Check(keyboard.Install(), "键盘钩子安装成功");
                if (!mouse.Installed || !keyboard.Installed)
                {
                    lines.Add("");
                    lines.Add("结果：钩子装不上，后续链路无法验证");
                    Write();
                    return 1;
                }

                Pump(250);
                Native.SendLeftClick(false);              // 不带标记：应被拦下并换成 → 键

                Stopwatch sw = Stopwatch.StartNew();
                while (sw.ElapsedMilliseconds < 2000 && !(mouse.SeenEvents > 0 && keyboard.SeenKeyDowns > 0))
                {
                    Application.DoEvents();
                    System.Threading.Thread.Sleep(10);
                }

                Check(mouse.SeenEvents > 0, "鼠标钩子收到了合成事件（SeenEvents=" + mouse.SeenEvents + "）");
                Check(mouse.Intercepted > 0, "左键被拦截并触发了动作（Intercepted=" + mouse.Intercepted + "）");
                Check(keyboard.SeenKeyDowns > 0, "键盘钩子看到了合成按键（SeenKeyDowns=" + keyboard.SeenKeyDowns + "）");
                Check(keyboard.LastVirtualKey == Native.VK_RIGHT,
                    "合成按键是 →（实际 vk=0x" + keyboard.LastVirtualKey.ToString("X2") + "）");
            }
            catch (Exception ex)
            {
                Check(false, "自检过程抛出异常：" + ex.Message);
            }
            finally
            {
                try { keyboard.Dispose(); } catch { }
                try { mouse.Dispose(); } catch { }
            }

            lines.Add("");
            lines.Add(failures == 0 ? "结果：全部通过" : "结果：" + failures + " 项失败");
            Write();
            return failures == 0 ? 0 : 1;
        }

        private static void Pump(int milliseconds)
        {
            Stopwatch sw = Stopwatch.StartNew();
            while (sw.ElapsedMilliseconds < milliseconds)
            {
                Application.DoEvents();
                System.Threading.Thread.Sleep(10);
            }
        }

        private static void Write()
        {
            string report = string.Join(Environment.NewLine, lines);
            try { File.WriteAllText(ReportPath, report, new UTF8Encoding(false)); } catch { }
            Program.WriteConsole(report);
            Program.WriteConsole("报告文件：" + ReportPath);
        }
    }
}
