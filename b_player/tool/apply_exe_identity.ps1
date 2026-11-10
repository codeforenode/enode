# 把 runner DLL 里的版本资源和图标搬到 eNode.exe 上。
#
# 为什么需要：开了 CEF 沙箱后，进程主模块是厂商的 bootstrap.exe（被复制成 eNode.exe），
# 我们的 Flutter runner 变成 eNode.dll。而 path_provider / shared_preferences 都是从
# 「主模块的 VERSIONINFO」取 CompanyName\ProductName 当应用身份目录的，于是设置会写到
# %APPDATA%\CEF Bootstrap Application\ 下——老用户的曲库目录、音源、投放设置全部“消失”。
# exe 属性里显示的版本号也会变成 CEF 的 149.x。
# 把 DLL 里那份 VERSIONINFO（CompanyName=eNode、ProductName=eNode、FileVersion=pubspec 版本）
# 原样搬过去，两个问题一起解决，数据目录也回到 %APPDATA%\eNode\eNode。
#
# 图标同理：Runner.rc 的图标只嵌进了 eNode.dll，exe 还是 bootstrap 自带的 CEF 默认图标，
# 桌面快捷方式、资源管理器显示的都是它。这里把 DLL 的 GROUP_ICON + ICON 原样覆盖到 exe，
# 写回 exe 原有的资源组槽位（bootstrap 是 32512），避免资源里同时留下两组图标。
param(
    [Parameter(Mandatory = $true)][string]$Dll,
    [Parameter(Mandatory = $true)][string]$Exe)
$ErrorActionPreference = 'Stop'

# 在 MSBuild 里跑时，LIB 环境变量带着 ATLMFC 的 lib 路径；这台机器没装 ATL，那个目录不存在，
# Add-Type 会把它当成"警告即错误"直接失败。清掉它——我们不需要任何原生库搜索路径。
$env:LIB = ''
$env:LIBPATH = ''

Add-Type -ReferencedAssemblies System.Runtime.InteropServices -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class Win32Resource
{
    public const int LOAD_LIBRARY_AS_DATAFILE = 0x2;
    public static readonly IntPtr RT_VERSION = new IntPtr(16);
    public static readonly IntPtr RT_ICON = new IntPtr(3);
    public static readonly IntPtr RT_GROUP_ICON = new IntPtr(14);

    [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr LoadLibraryEx(string f, IntPtr h, int flags);
    [DllImport("kernel32", SetLastError = true)]
    public static extern bool FreeLibrary(IntPtr h);
    [DllImport("kernel32", SetLastError = true)]
    public static extern IntPtr FindResourceEx(IntPtr h, IntPtr type, IntPtr name, ushort lang);
    [DllImport("kernel32", SetLastError = true)]
    public static extern IntPtr LoadResource(IntPtr h, IntPtr res);
    [DllImport("kernel32")]
    public static extern IntPtr LockResource(IntPtr data);
    [DllImport("kernel32", SetLastError = true)]
    public static extern uint SizeofResource(IntPtr h, IntPtr res);
    [DllImport("kernel32", SetLastError = true)]
    public static extern bool EnumResourceNames(IntPtr h, IntPtr type, ENUM_NAME cb, IntPtr arg);
    [DllImport("kernel32", SetLastError = true)]
    public static extern bool EnumResourceLanguages(IntPtr h, IntPtr type, IntPtr name, ENUM_LANG cb, IntPtr arg);

    [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr BeginUpdateResource(string p, bool deleteExisting);
    [DllImport("kernel32", SetLastError = true)]
    public static extern bool UpdateResource(IntPtr h, IntPtr type, IntPtr name, ushort lang, byte[] data, int size);
    [DllImport("kernel32", SetLastError = true)]
    public static extern bool EndUpdateResource(IntPtr h, bool discard);

    [DllImport("kernel32", CharSet = CharSet.Unicode)]
    public static extern int GetLastError();

    public delegate bool ENUM_NAME(IntPtr h, IntPtr type, IntPtr name, IntPtr arg);
    public delegate bool ENUM_LANG(IntPtr h, IntPtr type, IntPtr name, ushort lang, IntPtr arg);

    // 回调必须在枚举期间活着，否则会被 GC 回收成野指针。
    static readonly ENUM_NAME nameCb = (h, t, n, a) => { Names.Add(n); return true; };
    static readonly ENUM_LANG langCb = (h, t, n, l, a) => { Langs.Add(l); return true; };
    static readonly List<IntPtr> Names = new List<IntPtr>();
    static readonly List<ushort> Langs = new List<ushort>();

    public static byte[] ReadVersion(string modulePath, out ushort language)
    {
        language = 0;
        IntPtr module = LoadLibraryEx(modulePath, IntPtr.Zero, LOAD_LIBRARY_AS_DATAFILE);
        if (module == IntPtr.Zero) throw new Exception("LoadLibraryEx 打不开 " + modulePath + " err=" + GetLastError());
        try
        {
            Names.Clear();
            if (!EnumResourceNames(module, RT_VERSION, nameCb, IntPtr.Zero) || Names.Count == 0)
                throw new Exception(modulePath + " 里没有 VERSIONINFO 资源");
            Langs.Clear();
            EnumResourceLanguages(module, RT_VERSION, Names[0], langCb, IntPtr.Zero);
            ushort[] candidates = Langs.Count > 0 ? Langs.ToArray() : new ushort[] { 0 };
            foreach (ushort lang in candidates)
            {
                IntPtr found = FindResourceEx(module, RT_VERSION, Names[0], lang);
                if (found == IntPtr.Zero) continue;
                IntPtr loaded = LoadResource(module, found);
                if (loaded == IntPtr.Zero) continue;
                uint size = SizeofResource(module, found);
                byte[] bytes = new byte[size];
                Marshal.Copy(LockResource(loaded), bytes, 0, (int)size);
                language = lang;
                return bytes;
            }
            throw new Exception(modulePath + " 里找不到可读的 VERSIONINFO");
        }
        finally { FreeLibrary(module); }
    }

    public static void WriteVersion(string exePath, IntPtr name, ushort lang, byte[] data)
    {
        IntPtr handle = BeginUpdateResource(exePath, false);
        if (handle == IntPtr.Zero) throw new Exception("BeginUpdateResource 失败 err=" + GetLastError());
        if (!UpdateResource(handle, RT_VERSION, name, lang, data, data.Length))
        {
            int err = GetLastError();
            EndUpdateResource(handle, true);
            throw new Exception("UpdateResource 失败 err=" + err);
        }
        if (!EndUpdateResource(handle, false))
            throw new Exception("EndUpdateResource 失败 err=" + GetLastError());
    }

    public static void VersionResource(string modulePath, out IntPtr name, out ushort lang)
    {
        name = new IntPtr(1);
        lang = 0;
        IntPtr module = LoadLibraryEx(modulePath, IntPtr.Zero, LOAD_LIBRARY_AS_DATAFILE);
        if (module == IntPtr.Zero) throw new Exception("LoadLibraryEx 打不开 " + modulePath + " err=" + GetLastError());
        try
        {
            Names.Clear();
            if (!EnumResourceNames(module, RT_VERSION, nameCb, IntPtr.Zero) || Names.Count == 0)
                throw new Exception(modulePath + " 里没有 VERSIONINFO 资源");
            name = Names[0];
            // 字符串型资源名的指针在 FreeLibrary 后就失效；VERSIONINFO 一律用序号名 1。
            if (name.ToInt64() > 0xFFFF) name = new IntPtr(1);
            Langs.Clear();
            EnumResourceLanguages(module, RT_VERSION, name, langCb, IntPtr.Zero);
            if (Langs.Count > 0) lang = Langs[0];
        }
        finally { FreeLibrary(module); }
    }

    static byte[] ReadResourceAt(IntPtr module, IntPtr type, IntPtr name, ushort lang)
    {
        IntPtr found = FindResourceEx(module, type, name, lang);
        if (found == IntPtr.Zero) return null;
        IntPtr loaded = LoadResource(module, found);
        if (loaded == IntPtr.Zero) return null;
        uint size = SizeofResource(module, found);
        byte[] bytes = new byte[size];
        Marshal.Copy(LockResource(loaded), bytes, 0, (int)size);
        return bytes;
    }

    // 图标和 VERSIONINFO 在 PE 里都用整数序号名；字符串名不处理。
    struct ResRef
    {
        public int Name;
        public ushort Lang;
    }

    static void AddRef(List<ResRef> list, int name, ushort lang)
    {
        foreach (ResRef r in list)
            if (r.Name == name && r.Lang == lang) return;
        ResRef added;
        added.Name = name;
        added.Lang = lang;
        list.Add(added);
    }

    static ResRef[] ListResources(IntPtr module, IntPtr type)
    {
        List<ResRef> result = new List<ResRef>();
        Names.Clear();
        if (!EnumResourceNames(module, type, nameCb, IntPtr.Zero)) return result.ToArray();
        IntPtr[] names = Names.ToArray();
        foreach (IntPtr name in names)
        {
            long id = name.ToInt64();
            if (id > 0xFFFF) continue;
            Langs.Clear();
            if (!EnumResourceLanguages(module, type, name, langCb, IntPtr.Zero) || Langs.Count == 0)
            {
                AddRef(result, (int)id, 0);
                continue;
            }
            foreach (ushort lang in Langs.ToArray()) AddRef(result, (int)id, lang);
        }
        return result.ToArray();
    }

    public static bool ReadIconGroup(string modulePath, out int name, out ushort lang, out byte[] data)
    {
        name = 0;
        lang = 0;
        data = null;
        IntPtr module = LoadLibraryEx(modulePath, IntPtr.Zero, LOAD_LIBRARY_AS_DATAFILE);
        if (module == IntPtr.Zero) return false;
        try
        {
            Names.Clear();
            if (!EnumResourceNames(module, RT_GROUP_ICON, nameCb, IntPtr.Zero) || Names.Count == 0) return false;
            IntPtr group = Names[0];
            long id = group.ToInt64();
            if (id > 0xFFFF) return false;
            name = (int)id;
            Langs.Clear();
            EnumResourceLanguages(module, RT_GROUP_ICON, group, langCb, IntPtr.Zero);
            ushort[] candidates = Langs.Count > 0 ? Langs.ToArray() : new ushort[] { 0 };
            foreach (ushort candidate in candidates)
            {
                data = ReadResourceAt(module, RT_GROUP_ICON, group, candidate);
                if (data != null)
                {
                    lang = candidate;
                    return true;
                }
            }
            return false;
        }
        finally { FreeLibrary(module); }
    }

    public sealed class IconSet
    {
        public int[] Ids;
        public byte[][] Images;
    }

    public static IconSet ReadIconImages(string modulePath, ushort lang, byte[] groupData)
    {
        IntPtr module = LoadLibraryEx(modulePath, IntPtr.Zero, LOAD_LIBRARY_AS_DATAFILE);
        if (module == IntPtr.Zero) throw new Exception("LoadLibraryEx 打不开 " + modulePath + " err=" + GetLastError());
        try
        {
            int count = BitConverter.ToUInt16(groupData, 4);
            IconSet set = new IconSet();
            set.Ids = new int[count];
            set.Images = new byte[count][];
            for (int i = 0; i < count; i++)
            {
                int id = BitConverter.ToUInt16(groupData, 6 + i * 14 + 12);
                set.Ids[i] = id;
                byte[] bytes = ReadResourceAt(module, RT_ICON, new IntPtr(id), lang);
                if (bytes == null) bytes = ReadResourceAt(module, RT_ICON, new IntPtr(id), 0);
                if (bytes == null) throw new Exception(modulePath + " 里缺少 ICON 资源 " + id);
                set.Images[i] = bytes;
            }
            return set;
        }
        finally { FreeLibrary(module); }
    }

    public static int WriteIcons(string exePath, int groupName, ushort groupLang, byte[] groupData, IconSet set)
    {
        ResRef[] oldIcons;
        ResRef[] oldGroups;
        IntPtr module = LoadLibraryEx(exePath, IntPtr.Zero, LOAD_LIBRARY_AS_DATAFILE);
        if (module == IntPtr.Zero) throw new Exception("LoadLibraryEx 打不开 " + exePath + " err=" + GetLastError());
        try
        {
            oldIcons = ListResources(module, RT_ICON);
            oldGroups = ListResources(module, RT_GROUP_ICON);
        }
        finally { FreeLibrary(module); }

        IntPtr handle = BeginUpdateResource(exePath, false);
        if (handle == IntPtr.Zero) throw new Exception("BeginUpdateResource 失败 err=" + GetLastError());
        bool ok = false;
        try
        {
            foreach (ResRef r in oldIcons)
                if (!UpdateResource(handle, RT_ICON, new IntPtr(r.Name), r.Lang, null, 0))
                    throw new Exception("删除旧 ICON " + r.Name + " 失败 err=" + GetLastError());
            foreach (ResRef r in oldGroups)
                if (!UpdateResource(handle, RT_GROUP_ICON, new IntPtr(r.Name), r.Lang, null, 0))
                    throw new Exception("删除旧 GROUP_ICON " + r.Name + " 失败 err=" + GetLastError());
            if (!UpdateResource(handle, RT_GROUP_ICON, new IntPtr(groupName), groupLang, groupData, groupData.Length))
                throw new Exception("写入 GROUP_ICON 失败 err=" + GetLastError());
            for (int i = 0; i < set.Ids.Length; i++)
                if (!UpdateResource(handle, RT_ICON, new IntPtr(set.Ids[i]), groupLang, set.Images[i], set.Images[i].Length))
                    throw new Exception("写入 ICON " + set.Ids[i] + " 失败 err=" + GetLastError());
            ok = true;
            return set.Ids.Length;
        }
        finally
        {
            if (!EndUpdateResource(handle, !ok) && ok)
                throw new Exception("EndUpdateResource 失败 err=" + GetLastError());
        }
    }
}
'@

[IntPtr]$dllName = [IntPtr]::Zero
[UInt16]$dllLang = 0
[Win32Resource]::VersionResource($Dll, [ref]$dllName, [ref]$dllLang)
$bytes = [Win32Resource]::ReadVersion($Dll, [ref]$dllLang)

# 写回 exe 自己原本那份 VERSIONINFO 的 name/lang 槽位，避免资源里同时留下两份。
[IntPtr]$exeName = [IntPtr]::Zero
[UInt16]$exeLang = 0
try
{
    [Win32Resource]::VersionResource($Exe, [ref]$exeName, [ref]$exeLang)
    if ($exeLang -eq 0) { $exeLang = $dllLang }
}
catch { $exeName = $dllName; $exeLang = $dllLang }

[Win32Resource]::WriteVersion($Exe, $exeName, $exeLang, $bytes)

# 图标：Runner.rc 的图标只进了 DLL，exe 还是 bootstrap 自带的 CEF 默认图标。
[Int32]$dllGroupName = 0
[UInt16]$dllGroupLang = 0
[byte[]]$dllGroupData = $null
if ([Win32Resource]::ReadIconGroup($Dll, [ref]$dllGroupName, [ref]$dllGroupLang, [ref]$dllGroupData))
{
    # 写回 exe 原有的 GROUP_ICON 槽位（bootstrap 是 32512）；exe 没有就用 DLL 的。
    [Int32]$exeGroupName = 0
    [UInt16]$exeGroupLang = 0
    [byte[]]$exeGroupData = $null
    if (-not [Win32Resource]::ReadIconGroup($Exe, [ref]$exeGroupName, [ref]$exeGroupLang, [ref]$exeGroupData))
    {
        $exeGroupName = $dllGroupName
        $exeGroupLang = $dllGroupLang
    }

    $icons = [Win32Resource]::ReadIconImages($Dll, $dllGroupLang, $dllGroupData)
    $count = [Win32Resource]::WriteIcons($Exe, $exeGroupName, $exeGroupLang, $dllGroupData, $icons)
    Write-Host ("icons -> {0} group={1}/{2} images={3}" -f (Split-Path $Exe -Leaf),
        $exeGroupName, $exeGroupLang, $count)
}
else
{
    Write-Warning "$Dll 里没有 GROUP_ICON 资源，$Exe 会继续显示默认图标"
}

$info = (Get-Item $Exe).VersionInfo
Write-Host ("identity -> {0} Company={1} Product={2} File={3}" -f (Split-Path $Exe -Leaf),
    $info.CompanyName, $info.ProductName, $info.FileVersion)
