import Foundation

/// 极简双语支持：系统语言是中文就显示中文，否则显示英文。
/// 用中文原文当作 key，缺英文翻译时自动回退到中文，不会出现空白。
enum L {

    static let isChinese: Bool = {
        let first = Locale.preferredLanguages.first ?? "en"
        return first.hasPrefix("zh")
    }()

    static func s(_ zh: String) -> String {
        isChinese ? zh : (english[zh] ?? zh)
    }

    /// 带插值的句子：s("已拦截事件：\(n)") 这种先拼出中文，再查表
    private static let english: [String: String] = [
        // 菜单
        "翻页笔模式：已开启": "Clicker: ON",
        "翻页笔模式：已关闭": "Clicker: OFF",
        "切换翻页笔模式": "Toggle clicker mode",
        "关闭方式：再按一次快捷键 ・ ESC ・ 双击滚轮键": "To turn off: press the shortcut again / ESC / double-click the wheel",
        "关闭方式：再按一次快捷键 ・ ESC（已关） ・ 双击滚轮键": "To turn off: press the shortcut again / ESC (off) / double-click the wheel",
        "关闭方式：再按一次快捷键 ・ ESC ・ 双击滚轮键（已关）": "To turn off: press the shortcut again / ESC / double-click the wheel (off)",
        "关闭方式：再按一次快捷键 ・ ESC（已关） ・ 双击滚轮键（已关）": "To turn off: press the shortcut again / ESC (off) / double-click the wheel (off)",
        "仅在前台是演示软件时生效": "Only inside presentation apps",
        "显示屏幕角落的指示灯": "Show corner indicator dot",
        "重新载入配置": "Reload config",
        "打开配置文件…": "Open config file…",
        "打开日志…": "Open log…",
        "记录原始事件到日志（诊断用）": "Log raw events (diagnostics)",
        "把状态栏诊断写进日志": "Write diagnostics to log",
        "开机自动启动": "Launch at login",
        "退出": "Quit",
        "当前映射：": "Current mapping: ",
        "，滚轮下→": ", wheel down → ",
        "，右键→": ", right click → ",
        "，滚轮上→": ", wheel up → ",
        "下一页 →": "next →",
        "上一页 ←": "prev ←",
        "保持原样": "leave as is",
        "拦截但无动作": "swallow, no action",
        "事件监听：正常": "Event tap: active",
        "事件监听：未安装": "Event tap: not installed",
        "已注册": "registered",
        "未注册（改用事件监听兜底）": "not registered (fallback via event tap)",
        "辅助功能权限：已授权": "Accessibility: granted",
        "辅助功能权限：未授权 —— 点此去开启": "Accessibility: NOT granted — click to open settings",
        "输入监控权限：已授权": "Input Monitoring: granted",
        "输入监控权限：未授权 —— 点此去开启": "Input Monitoring: NOT granted — click to open settings",
        "已拦截事件：": "Events intercepted: ",
        "全局快捷键": "Global shortcut",
        // 指示灯提示
        "PPT 翻页笔：已开启": "PPT Clicker: ON",
        "PPT 翻页笔：已关闭": "PPT Clicker: OFF",
        "；但事件监听未生效，请授予『辅助功能』权限": "; event tap inactive — grant Accessibility permission",
        "（切换）": " (toggle)",
        // 首次启动引导
        "欢迎使用 PPT 翻页笔": "Welcome to PPT Clicker",
        "打开系统设置授权": "Open System Settings",
        "稍后": "Later",
    ]
}
