using System;
using System.Windows.Forms;

namespace PPTClicker
{
    /// <summary>极简双语：系统界面语言是中文就中文，否则英文。</summary>
    public static class L
    {
        public static readonly bool Chinese =
            System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "zh";

        public static string S(string zh, string en)
        {
            return Chinese ? zh : en;
        }
    }
}
