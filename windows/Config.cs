using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.Json;

namespace PPTClicker
{
    public class AppRule
    {
        public string Exe = "";
        public string Name = "";

        public bool Matches(string processName)
        {
            if (string.IsNullOrEmpty(Exe) || string.IsNullOrEmpty(processName)) return false;
            return string.Equals(Exe, processName, StringComparison.OrdinalIgnoreCase);
        }
    }

    public class Config
    {
        public Bindings Bindings = new Bindings();
        public ScrollDirectionSetting ScrollDirection = ScrollDirectionSetting.Auto;
        public bool EscapeDisables = true;
        public bool MiddleDoubleClickToggles = true;
        public bool ShowIndicator = true;
        public Hotkey Hotkey = new Hotkey();
        public int ThrottleMs = 300;
        public string Scope = "global";
        public List<AppRule> Apps = DefaultApps();
        public bool StartEnabled = false;
        public bool DebugLog = true;
        public bool DebugEvents = false;
        public string LogPath = DefaultLogPath();

        public double ThrottleInterval { get { return ThrottleMs / 1000.0; } }

        public static string DataDirectory()
        {
            string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            return Path.Combine(appData, "PPTClicker");
        }

        public static string DefaultLogPath()
        {
            string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            return Path.Combine(local, "PPTClicker", "pptclicker.log");
        }

        public static string ConfigPath()
        {
            return Path.Combine(DataDirectory(), "config.json");
        }

        public static string StatePath()
        {
            return Path.Combine(DataDirectory(), "state.json");
        }

        /// <summary>展开 %LOCALAPPDATA% 之类的环境变量。</summary>
        public static string Expand(string path)
        {
            if (string.IsNullOrEmpty(path)) return path;
            return Environment.ExpandEnvironmentVariables(path);
        }

        public static List<AppRule> DefaultApps()
        {
            var list = new List<AppRule>();
            list.Add(new AppRule { Exe = "POWERPNT.EXE", Name = "Microsoft PowerPoint" });
            list.Add(new AppRule { Exe = "wpp.exe", Name = "WPS 演示" });
            list.Add(new AppRule { Exe = "soffice.exe", Name = "LibreOffice Impress" });
            list.Add(new AppRule { Exe = "wps.exe", Name = "WPS Office" });
            return list;
        }

        public static Config Load()
        {
            string path = ConfigPath();
            if (!File.Exists(path))
            {
                try
                {
                    Directory.CreateDirectory(DataDirectory());
                    File.WriteAllText(path, DefaultJson, new UTF8Encoding(false));
                }
                catch { }
                return Parse(DefaultJson);
            }
            try
            {
                return Parse(File.ReadAllText(path));
            }
            catch (Exception ex)
            {
                Log.Write("配置文件读取失败，使用内置默认值：" + ex.Message);
                return Parse(DefaultJson);
            }
        }

        public static bool Save(Config config)
        {
            try
            {
                Directory.CreateDirectory(DataDirectory());
                File.WriteAllText(ConfigPath(), config.ToJson(), new UTF8Encoding(false));
                return true;
            }
            catch { return false; }
        }

        public string ToJson()
        {
            var sb = new StringBuilder();
            sb.Append("{\n");
            sb.Append("  \"scrollDirection\": \"").Append(ScrollDirection.ToString().ToLowerInvariant()).Append("\",\n");
            sb.Append("  \"escapeDisables\": ").Append(EscapeDisables ? "true" : "false").Append(",\n");
            sb.Append("  \"middleDoubleClickToggles\": ").Append(MiddleDoubleClickToggles ? "true" : "false").Append(",\n");
            sb.Append("  \"showIndicator\": ").Append(ShowIndicator ? "true" : "false").Append(",\n");
            sb.Append("  \"throttleMs\": ").Append(ThrottleMs).Append(",\n");
            sb.Append("  \"scope\": \"").Append(Scope).Append("\",\n");
            sb.Append("  \"startEnabled\": ").Append(StartEnabled ? "true" : "false").Append(",\n");
            sb.Append("  \"debugLog\": ").Append(DebugLog ? "true" : "false").Append(",\n");
            sb.Append("  \"debugEvents\": ").Append(DebugEvents ? "true" : "false").Append(",\n");
            sb.Append("  \"logPath\": \"").Append(JsonEscape(LogPath)).Append("\",\n");
            sb.Append("  \"bindings\": {\n");
            sb.Append("    \"leftClick\": \"").Append(Bindings.LeftClick.ToString().ToLowerInvariant()).Append("\",\n");
            sb.Append("    \"rightClick\": \"").Append(Bindings.RightClick.ToString().ToLowerInvariant()).Append("\",\n");
            sb.Append("    \"middleClick\": \"").Append(Bindings.MiddleClick.ToString().ToLowerInvariant()).Append("\",\n");
            sb.Append("    \"backButton\": \"").Append(Bindings.BackButton.ToString().ToLowerInvariant()).Append("\",\n");
            sb.Append("    \"forwardButton\": \"").Append(Bindings.ForwardButton.ToString().ToLowerInvariant()).Append("\",\n");
            sb.Append("    \"scrollUp\": \"").Append(Bindings.ScrollUp.ToString().ToLowerInvariant()).Append("\",\n");
            sb.Append("    \"scrollDown\": \"").Append(Bindings.ScrollDown.ToString().ToLowerInvariant()).Append("\",\n");
            sb.Append("    \"scrollLeft\": \"").Append(Bindings.ScrollLeft.ToString().ToLowerInvariant()).Append("\",\n");
            sb.Append("    \"scrollRight\": \"").Append(Bindings.ScrollRight.ToString().ToLowerInvariant()).Append("\"\n");
            sb.Append("  },\n");
            sb.Append("  \"hotkey\": { \"key\": \"").Append(JsonEscape(Hotkey.Key)).Append("\", \"modifiers\": [");
            for (int i = 0; i < Hotkey.Modifiers.Count; i++)
            {
                if (i > 0) sb.Append(", ");
                sb.Append("\"").Append(JsonEscape(Hotkey.Modifiers[i])).Append("\"");
            }
            sb.Append("] },\n");
            sb.Append("  \"apps\": [\n");
            for (int i = 0; i < Apps.Count; i++)
            {
                sb.Append("    { \"exe\": \"").Append(JsonEscape(Apps[i].Exe)).Append("\", \"name\": \"")
                  .Append(JsonEscape(Apps[i].Name)).Append("\" }");
                sb.Append(i < Apps.Count - 1 ? ",\n" : "\n");
            }
            sb.Append("  ]\n");
            sb.Append("}\n");
            return sb.ToString();
        }

        private static string JsonEscape(string s)
        {
            if (s == null) return "";
            return s.Replace("\\", "\\\\").Replace("\"", "\\\"");
        }

        public static Config Parse(string json)
        {
            var cfg = new Config();
            cfg.Apps = new List<AppRule>();
            JsonDocument doc;
            try { doc = JsonDocument.Parse(json); }
            catch { return cfg; }

            using (doc)
            {
                JsonElement root = doc.RootElement;
                if (root.ValueKind != JsonValueKind.Object) return cfg;

                string sd = GetString(root, "scrollDirection");
                if (sd != null) cfg.ScrollDirection = Mapping.ParseScrollDirection(sd, cfg.ScrollDirection);
                bool? b;
                b = GetBool(root, "escapeDisables"); if (b.HasValue) cfg.EscapeDisables = b.Value;
                b = GetBool(root, "middleDoubleClickToggles"); if (b.HasValue) cfg.MiddleDoubleClickToggles = b.Value;
                b = GetBool(root, "showIndicator"); if (b.HasValue) cfg.ShowIndicator = b.Value;
                b = GetBool(root, "startEnabled"); if (b.HasValue) cfg.StartEnabled = b.Value;
                b = GetBool(root, "debugLog"); if (b.HasValue) cfg.DebugLog = b.Value;
                b = GetBool(root, "debugEvents"); if (b.HasValue) cfg.DebugEvents = b.Value;
                int? t = GetInt(root, "throttleMs"); if (t.HasValue && t.Value >= 0) cfg.ThrottleMs = t.Value;
                string sp = GetString(root, "scope");
                if (sp == "global" || sp == "apps") cfg.Scope = sp;
                string lp = GetString(root, "logPath");
                if (!string.IsNullOrEmpty(lp)) cfg.LogPath = lp;

                JsonElement el;
                if (root.TryGetProperty("bindings", out el) && el.ValueKind == JsonValueKind.Object)
                {
                    var d = new Bindings();
                    cfg.Bindings.LeftClick = ReadAction(el, "leftClick", d.LeftClick);
                    cfg.Bindings.RightClick = ReadAction(el, "rightClick", d.RightClick);
                    cfg.Bindings.MiddleClick = ReadAction(el, "middleClick", d.MiddleClick);
                    cfg.Bindings.BackButton = ReadAction(el, "backButton", d.BackButton);
                    cfg.Bindings.ForwardButton = ReadAction(el, "forwardButton", d.ForwardButton);
                    cfg.Bindings.ScrollUp = ReadAction(el, "scrollUp", d.ScrollUp);
                    cfg.Bindings.ScrollDown = ReadAction(el, "scrollDown", d.ScrollDown);
                    cfg.Bindings.ScrollLeft = ReadAction(el, "scrollLeft", d.ScrollLeft);
                    cfg.Bindings.ScrollRight = ReadAction(el, "scrollRight", d.ScrollRight);
                }

                if (root.TryGetProperty("hotkey", out el) && el.ValueKind == JsonValueKind.Object)
                {
                    string key = GetString(el, "key");
                    byte probe;
                    if (!string.IsNullOrEmpty(key) && KeyNames.TryGet(key, out probe)) cfg.Hotkey.Key = key;
                    JsonElement mods;
                    if (el.TryGetProperty("modifiers", out mods) && mods.ValueKind == JsonValueKind.Array)
                    {
                        var list = new List<string>();
                        foreach (JsonElement item in mods.EnumerateArray())
                        {
                            if (item.ValueKind == JsonValueKind.String) list.Add(item.GetString());
                        }
                        cfg.Hotkey.Modifiers = list;
                    }
                    // 安全兜底：至少要有一个修饰键，否则会退化成全局吞掉某个普通按键
                    if (cfg.Hotkey.NativeModifiers() == Native.MOD_NOREPEAT)
                        cfg.Hotkey.Modifiers = new List<string> { "control", "alt", "shift" };
                }

                if (root.TryGetProperty("apps", out el) && el.ValueKind == JsonValueKind.Array)
                {
                    foreach (JsonElement item in el.EnumerateArray())
                    {
                        if (item.ValueKind != JsonValueKind.Object) continue;
                        string exe = GetString(item, "exe");
                        if (string.IsNullOrEmpty(exe)) exe = GetString(item, "bundleID");
                        if (string.IsNullOrEmpty(exe)) continue;
                        var rule = new AppRule { Exe = exe, Name = GetString(item, "name") ?? exe };
                        cfg.Apps.Add(rule);
                    }
                }
            }
            return cfg;
        }

        private static ClickerAction ReadAction(JsonElement obj, string name, ClickerAction fallback)
        {
            string raw = GetString(obj, name);
            return Mapping.ParseAction(raw, fallback);
        }

        public static string GetString(JsonElement obj, string name)
        {
            JsonElement v;
            if (obj.ValueKind == JsonValueKind.Object && obj.TryGetProperty(name, out v) && v.ValueKind == JsonValueKind.String)
                return v.GetString();
            return null;
        }

        public static bool? GetBool(JsonElement obj, string name)
        {
            JsonElement v;
            if (obj.ValueKind == JsonValueKind.Object && obj.TryGetProperty(name, out v))
            {
                if (v.ValueKind == JsonValueKind.True) return true;
                if (v.ValueKind == JsonValueKind.False) return false;
            }
            return null;
        }

        public static int? GetInt(JsonElement obj, string name)
        {
            JsonElement v;
            if (obj.ValueKind == JsonValueKind.Object && obj.TryGetProperty(name, out v) && v.ValueKind == JsonValueKind.Number)
            {
                int i;
                if (v.TryGetInt32(out i)) return i;
            }
            return null;
        }

        public const string DefaultJson = @"{
  ""_说明"": ""PPT Clicker（Windows）配置。改完在托盘菜单里点『重新载入配置』。环境变量可用 %LOCALAPPDATA% 这种写法。"",
  ""_动作可选值"": {
    ""next"": ""下一页（发送 →）"",
    ""prev"": ""上一页（发送 ←）"",
    ""pageDown"": ""Page Down"",
    ""pageUp"": ""Page Up"",
    ""space"": ""空格"",
    ""escape"": ""Esc"",
    ""black"": ""黑屏（b）"",
    ""white"": ""白屏（w）"",
    ""none"": ""拦截但什么都不做"",
    ""pass"": ""不拦截，保持系统原样""
  },
  ""_生效时机"": ""开关由快捷键/双击滚轮键/ESC 手动控制；scope=global 表示开启后所有程序都生效，scope=apps 表示仅当前前台程序的 exe 在 apps 列表里时生效。"",
  ""_滚轮方向"": ""auto = 按 Windows 常规滚轮方向判定（向下滚 → 下一页）。若你的触控板/驱动开了反向滚动，改成 inverted。"",
  ""scrollDirection"": ""auto"",
  ""_关闭方式"": ""开启用快捷键；关闭可用 快捷键再按一次 / ESC / 双击滚轮键（中键）。ESC 只旁听不拦截，PowerPoint 自己的『按 ESC 结束放映』照样有效。"",
  ""escapeDisables"": true,
  ""middleDoubleClickToggles"": true,
  ""_指示灯"": ""屏幕角落的小圆点：绿色=已开启，灰色=已关闭。左键点一下=开关，右键=菜单，拖动=换位置。"",
  ""showIndicator"": true,
  ""bindings"": {
    ""leftClick"": ""next"",
    ""rightClick"": ""prev"",
    ""middleClick"": ""pass"",
    ""backButton"": ""pass"",
    ""forwardButton"": ""pass"",
    ""scrollUp"": ""prev"",
    ""scrollDown"": ""next"",
    ""scrollLeft"": ""pass"",
    ""scrollRight"": ""pass""
  },
  ""hotkey"": { ""key"": ""p"", ""modifiers"": [""control"", ""alt"", ""shift""] },
  ""throttleMs"": 300,
  ""scope"": ""global"",
  ""startEnabled"": false,
  ""debugLog"": true,
  ""debugEvents"": false,
  ""logPath"": ""%LOCALAPPDATA%\\PPTClicker\\pptclicker.log"",
  ""apps"": [
    { ""exe"": ""POWERPNT.EXE"", ""name"": ""Microsoft PowerPoint"" },
    { ""exe"": ""wpp.exe"", ""name"": ""WPS 演示"" },
    { ""exe"": ""soffice.exe"", ""name"": ""LibreOffice Impress"" }
  ]
}
";
    }

    /// <summary>指示灯的持久化状态（位置等）。</summary>
    public class UiState
    {
        public int IndicatorX = -1;
        public int IndicatorY = -1;

        public static UiState Load()
        {
            try
            {
                string path = Config.StatePath();
                if (!File.Exists(path)) return new UiState();
                string json = File.ReadAllText(path);
                UiState state = new UiState();
                using (JsonDocument doc = JsonDocument.Parse(json))
                {
                    JsonElement root = doc.RootElement;
                    int? x = Config.GetInt(root, "indicatorX");
                    int? y = Config.GetInt(root, "indicatorY");
                    if (x.HasValue) state.IndicatorX = x.Value;
                    if (y.HasValue) state.IndicatorY = y.Value;
                }
                return state;
            }
            catch { return new UiState(); }
        }

        public void Save()
        {
            try
            {
                Directory.CreateDirectory(Config.DataDirectory());
                File.WriteAllText(Config.StatePath(),
                    "{\n  \"indicatorX\": " + IndicatorX + ",\n  \"indicatorY\": " + IndicatorY + "\n}\n",
                    new UTF8Encoding(false));
            }
            catch { }
        }
    }
}
