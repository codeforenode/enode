// 自定义音源脚本的平台目录与超时。
//
// 播放地址只由用户导入的音源脚本兑换（musicUrl），项目不内置任何兜底音源；
// 搜索/歌词由各平台公开接口补齐。某个平台个别曲目兑换失败属于上游版权/线路问题，
// 由 alts 回退处理。

/// 平台尝试顺序：合并同一首歌时，靠前的平台作为主音源。
const List<String> lxPlatformCatalog = ['kw', 'kg', 'mg', 'tx', 'wy'];

const Set<String> lxDefaultPlatformIds = {'kw', 'kg', 'mg', 'tx', 'wy'};
const List<String> lxQualityOptions = ['128k', '320k', 'flac'];
const String lxDefaultQuality = '320k';
const String lxUserAgent = 'lx-music-request/2.11.0';

const Duration lxSearchTimeout = Duration(seconds: 4);
const Duration lxHttpTimeout = Duration(seconds: 12);
const Duration lxUrlTimeout = Duration(seconds: 15);
