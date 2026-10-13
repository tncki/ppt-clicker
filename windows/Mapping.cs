using System;
using System.Collections.Generic;
using System.Globalization;

namespace PPTClicker
{
    /// <summary>一个鼠标事件可以映射成的动作。</summary>
    public enum ClickerAction
    {
        Next, Prev, PageDown, PageUp, Space, Escape, Black, White, None, Pass
    }

    public enum MouseKind
    {
        LeftClick, RightClick, MiddleClick, BackButton, ForwardButton,
        ScrollUp, ScrollDown, ScrollLeft, ScrollRight
    }

    /// <summary>滚轮方向语义：跟随系统设置还是手动指定。</summary>
    public enum ScrollDirectionSetting { Auto, Normal, Inverted }

    public static class Mapping
    {
        public static ClickerAction ParseAction(string value, ClickerAction fallback)
        {
            if (string.IsNullOrWhiteSpace(value)) return fallback;
            switch (value.Trim().ToLowerInvariant())
            {
                case "next": return ClickerAction.Next;
                case "prev": return ClickerAction.Prev;
                case "pagedown": return ClickerAction.PageDown;
                case "pageup": return ClickerAction.PageUp;
                case "space": return ClickerAction.Space;
                case "escape": return ClickerAction.Escape;
                case "black": return ClickerAction.Black;
                case "white": return ClickerAction.White;
                case "none": return ClickerAction.None;
                case "pass": return ClickerAction.Pass;
                default: return fallback;
            }
        }

        public static ScrollDirectionSetting ParseScrollDirection(string value, ScrollDirectionSetting fallback)
        {
            if (string.IsNullOrWhiteSpace(value)) return fallback;
            switch (value.Trim().ToLowerInvariant())
            {
                case "auto": return ScrollDirectionSetting.Auto;
                case "normal": return ScrollDirectionSetting.Normal;
                case "inverted": return ScrollDirectionSetting.Inverted;
                default: return fallback;
            }
        }

        /// <summary>true = 吞掉原始鼠标事件。</summary>
        public static bool Swallows(ClickerAction action) { return action != ClickerAction.Pass; }

        /// <summary>动作对应的虚拟键（无则为 null）。</summary>
        public static byte? VirtualKey(ClickerAction action)
        {
            switch (action)
            {
                case ClickerAction.Next: return Native.VK_RIGHT;
                case ClickerAction.Prev: return Native.VK_LEFT;
                case ClickerAction.PageDown: return Native.VK_NEXT;
                case ClickerAction.PageUp: return Native.VK_PRIOR;
                case ClickerAction.Space: return Native.VK_SPACE;
                case ClickerAction.Escape: return Native.VK_ESCAPE;
                case ClickerAction.Black: return Native.VK_B;
                case ClickerAction.White: return Native.VK_W;
                default: return null;
            }
        }

        /// <summary>
        /// Windows 上普通鼠标滚轮是"传统"方向：远离自己（向前滚）delta &gt; 0。
        /// 所以物理"向下滚"（朝自己）对应 delta &lt; 0，即 downIsPositive = false。
        /// 触控板/驱动若开了反向滚动，可用配置里的 scrollDirection 手动指定。
        /// </summary>
        public static bool PhysicalDownIsPositive(ScrollDirectionSetting setting)
        {
            switch (setting)
            {
                case ScrollDirectionSetting.Auto: return false;
                case ScrollDirectionSetting.Normal: return false;
                case ScrollDirectionSetting.Inverted: return true;
                default: return false;
            }
        }

        public static MouseKind? ScrollKind(double axis1, double axis2, bool downIsPositive)
        {
            if (Math.Abs(axis1) >= Math.Abs(axis2) && axis1 != 0)
            {
                bool isDown = downIsPositive ? (axis1 > 0) : (axis1 < 0);
                return isDown ? MouseKind.ScrollDown : MouseKind.ScrollUp;
            }
            if (axis2 != 0)
            {
                bool isRight = downIsPositive ? (axis2 > 0) : (axis2 < 0);
                return isRight ? MouseKind.ScrollRight : MouseKind.ScrollLeft;
            }
            return null;
        }

        public static string Describe(MouseKind kind)
        {
            switch (kind)
            {
                case MouseKind.LeftClick: return "左键";
                case MouseKind.RightClick: return "右键";
                case MouseKind.MiddleClick: return "中键";
                case MouseKind.BackButton: return "侧键后退";
                case MouseKind.ForwardButton: return "侧键前进";
                case MouseKind.ScrollUp: return "滚轮上";
                case MouseKind.ScrollDown: return "滚轮下";
                case MouseKind.ScrollLeft: return "滚轮左";
                case MouseKind.ScrollRight: return "滚轮右";
                default: return kind.ToString();
            }
        }
    }

    public class Bindings
    {
        public ClickerAction LeftClick = ClickerAction.Next;
        public ClickerAction RightClick = ClickerAction.Prev;
        public ClickerAction MiddleClick = ClickerAction.Pass;
        public ClickerAction BackButton = ClickerAction.Pass;
        public ClickerAction ForwardButton = ClickerAction.Pass;
        public ClickerAction ScrollUp = ClickerAction.Prev;
        public ClickerAction ScrollDown = ClickerAction.Next;
        public ClickerAction ScrollLeft = ClickerAction.Pass;
        public ClickerAction ScrollRight = ClickerAction.Pass;

        public ClickerAction ActionFor(MouseKind kind)
        {
            switch (kind)
            {
                case MouseKind.LeftClick: return LeftClick;
                case MouseKind.RightClick: return RightClick;
                case MouseKind.MiddleClick: return MiddleClick;
                case MouseKind.BackButton: return BackButton;
                case MouseKind.ForwardButton: return ForwardButton;
                case MouseKind.ScrollUp: return ScrollUp;
                case MouseKind.ScrollDown: return ScrollDown;
                case MouseKind.ScrollLeft: return ScrollLeft;
                case MouseKind.ScrollRight: return ScrollRight;
                default: return ClickerAction.Pass;
            }
        }
    }

    /// <summary>滚轮/按键连发节流。</summary>
    public class Throttle
    {
        private double last = double.NegativeInfinity;

        public bool Allow(double now, double interval)
        {
            if (now - last < interval) return false;
            last = now;
            return true;
        }

        public void Reset() { last = double.NegativeInfinity; }
    }

    /// <summary>双击检测（双击滚轮键切换模式），带冷却避免连按反复触发。</summary>
    public class DoubleClickDetector
    {
        private double? lastAt;
        private double lastTriggerAt = double.NegativeInfinity;

        public bool Register(double now, double interval)
        {
            if (now - lastTriggerAt < interval)
            {
                lastAt = null;
                return false;
            }
            if (lastAt.HasValue && now - lastAt.Value <= interval)
            {
                lastAt = null;
                lastTriggerAt = now;
                return true;
            }
            lastAt = now;
            return false;
        }

        public void Reset()
        {
            lastAt = null;
            lastTriggerAt = double.NegativeInfinity;
        }
    }

    public class Hotkey
    {
        public string Key = "p";
        public List<string> Modifiers = new List<string> { "control", "alt", "shift" };

        public byte VirtualKey()
        {
            byte vk;
            if (KeyNames.TryGet(Key, out vk)) return vk;
            return Native.VK_P;
        }

        public uint NativeModifiers()
        {
            uint mods = 0;
            foreach (string raw in Modifiers)
            {
                switch ((raw ?? "").Trim().ToLowerInvariant())
                {
                    case "control":
                    case "ctrl": mods |= Native.MOD_CONTROL; break;
                    case "option":
                    case "alt": mods |= Native.MOD_ALT; break;
                    case "shift": mods |= Native.MOD_SHIFT; break;
                    case "command":
                    case "cmd":
                    case "win": mods |= Native.MOD_WIN; break;
                    default: break;
                }
            }
            return mods | Native.MOD_NOREPEAT;
        }

        public string Display()
        {
            string s = "";
            foreach (string raw in Modifiers)
            {
                switch ((raw ?? "").Trim().ToLowerInvariant())
                {
                    case "control":
                    case "ctrl": s += "Ctrl+"; break;
                    case "option":
                    case "alt": s += "Alt+"; break;
                    case "shift": s += "Shift+"; break;
                    case "command":
                    case "cmd":
                    case "win": s += "Win+"; break;
                    default: break;
                }
            }
            return s + Key.ToUpperInvariant();
        }
    }

    public static class KeyNames
    {
        private static readonly Dictionary<string, byte> Map = Build();

        private static Dictionary<string, byte> Build()
        {
            var m = new Dictionary<string, byte>(StringComparer.OrdinalIgnoreCase);
            string letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
            for (int i = 0; i < letters.Length; i++) m[letters[i].ToString()] = (byte)(0x41 + i);
            for (int i = 0; i <= 9; i++) m[i.ToString()] = (byte)(0x30 + i);
            for (int i = 1; i <= 24; i++) m["f" + i.ToString(CultureInfo.InvariantCulture)] = (byte)(0x70 + i - 1);
            m["space"] = 0x20;
            m["escape"] = 0x1B;
            m["esc"] = 0x1B;
            m["enter"] = 0x0D;
            m["return"] = 0x0D;
            m["tab"] = 0x09;
            m["left"] = 0x25;
            m["up"] = 0x26;
            m["right"] = 0x27;
            m["down"] = 0x28;
            m["pageup"] = 0x21;
            m["pagedown"] = 0x22;
            m["home"] = 0x24;
            m["end"] = 0x23;
            m["insert"] = 0x2D;
            m["delete"] = 0x2E;
            return m;
        }

        public static bool TryGet(string name, out byte vk)
        {
            vk = 0;
            if (string.IsNullOrWhiteSpace(name)) return false;
            return Map.TryGetValue(name.Trim(), out vk);
        }
    }
}
