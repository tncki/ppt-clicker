using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace PPTClicker
{
    /// <summary>无界面自测：验证映射、节流、配置解析、方向判定等纯逻辑。</summary>
    public static class SelfTest
    {
        private static int passed;
        private static int failed;
        private static readonly List<string> lines = new List<string>();

        public static string ReportPath
        {
            get { return Path.Combine(Path.GetTempPath(), "pptclicker-selftest.txt"); }
        }

        private static void Section(string title)
        {
            lines.Add("");
            lines.Add(title);
        }

        private static void Check(bool ok, string name)
        {
            if (ok) { passed++; lines.Add("  OK   " + name); }
            else { failed++; lines.Add("  FAIL " + name); }
        }

        public static int Run()
        {
            try
            {
                return RunBody();
            }
            catch (Exception ex)
            {
                failed++;
                lines.Add("  FAIL 自检过程抛出异常：" + ex.ToString());
                Finish();
                return 1;
            }
        }

        private static int RunBody()
        {
            lines.Add("PPT Clicker (Windows) 自测");

            Section("[1] 默认映射");
            Bindings b = new Bindings();
            Check(b.LeftClick == ClickerAction.Next, "左键 → 下一页");
            Check(b.RightClick == ClickerAction.Prev, "右键 → 上一页");
            Check(b.ScrollDown == ClickerAction.Next, "滚轮下 → 下一页");
            Check(b.ScrollUp == ClickerAction.Prev, "滚轮上 → 上一页");
            Check(b.MiddleClick == ClickerAction.Pass, "中键 → 放行（默认）");
            Check(b.ActionFor(MouseKind.LeftClick) == ClickerAction.Next, "ActionFor 路由正确");

            Section("[2] 动作 → 虚拟键");
            Check(Mapping.VirtualKey(ClickerAction.Next) == 0x27, "next → →(0x27)");
            Check(Mapping.VirtualKey(ClickerAction.Prev) == 0x25, "prev → ←(0x25)");
            Check(Mapping.VirtualKey(ClickerAction.PageDown) == 0x22, "pageDown → 0x22");
            Check(Mapping.VirtualKey(ClickerAction.PageUp) == 0x21, "pageUp → 0x21");
            Check(Mapping.VirtualKey(ClickerAction.Space) == 0x20, "space → 0x20");
            Check(Mapping.VirtualKey(ClickerAction.Black) == 0x42, "black → B(0x42)");
            Check(Mapping.VirtualKey(ClickerAction.Pass) == null && !Mapping.Swallows(ClickerAction.Pass), "pass 不发送按键且不拦截");
            Check(Mapping.VirtualKey(ClickerAction.None) == null && Mapping.Swallows(ClickerAction.None), "none 拦截但不发按键");
            Check(Mapping.Swallows(ClickerAction.Next), "next 拦截并发送按键");

            Section("[3] 节流");
            Throttle t = new Throttle();
            Check(t.Allow(100.0, 0.3), "首次触发允许");
            Check(!t.Allow(100.1, 0.3), "100ms 内连发被抑制");
            Check(!t.Allow(100.29, 0.3), "290ms 仍被抑制");
            Check(t.Allow(100.31, 0.3), "超过 300ms 恢复允许");
            t.Reset();
            Check(t.Allow(100.05, 0.3), "reset 后立即允许");

            Section("[4] 默认配置模板解析");
            Config cfg = Config.Parse(Config.DefaultJson);
            Check(cfg.Bindings.LeftClick == ClickerAction.Next, "模板 leftClick=next");
            Check(cfg.Bindings.ScrollUp == ClickerAction.Prev, "模板 scrollUp=prev");
            Check(cfg.Hotkey.Key == "p", "模板热键 key=p");
            Check(cfg.Hotkey.Display() == "Ctrl+Alt+Shift+P", "模板热键显示 Ctrl+Alt+Shift+P（实际 " + cfg.Hotkey.Display() + "）");
            Check(cfg.ScrollDirection == ScrollDirectionSetting.Auto, "模板 scrollDirection=auto");
            Check(cfg.ThrottleMs == 300, "模板 throttleMs=300");
            Check(cfg.Apps.Count >= 3, "模板含多个演示程序（实际 " + cfg.Apps.Count + "）");
            Check(cfg.EscapeDisables && cfg.MiddleDoubleClickToggles && cfg.ShowIndicator, "模板三项开关为默认开");
            bool hasPpt = false;
            foreach (AppRule r in cfg.Apps) if (r.Exe == "POWERPNT.EXE") hasPpt = true;
            Check(hasPpt, "模板包含 PowerPoint");

            Section("[5] 宽容解析（写错不影响其它项）");
            string partial = "{ \"bindings\": { \"leftClick\": \"pass\", \"scrollDown\": \"none\" },"
                + " \"hotkey\": { \"key\": \"k\", \"modifiers\": [\"control\", \"shift\"] },"
                + " \"scope\": \"apps\", \"unknown\": 123 }";
            Config p = Config.Parse(partial);
            Check(p.Bindings.LeftClick == ClickerAction.Pass, "覆盖 leftClick=pass");
            Check(p.Bindings.ScrollDown == ClickerAction.None, "覆盖 scrollDown=none");
            Check(p.Bindings.ScrollUp == ClickerAction.Prev, "未写的 scrollUp 保持默认 prev");
            Check(p.Bindings.RightClick == ClickerAction.Prev, "未写的 rightClick 保持默认 prev");
            Check(p.Hotkey.VirtualKey() == 0x4B, "热键 k 虚拟键正确");
            Check(p.Hotkey.Display() == "Ctrl+Shift+K", "热键显示 Ctrl+Shift+K（实际 " + p.Hotkey.Display() + "）");
            Check(p.Scope == "apps", "scope=apps");

            Section("[6] 非法值回退");
            string bogus = "{ \"bindings\": { \"leftClick\": \"这不是动作\", \"scrollUp\": \"\" },"
                + " \"hotkey\": { \"key\": \"不存在的键\" }, \"throttleMs\": -5 }";
            Config g = Config.Parse(bogus);
            Check(g.Bindings.LeftClick == ClickerAction.Next, "非法动作回退为默认 next");
            Check(g.Bindings.ScrollUp == ClickerAction.Prev, "非法动作回退为默认 prev");
            Check(g.Hotkey.Key == "p", "非法热键名回退为 p");
            Check(g.ThrottleMs == 300, "负数 throttleMs 回退为 300");

            Section("[6b] 热键安全兜底");
            Config noMods = Config.Parse("{ \"hotkey\": { \"key\": \"p\", \"modifiers\": [] } }");
            Check(noMods.Hotkey.NativeModifiers() != Native.MOD_NOREPEAT, "空修饰键被强制补回修饰键（避免裸按吞键）");
            Check(noMods.Hotkey.Display() == "Ctrl+Alt+Shift+P", "空修饰键兜底显示 Ctrl+Alt+Shift+P（实际 " + noMods.Hotkey.Display() + "）");
            Config shiftOnly = Config.Parse("{ \"hotkey\": { \"key\": \"p\", \"modifiers\": [\"shift\"] } }");
            Check(shiftOnly.Hotkey.Display() == "Shift+P", "只写 shift 时保留 Shift+P");

            Section("[7] 键名表");
            byte vk;
            Check(KeyNames.TryGet("p", out vk) && vk == 0x50, "p → 0x50");
            Check(KeyNames.TryGet("F12", out vk) && vk == 0x7B, "f12 → 0x7B（大小写不敏感）");
            Check(KeyNames.TryGet("space", out vk) && vk == 0x20, "space → 0x20");
            Check(KeyNames.TryGet("pagedown", out vk) && vk == 0x22, "pagedown → 0x22");
            Check(!KeyNames.TryGet("没有这个键", out vk), "未知键名返回 false");

            Section("[8] 演示程序白名单匹配");
            List<AppRule> apps = Config.DefaultApps();
            Check(MatchAny(apps, "POWERPNT.EXE"), "POWERPNT.EXE 命中");
            Check(MatchAny(apps, "powerpnt.exe"), "大小写不敏感");
            Check(!MatchAny(apps, "chrome.exe"), "chrome.exe 不命中");
            Check(!MatchAny(apps, ""), "空进程名不命中");

            Section("[9] 配置序列化往返");
            Config round = Config.Parse(cfg.ToJson());
            Check(round.Bindings.LeftClick == cfg.Bindings.LeftClick, "编码后仍能解回 leftClick");
            Check(round.Hotkey.Display() == cfg.Hotkey.Display(), "编码后仍能解回热键");
            Check(round.Apps.Count == cfg.Apps.Count, "编码后程序列表一致");
            Check(round.ScrollDirection == cfg.ScrollDirection, "编码后滚轮方向一致");

            Section("[10] 鼠标事件口径");
            Check(Enum.GetValues(typeof(MouseKind)).Length == 9, "共 9 种鼠标事件");
            Check(Mapping.Describe(MouseKind.ScrollDown) == "滚轮下", "事件名称正确");

            Section("[11] 滚轮方向（Windows：向前滚 delta>0）");
            Check(Mapping.ScrollKind(120, 0, false) == MouseKind.ScrollUp, "delta=+120 → 物理向上滚");
            Check(Mapping.ScrollKind(-120, 0, false) == MouseKind.ScrollDown, "delta=-120 → 物理向下滚");
            Check(Mapping.ScrollKind(-120, 0, true) == MouseKind.ScrollUp, "inverted 时方向翻转");
            Check(Mapping.ScrollKind(0, -2, false) == MouseKind.ScrollLeft, "横向 -2 → 向左滚");
            Check(Mapping.ScrollKind(0, 2, false) == MouseKind.ScrollRight, "横向 +2 → 向右滚（Windows 约定）");
            Check(Mapping.ScrollKind(5, 1, false) == MouseKind.ScrollUp, "纵向优先于横向");
            Check(Mapping.ScrollKind(0, 0, false) == null, "零位移不产生动作");
            Bindings d = new Bindings();
            Check(d.ActionFor(Mapping.ScrollKind(-120, 0, false).Value) == ClickerAction.Next, "向下滚 → 下一页（关键回归）");
            Check(d.ActionFor(Mapping.ScrollKind(120, 0, false).Value) == ClickerAction.Prev, "向上滚 → 上一页");

            Section("[11b] 方向自动判定");
            Check(!Mapping.PhysicalDownIsPositive(ScrollDirectionSetting.Auto), "auto：Windows 常规滚轮，向下滚 delta 为负");
            Check(!Mapping.PhysicalDownIsPositive(ScrollDirectionSetting.Normal), "normal：向下滚 delta 为负");
            Check(Mapping.PhysicalDownIsPositive(ScrollDirectionSetting.Inverted), "inverted：向下滚 delta 为正");

            Section("[12] 双击滚轮键检测");
            DoubleClickDetector det = new DoubleClickDetector();
            Check(!det.Register(100.0, 0.45), "第 1 下不算双击");
            Check(det.Register(100.2, 0.45), "200ms 内的第 2 下 = 双击");
            Check(!det.Register(100.3, 0.45), "刚触发完，冷却期内不再触发");
            Check(!det.Register(100.6, 0.45), "冷却期内连按也只算一次");
            Check(!det.Register(101.0, 0.45), "冷却结束后这是新序列的第 1 下");
            Check(det.Register(101.2, 0.45), "随后 200ms 内构成新的双击");

            Section("[13] 开关默认值");
            Config fresh = new Config();
            Check(fresh.EscapeDisables, "默认 ESC 可关闭模式");
            Check(fresh.MiddleDoubleClickToggles, "默认双击滚轮键可切换");
            Check(fresh.ShowIndicator, "默认显示角落指示灯");
            Check(fresh.Scope == "global", "默认全局生效");

            return Finish();
        }

        private static int Finish()
        {
            lines.Add("");
            lines.Add("结果：" + passed + " 通过 / " + failed + " 失败");

            string report = string.Join(Environment.NewLine, lines);
            try { File.WriteAllText(ReportPath, report, new UTF8Encoding(false)); } catch { }
            Program.WriteConsole(report);
            Program.WriteConsole("报告文件：" + ReportPath);
            return failed == 0 ? 0 : 1;
        }

        private static bool MatchAny(List<AppRule> rules, string processName)
        {
            foreach (AppRule r in rules) if (r.Matches(processName)) return true;
            return false;
        }
    }
}
