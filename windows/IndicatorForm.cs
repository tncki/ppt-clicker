using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace PPTClicker
{
    /// <summary>
    /// 屏幕角落的状态指示灯：一颗小圆点，常驻最上层。
    /// 绿色 = 已开启，灰色 = 已关闭，橙色 = 事件钩子没装上。
    /// 左键点击 = 开关，右键 = 菜单，按住拖动 = 换位置。
    /// </summary>
    public sealed class IndicatorForm : Form
    {
        private const int WS_EX_TOOLWINDOW = 0x00000080;

        public bool IsOn;
        public bool Warning;

        public event Action Clicked;
        public event Action RightClicked;
        public event Action<Point> Moved;

        private bool dragging;
        private Point dragStartScreen;
        private Point startLocation;

        public IndicatorForm()
        {
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            TopMost = true;
            StartPosition = FormStartPosition.Manual;
            Size = new Size(18, 18);
            BackColor = Color.Fuchsia;
            TransparencyKey = Color.Fuchsia;
            DoubleBuffered = true;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true);
            Text = "PPT Clicker";
        }

        /// <summary>显示时不抢焦点。</summary>
        protected override bool ShowWithoutActivation { get { return true; } }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= WS_EX_TOOLWINDOW;   // 不出现在 Alt-Tab 里
                return cp;
            }
        }

        public void SetState(bool on, bool warning)
        {
            IsOn = on;
            Warning = warning;
            Invalidate();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.Clear(TransparencyKey);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;

            Rectangle rect = new Rectangle(4, 4, Width - 9, Height - 9);
            if (Warning)
            {
                using (SolidBrush b = new SolidBrush(Color.FromArgb(255, 149, 0))) e.Graphics.FillEllipse(b, rect);
            }
            else if (IsOn)
            {
                Rectangle glow = new Rectangle(2, 2, Width - 5, Height - 5);
                using (Pen p = new Pen(Color.FromArgb(90, 52, 199, 89), 2f)) e.Graphics.DrawEllipse(p, glow);
                using (SolidBrush b = new SolidBrush(Color.FromArgb(52, 199, 89))) e.Graphics.FillEllipse(b, rect);
            }
            else
            {
                using (SolidBrush b = new SolidBrush(Color.FromArgb(60, 120, 128, 140))) e.Graphics.FillEllipse(b, rect);
                using (Pen p = new Pen(Color.FromArgb(150, 120, 128, 140), 1.4f)) e.Graphics.DrawEllipse(p, rect);
            }
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left)
            {
                dragging = false;
                dragStartScreen = Cursor.Position;
                startLocation = Location;
            }
            else if (e.Button == MouseButtons.Right)
            {
                Action handler = RightClicked;
                if (handler != null) handler();
            }
            base.OnMouseDown(e);
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left)
            {
                Point now = Cursor.Position;
                int dx = now.X - dragStartScreen.X;
                int dy = now.Y - dragStartScreen.Y;
                if (Math.Abs(dx) + Math.Abs(dy) > 2) dragging = true;
                Location = new Point(startLocation.X + dx, startLocation.Y + dy);
            }
            base.OnMouseMove(e);
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left)
            {
                if (dragging)
                {
                    Action<Point> handler = Moved;
                    if (handler != null) handler(Location);
                }
                else
                {
                    Action handler = Clicked;
                    if (handler != null) handler();
                }
                dragging = false;
            }
            base.OnMouseUp(e);
        }
    }
}
