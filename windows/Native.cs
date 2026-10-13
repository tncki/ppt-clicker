using System;
using System.Runtime.InteropServices;

namespace PPTClicker
{
    /// <summary>Win32 常量、结构体与 P/Invoke 声明。</summary>
    public static class Native
    {
        // 键盘虚拟键
        public const byte VK_ESCAPE = 0x1B;
        public const byte VK_SPACE = 0x20;
        public const byte VK_PRIOR = 0x21;
        public const byte VK_NEXT = 0x22;
        public const byte VK_LEFT = 0x25;
        public const byte VK_RIGHT = 0x27;
        public const byte VK_B = 0x42;
        public const byte VK_W = 0x57;
        public const byte VK_P = 0x50;

        // 全局快捷键修饰键
        public const uint MOD_ALT = 0x0001;
        public const uint MOD_CONTROL = 0x0002;
        public const uint MOD_SHIFT = 0x0004;
        public const uint MOD_WIN = 0x0008;
        public const uint MOD_NOREPEAT = 0x4000;

        // 窗口消息
        public const int WM_HOTKEY = 0x0312;
        public const int WM_LBUTTONDOWN = 0x0201;
        public const int WM_LBUTTONUP = 0x0202;
        public const int WM_RBUTTONDOWN = 0x0204;
        public const int WM_RBUTTONUP = 0x0205;
        public const int WM_MBUTTONDOWN = 0x0207;
        public const int WM_MBUTTONUP = 0x0208;
        public const int WM_MOUSEWHEEL = 0x020A;
        public const int WM_XBUTTONDOWN = 0x020B;
        public const int WM_XBUTTONUP = 0x020C;
        public const int WM_MOUSEHWHEEL = 0x020E;

        public const int WH_MOUSE_LL = 14;
        public const int WH_KEYBOARD_LL = 13;

        // SendInput
        public const uint INPUT_MOUSE = 0;
        public const uint INPUT_KEYBOARD = 1;
        public const uint KEYEVENTF_KEYUP = 0x0002;
        public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
        public const uint MOUSEEVENTF_LEFTUP = 0x0004;

        /// <summary>自己合成的事件带的标记，避免被自己的钩子再次处理。</summary>
        public static readonly UIntPtr MagicExtraInfo = new UIntPtr(0x50505443); // "PPTC"

        [StructLayout(LayoutKind.Sequential)]
        public struct POINT { public int X; public int Y; }

        [StructLayout(LayoutKind.Sequential)]
        public struct MSLLHOOKSTRUCT
        {
            public POINT pt;
            public uint mouseData;
            public uint flags;
            public uint time;
            public UIntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct KBDLLHOOKSTRUCT
        {
            public uint vkCode;
            public uint scanCode;
            public uint flags;
            public uint time;
            public UIntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct MOUSEINPUT
        {
            public int dx;
            public int dy;
            public uint mouseData;
            public uint dwFlags;
            public uint time;
            public UIntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct KEYBDINPUT
        {
            public ushort wVk;
            public ushort wScan;
            public uint dwFlags;
            public uint time;
            public UIntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct HARDWAREINPUT
        {
            public uint uMsg;
            public ushort wParamL;
            public ushort wParamH;
        }

        [StructLayout(LayoutKind.Explicit)]
        public struct InputUnion
        {
            [FieldOffset(0)] public MOUSEINPUT mi;
            [FieldOffset(0)] public KEYBDINPUT ki;
            [FieldOffset(0)] public HARDWAREINPUT hi;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct INPUT
        {
            public uint type;
            public InputUnion U;
        }

        public delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr SetWindowsHookEx(int idHook, HookProc lpfn, IntPtr hMod, uint dwThreadId);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll")]
        public static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll")]
        public static extern IntPtr GetModuleHandle(string lpModuleName);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool AttachConsole(int dwProcessId);

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool AllocConsole();

        public const int ATTACH_PARENT_PROCESS = -1;

        public static double Now()
        {
            return (double)Environment.TickCount64 / 1000.0;
        }

        /// <summary>发送一次按键（按下 + 抬起）。</summary>
        public static void SendKey(byte vk)
        {
            INPUT[] inputs = new INPUT[2];
            inputs[0].type = INPUT_KEYBOARD;
            inputs[0].U.ki.wVk = vk;
            inputs[0].U.ki.wScan = 0;
            inputs[0].U.ki.dwFlags = 0;
            inputs[0].U.ki.time = 0;
            inputs[0].U.ki.dwExtraInfo = MagicExtraInfo;

            inputs[1].type = INPUT_KEYBOARD;
            inputs[1].U.ki.wVk = vk;
            inputs[1].U.ki.wScan = 0;
            inputs[1].U.ki.dwFlags = KEYEVENTF_KEYUP;
            inputs[1].U.ki.time = 0;
            inputs[1].U.ki.dwExtraInfo = MagicExtraInfo;

            SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
        }

        /// <summary>合成一次左键点击（供自检使用）。</summary>
        public static void SendLeftClick(bool markAsOurs)
        {
            INPUT[] inputs = new INPUT[2];
            inputs[0].type = INPUT_MOUSE;
            inputs[0].U.mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
            inputs[0].U.mi.dwExtraInfo = markAsOurs ? MagicExtraInfo : UIntPtr.Zero;

            inputs[1].type = INPUT_MOUSE;
            inputs[1].U.mi.dwFlags = MOUSEEVENTF_LEFTUP;
            inputs[1].U.mi.dwExtraInfo = markAsOurs ? MagicExtraInfo : UIntPtr.Zero;

            SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
        }
    }
}
