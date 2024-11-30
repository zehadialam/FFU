Add-Type @"
    using System;
    using System.Text;
    using System.Runtime.InteropServices;
    public class User32 {
        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
        
        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
        
        [DllImport("user32.dll", SetLastError = true)]
        public static extern int GetWindowTextLength(IntPtr hWnd);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        public static bool EnumTheWindows(IntPtr hWnd, IntPtr lParam) {
            int length = GetWindowTextLength(hWnd);
            if (length > 0 && IsWindowVisible(hWnd)) {
                StringBuilder builder = new StringBuilder(length + 1);
                GetWindowText(hWnd, builder, builder.Capacity);
                Console.WriteLine(builder.ToString());
            }
            return true;
        }
    }
"@

# Delegate the call to EnumWindows to enumerate all open windows
$EnumFunc = [User32+EnumWindowsProc]{
    param ($hWnd, $lParam)
    [User32]::EnumTheWindows($hWnd, $lParam)
}

[User32]::EnumWindows($EnumFunc, [IntPtr]::Zero)
