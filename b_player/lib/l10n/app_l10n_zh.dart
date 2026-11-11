// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppL10nZh extends AppL10n {
  AppL10nZh([String locale = 'zh']) : super(locale);

  @override
  String get settingsTitle => '設定';

  @override
  String get done => '完成';

  @override
  String get close => '關閉';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '確認';

  @override
  String get delete => '刪除';

  @override
  String get notSet => '未設定';

  @override
  String get notAssigned => '未分配';

  @override
  String get tabDisplay => '顯示';

  @override
  String get tabBroadcast => '廣播';

  @override
  String get tabSources => '音源';

  @override
  String get tabCast => '螢幕管理';

  @override
  String get tabAbout => '關於';

  @override
  String get theme => '主題';

  @override
  String get themeDark => '暗色';

  @override
  String get themeLight => '亮色';

  @override
  String get themeSystem => '跟隨系統';

  @override
  String get themeSystemHint => '「跟隨系統」會隨裝置的深色模式自動切換。';

  @override
  String get textSize => '字型大小';

  @override
  String get textSizeSmall => '小';

  @override
  String get textSizeMedium => '中';

  @override
  String get textSizeLarge => '大';

  @override
  String get textSizeXLarge => '特大';

  @override
  String get displayPrefsHint => '顯示偏好保存在本機，重啟後保持。';

  @override
  String get language => '語言';

  @override
  String get languageSystem => '跟隨系統';

  @override
  String get languageSimplifiedChinese => '简体中文';

  @override
  String get languageTraditionalChinese => '繁體中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageHint => '簡體中文系統顯示簡體中文，繁體中文系統顯示繁體中文；其他語言顯示英文。';

  @override
  String get aboutVersionNode => '版本與節點';

  @override
  String get aboutVersion => '版本';

  @override
  String get aboutNodeId => '節點 ID';

  @override
  String get aboutConnection => '連線狀態';

  @override
  String get aboutLibraryDir => '曲庫資料夾';

  @override
  String get aboutLogDir => '偵錯日誌';

  @override
  String get aboutOpenLog => '開啟日誌資料夾';

  @override
  String get aboutOpenSource => '開源授權';

  @override
  String get aboutLicense => '授權條款';

  @override
  String get aboutViewLicenses => '查看授權與第三方元件';

  @override
  String get aboutOpenSourceHint =>
      '本程式以 AGPL-3.0 授權。第三方元件包含 CEF（BSD-3）、libmpv／FFmpeg（LGPL-2.1-or-later），完整清單見授權頁。';

  @override
  String get aboutSourceCode => '原始碼';

  @override
  String get aboutSourceCopied => '原始碼位址已複製';

  @override
  String get aboutUpdate => '應用程式更新';

  @override
  String get aboutUpdateIdle => '未檢查';

  @override
  String get aboutCheckUpdate => '檢查更新';

  @override
  String get aboutCheckingUpdate => '正在檢查…';

  @override
  String get aboutUpToDate => '已是最新版本';

  @override
  String get aboutNoRelease => '暫無發佈版本';

  @override
  String aboutNewVersion(String version) {
    return '有新版本 $version';
  }

  @override
  String get aboutDownloadUpdate => '下載新版本';

  @override
  String updateAvailableTitle(String version) {
    return '發現新版本 $version';
  }

  @override
  String updateAvailableBody(String current) {
    return '目前 $current，要下載新版本嗎？';
  }

  @override
  String get updateLater => '稍後';

  @override
  String get updateDownload => '前往下載';

  @override
  String get openLinkFailed => '無法開啟連結';

  @override
  String get settingsTooltip => '設定';

  @override
  String get trayOpen => '開啟 eNode';

  @override
  String get trayAutostart => '開機啟動';

  @override
  String get trayQuit => '退出';

  @override
  String get exitTitle => '要退出軟體嗎？';

  @override
  String get mqttNotConfigured => 'MQTT 未設定';

  @override
  String get mqttInvalidConfig => 'MQTT 參數有誤';

  @override
  String get mqttConnected => 'MQTT 已連線';

  @override
  String get mqttConnecting => 'MQTT 連線中';

  @override
  String get mqttFailed => 'MQTT 連線失敗';

  @override
  String get mqttDisconnected => 'MQTT 未連線';

  @override
  String get nowPlaying => '播放';

  @override
  String get queueEmpty => '隊列為空';

  @override
  String queuePosition(int total) {
    return '第 1 / $total';
  }

  @override
  String get addedHere => '本機新增';

  @override
  String fromGuest(String seat) {
    return 'C端 · $seat';
  }

  @override
  String timeLeft(String time) {
    return '剩 $time';
  }

  @override
  String get volume => '音量';

  @override
  String get queue => '隊列';

  @override
  String queueLimit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 首 / 上限 200',
    );
    return '$_temp0';
  }

  @override
  String moveToPosition(String title, int position) {
    return '把「$title」移到第 $position 位？';
  }

  @override
  String get playingNow => '播放中';

  @override
  String get paused => '已暫停';

  @override
  String get removeFromQueue => '移出隊列';

  @override
  String get library => '曲庫';

  @override
  String trackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 首',
    );
    return '$_temp0';
  }

  @override
  String missingCount(int count) {
    return '缺失 $count';
  }

  @override
  String scanProgress(int scanned, int total) {
    return '掃描中 $scanned / $total';
  }

  @override
  String get demoLibrary => '演示曲庫';

  @override
  String get libraryReady => '已就緒';

  @override
  String get noRealFolder => '未接真實資料夾';

  @override
  String get noFolder => '未設定資料夾';

  @override
  String get scanning => '掃描中…';

  @override
  String get scan => '掃描';

  @override
  String get rescan => '重新掃描';

  @override
  String get folder => '資料夾';

  @override
  String get changeFolder => '更改資料夾';

  @override
  String get grantAccess => '去授權';

  @override
  String get systemSettings => '系統設定';

  @override
  String get dirUnreadable => '無法讀取該資料夾，可能缺少儲存權限';

  @override
  String get chooseLibraryFolder => '選擇曲庫資料夾';

  @override
  String get parentFolder => '上一級';

  @override
  String get chooseFolderHint => '儲存後會立即重新掃描，子資料夾會被遞迴掃描。';

  @override
  String get chooseThisFolder => '選擇此資料夾';

  @override
  String get openStorageSettings => '去系統設定授權';

  @override
  String get noSubfolders => '這裡沒有子資料夾，可直接選擇目前資料夾';

  @override
  String get imageDirUnreadable => '讀不到這個資料夾';

  @override
  String get chooseBackgroundImage => '選擇背景圖片';

  @override
  String get pastePathHint => '也可以直接貼路徑，例如 D:\\pics\\stage.png';

  @override
  String get imagePathNote => '只存本機絕對路徑，不複製檔案、不進曲庫索引。';

  @override
  String get useThisPath => '用這個路徑';

  @override
  String imageDirError(String error) {
    return '$error —— 換個資料夾，或在下面直接貼路徑';
  }

  @override
  String get noImages => '這個資料夾下沒有圖片檔案（png/jpg/jpeg/webp/bmp/gif）';

  @override
  String get mqttIntro => '把連線資訊整段貼進來就行，Broker、連接埠、帳號、密碼會自動識別，不用逐項填寫。';

  @override
  String get mqttIntroUnconfigured => '還沒有設定 MQTT。把中繼那邊的連線資訊整段貼進來，識別後立即連線。';

  @override
  String get mqttPasteHint =>
      'mqtt://帳號:密碼@位址:1883\n或：位址 / 連接埠 / 帳號 / 密碼 分多行貼上';

  @override
  String get mqttApplying => '套用中…';

  @override
  String get mqttApply => '識別並套用';

  @override
  String get mqttClear => '清除本機設定';

  @override
  String get mqttActive => '目前生效';

  @override
  String get mqttNotConfiguredShort => '未設定';

  @override
  String get mqttAnonymous => '匿名';

  @override
  String mqttPasswordMasked(int length) {
    return '••••••（$length 位）';
  }

  @override
  String get mqttTopicPrefix => '主題前綴';

  @override
  String get mqttLocalOnly => '參數只保存在本機，密碼不會寫進日誌。';

  @override
  String mqttApplied(String host, int port) {
    return '已識別並套用 $host:$port';
  }

  @override
  String applyFailed(String error) {
    return '套用失敗：$error';
  }

  @override
  String get mqttCleared => '已清除本機設定';

  @override
  String clearFailed(String error) {
    return '清除失敗：$error';
  }

  @override
  String get brokerAddress => 'Broker 位址';

  @override
  String get username => '帳號';

  @override
  String get password => '密碼';

  @override
  String get pasteEmpty => '先貼上一段連線資訊';

  @override
  String get pasteUnrecognized =>
      '沒認出連線資訊。可以貼 mqtt://帳號:密碼@位址:連接埠，或位址/連接埠/帳號/密碼多行。';

  @override
  String get pasteMissingHost => 'JSON 裡缺少 host（Broker 位址）';

  @override
  String get pasteNoWebsocket => '暫不支援 ws/wss 位址，請換成 mqtt://位址:連接埠';

  @override
  String get pasteBadHost => 'Broker 位址格式不對';

  @override
  String get configHostRequired => 'Broker 位址不能為空';

  @override
  String get configPortRange => '連接埠需在 1–65535';

  @override
  String get configTopicPrefix => '主題前綴不能為空，且不能含 #、+、空格';

  @override
  String get configClientIdTooLong => 'Client ID 過長';

  @override
  String connectFailed(String error) {
    return '連線失敗：$error';
  }

  @override
  String connectNotEstablished(String state) {
    return '連線未建立（$state）';
  }

  @override
  String get connectionClosed => '連線已斷開';

  @override
  String publishFailed(String error) {
    return '發佈失敗：$error';
  }

  @override
  String get searchTimeout => '檢索逾時';

  @override
  String get permNoPermissionNeeded => '無需授權';

  @override
  String get permAllFiles => '已授權（所有檔案存取）';

  @override
  String get permAudioOnly => '僅音訊可讀；讀取 .lrc 與掃描資料夾還需「所有檔案存取」';

  @override
  String get permNotGranted => '未授權：請在系統設定中允許存取儲存空間';

  @override
  String folderMissing(String root) {
    return '資料夾不存在：$root';
  }

  @override
  String folderUnreadable(String message) {
    return '無法讀取資料夾：$message';
  }

  @override
  String get unknownArtist => '未知歌手';

  @override
  String get lyricsEmpty => '歌詞為空';

  @override
  String get noLyrics => '沒有歌詞';

  @override
  String get castNoLyrics => '暫無歌詞';

  @override
  String get onlineLibrary => '線上曲庫';

  @override
  String get localFolder => '本地目錄';

  @override
  String get demoNoLyrics => '演示曲目沒有歌詞';

  @override
  String get unsupportedSearch => '該音源不支援檢索';

  @override
  String get unsupportedPlay => '該音源不支援播放';

  @override
  String get unsupportedLyrics => '該音源不支援歌詞';

  @override
  String get kugouSearchFailed => '酷狗搜尋失敗';

  @override
  String get kugouMissingHash => '酷狗曲目缺少 hash';

  @override
  String get kugouNoLyrics => '酷狗沒有找到歌詞';

  @override
  String get kugouMissingCredential => '酷狗歌詞缺少憑證';

  @override
  String get kugouLyricsEmpty => '酷狗歌詞為空';

  @override
  String get kuwoSearchFailed => '酷我搜尋失敗';

  @override
  String get kuwoNoLyrics => '酷我沒有歌詞';

  @override
  String get kuwoMissingId => '酷我曲目缺少 ID';

  @override
  String get miguSearchFailed => '咪咕搜尋失敗';

  @override
  String get miguNoLyricUrl => '咪咕曲目沒有歌詞位址';

  @override
  String get miguLyricsEmpty => '咪咕歌詞為空';

  @override
  String get qqSearchFailed => 'QQ 音樂搜尋失敗';

  @override
  String get qqMissingMid => 'QQ 音樂曲目缺少 mid';

  @override
  String get qqNoLyrics => 'QQ 音樂沒有歌詞';

  @override
  String get neteaseMissingId => '網易雲曲目缺少 ID';

  @override
  String get neteaseNoLyrics => '網易雲沒有歌詞';

  @override
  String get lyricsDecodeFailed => '歌詞內容解碼失敗';

  @override
  String get httpBadJson => '回應不是有效 JSON';

  @override
  String get httpRateLimited => '請求過速，請稍後再試';

  @override
  String httpUnavailable(int status) {
    return '服務暫時不可用（HTTP $status）';
  }

  @override
  String httpFailed(int status) {
    return '請求失敗（HTTP $status）';
  }

  @override
  String get httpTimeout => '網路逾時';

  @override
  String get httpError => '網路請求失敗';

  @override
  String get networkUnavailable => '網路不可用';

  @override
  String jsHostFailed(String detail) {
    return 'JS 宿主初始化失敗：$detail';
  }

  @override
  String scriptRunFailed(String detail) {
    return '腳本執行失敗：$detail';
  }

  @override
  String get scriptNoInited => '腳本沒有發送 inited 事件';

  @override
  String get scriptNoPlatforms => '腳本沒有宣告可用的音樂服務';

  @override
  String get sourceNotInitialized => '音源尚未初始化';

  @override
  String scriptCallFailed(String detail) {
    return '腳本呼叫失敗：$detail';
  }

  @override
  String get scriptNoResult => '腳本沒有返回結果';

  @override
  String get scriptError => '腳本返回錯誤';

  @override
  String get scriptBadUrl => '腳本返回的播放位址無效';

  @override
  String jsUnavailable(String error) {
    return 'JS 引擎不可用：$error';
  }

  @override
  String get runtimeDisposed => '執行時已釋放';

  @override
  String get scriptBadJson => '腳本返回值不是有效 JSON';

  @override
  String get requestBadUrl => '請求位址無效';

  @override
  String get requestHttpOnly => '只支援 http(s) 請求';

  @override
  String get requestNoMultipart => '暫不支援 multipart 請求';

  @override
  String scriptTimeout(String what) {
    return '$what逾時';
  }

  @override
  String get scriptInit => '腳本初始化';

  @override
  String get playbackResolve => '播放位址解析';

  @override
  String get trackNoPlatform => '曲目缺少線上來源標識';

  @override
  String resolveFailed(String error) {
    return '播放位址解析失敗：$error';
  }

  @override
  String get resolveFailedShort => '播放位址解析失敗';

  @override
  String get noImportedScripts => '尚未匯入音源腳本';

  @override
  String get noUsableScripts => '沒有可用的音源腳本';

  @override
  String sourceResolveFailed(String detail) {
    return '音源取鏈失敗：$detail';
  }

  @override
  String lyricsFetchFailed(String error) {
    return '歌詞取得失敗：$error';
  }

  @override
  String get trackNoLyrics => '該曲目沒有歌詞';

  @override
  String get sourceUrlScheme => '音源位址需以 http(s):// 開頭';

  @override
  String downloadFailed(int status) {
    return '下載失敗（HTTP $status）';
  }

  @override
  String get sourceInvalid => '不是有效的音源腳本（缺少 @name 標頭）';

  @override
  String get downloadTimeout => '下載逾時';

  @override
  String get sourceUnavailable => '音源暫不可用';

  @override
  String get platformResolveUnsupported => '該音源不支援此曲目取鏈';

  @override
  String get sourceNotFound => '音源不存在';

  @override
  String get seatLocal => '本機';

  @override
  String get localTag => '本地';

  @override
  String scanFailed(String error) {
    return '掃描失敗：$error';
  }

  @override
  String probeReady(int ms) {
    return '就緒 ${ms}ms';
  }

  @override
  String get probeNoResolve => ' · 無取鏈動作';

  @override
  String probeFailed(String error) {
    return '失敗：$error';
  }

  @override
  String get probeNoOnlineSource => '未接入線上音源';

  @override
  String probeZero(int ms) {
    return '0 條 · ${ms}ms';
  }

  @override
  String probeTracks(int count, int ms, int resolveMs, String host) {
    return '$count 條 · ${ms}ms · 取鏈 ${resolveMs}ms ($host)';
  }

  @override
  String probeResolveFailed(int count, int ms, String error) {
    return '$count 條 · ${ms}ms · 取鏈失敗：$error';
  }

  @override
  String get audioFormatUnsupported => '無法識別音訊格式';

  @override
  String get audioOpenFailed => '無法開啟音訊檔案';

  @override
  String skipResolveFailed(String title) {
    return '無法解析「$title」的播放位址，已跳過';
  }

  @override
  String playOpenFailed(String title, String error) {
    return '無法播放「$title」：$error';
  }

  @override
  String skipUnplayable(String title) {
    return '「$title」無法播放，已跳過';
  }

  @override
  String get castBgSolid => '純黑';

  @override
  String get castBgGradient => '上下漸層';

  @override
  String get castBgCustom => '自訂色';

  @override
  String get castBgImage => '圖片';

  @override
  String get castAlignLeft => '左對齊';

  @override
  String get castAlignCenter => '居中';

  @override
  String get castAlignRight => '右對齊';

  @override
  String get onlineSourcesTitle => '線上音源';

  @override
  String scriptCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 個腳本',
    );
    return '$_temp0';
  }

  @override
  String get sourcesIntro => '改動即時生效，不需要另外儲存。取鏈按下面的順序逐個嘗試。';

  @override
  String get sourcesEmpty => '還沒有匯入音源；線上取鏈需要至少一個音源腳本。';

  @override
  String get importHint => '貼上音源腳本位址，例如 https://.../source.js';

  @override
  String get importing => '匯入中…';

  @override
  String get importAction => '匯入';

  @override
  String importedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已匯入並啟用 · 共 $count 個腳本',
    );
    return '$_temp0';
  }

  @override
  String importFailedOnline(String error) {
    return '匯入失敗：$error';
  }

  @override
  String saveFailed(String error) {
    return '儲存失敗：$error';
  }

  @override
  String get needSourceUrl => '請先填寫音源位址';

  @override
  String get sourceEnabled => '已啟用';

  @override
  String get sourceDisabled => '已停用';

  @override
  String get sourceOrderUpdated => '取鏈順序已更新';

  @override
  String get sourceRemoved => '已刪除該音源';

  @override
  String get qualityLabel => '音質';

  @override
  String get qualitySaved => '音質已儲存';

  @override
  String get restoreDefaults => '恢復預設音質';

  @override
  String get defaultsRestored => '音質已恢復預設';

  @override
  String statusError(String error) {
    return '錯誤：$error';
  }

  @override
  String get moveUp => '上移';

  @override
  String get moveDown => '下移';

  @override
  String get testSourceTooltip => '測試：腳本 + 檢索 + 取鏈';

  @override
  String get checkSourceUpdate => '檢查更新';

  @override
  String get sourceUpToDate => '已是最新版本';

  @override
  String sourceUpdateFound(String latest, String current) {
    return '發現新版 $latest · 目前 $current';
  }

  @override
  String get sourceUpdateApply => '更新';

  @override
  String get sourceUpdateDismiss => '忽略';

  @override
  String sourceUpdated(String version) {
    return '已更新至 $version';
  }

  @override
  String get sourceUpdatedPlain => '音源已更新';

  @override
  String sourceNotice(String message) {
    return '音源提示：$message';
  }

  @override
  String sourceNoticeLink(String url) {
    return '更新地址：$url';
  }

  @override
  String updateCheckFailed(String error) {
    return '檢查更新失敗：$error';
  }

  @override
  String get castTitle => '螢幕管理';

  @override
  String castSummary(int monitors, int windows) {
    return '$monitors 台螢幕 · $windows 個投放窗';
  }

  @override
  String get castIntro =>
      '每台勾選的螢幕開一扇置頂穿透窗；樣式和時鐘只有一份，所以畫面天然同步，改動即時生效。投放中在投放螢幕上按右鍵，可關掉本螢幕或全部投放。';

  @override
  String get castNoMonitors =>
      '沒掃到螢幕（screen_retriever 不可用或只有一塊螢幕時也可能為空）。插好螢幕後重新掃描。';

  @override
  String get castNoMonitorsFound => '還是沒掃到螢幕';

  @override
  String get castDetected => '偵測到';

  @override
  String castDetectedValue(int count) {
    return '$count 台';
  }

  @override
  String get castCasting => '投放';

  @override
  String castCastingValue(int count) {
    return '$count 個視窗';
  }

  @override
  String get castOpen => '已開';

  @override
  String castOpenValue(int count) {
    return '$count 扇';
  }

  @override
  String get castMemory => '額外記憶體';

  @override
  String get castSync => '同步';

  @override
  String get castSyncValue => '一塊畫布 · 同幀呈現';

  @override
  String get castEnable => '啟用投放';

  @override
  String castEnabledHint(int count) {
    return '已開 $count 扇投放窗，滑鼠點得穿，結束程式時自動收起。';
  }

  @override
  String get castDisabledHint => '關掉時只有這裡的預覽，勾選的螢幕上不會開窗。';

  @override
  String get castTargetsTitle => '投放目標';

  @override
  String get castMultiSelect => '可多選';

  @override
  String get castTargetsHint => '只有勾選的螢幕才出現在下面的地圖和預覽裡。';

  @override
  String castMonitorLabel(int index, String name) {
    return '$index 號 · $name';
  }

  @override
  String castMonitorSpec(
    int fullW,
    int fullH,
    int workW,
    int workH,
    int scale,
  ) {
    return '整屏 $fullW×$fullH · 工作區 $workW×$workH · 縮放 $scale%';
  }

  @override
  String get castFullscreen => '全屏';

  @override
  String get castRegion => '區域';

  @override
  String get castEditing => '編輯中';

  @override
  String get castEditScreen => '編輯這塊螢幕';

  @override
  String get castRegionTitle => '區域框選';

  @override
  String get castNoSelection => '還沒勾選任何螢幕 —— 在上面勾一台，這裡就只出現被選中的螢幕。';

  @override
  String get castPresetBottomStrip => '底部字幕條';

  @override
  String get castPresetLowerHalf => '下半屏';

  @override
  String get castPresetCenterStrip => '居中窄條';

  @override
  String get castMapHint => '在地圖上直接拖：框內移動、八向把手縮放、空白處重新框選。';

  @override
  String get castMoveLeft => '左移';

  @override
  String get castMoveUp => '上移';

  @override
  String get castMoveDown => '下移';

  @override
  String get castMoveRight => '右移';

  @override
  String get castCenterH => '水平居中';

  @override
  String get castCenterV => '垂直居中';

  @override
  String get castLeftPx => '左 (px)';

  @override
  String get castTopPx => '上 (px)';

  @override
  String get castWidthPx => '寬 (px)';

  @override
  String get castHeightPx => '高 (px)';

  @override
  String castPercentSummary(
    String left,
    String top,
    String width,
    String height,
    int workW,
    int workH,
  ) {
    return '存成百分比 $left/$top · $width×$height · 該螢幕工作區 $workW×$workH 邏輯 px';
  }

  @override
  String get castStyleTitle => '歌詞樣式';

  @override
  String get castLines => '顯示行數';

  @override
  String get castLinesCurrent => '僅目前句';

  @override
  String get castLinesPrev => '上一句 + 目前';

  @override
  String get castLinesBoth => '上句 + 目前 + 下句';

  @override
  String get castFont => '字型';

  @override
  String get castFontSize => '字號';

  @override
  String get castFontSizeUnit => 'px（按 1080 高折算）';

  @override
  String get castLineGap => '行間距';

  @override
  String get castTextWidth => '文字寬度';

  @override
  String get castTextHeight => '文字高度';

  @override
  String get castWeight => '字重';

  @override
  String get castWeightRegular => '400 一般';

  @override
  String get castWeightMedium => '500 中等';

  @override
  String get castWeightSemibold => '600 半粗';

  @override
  String get castWeightBold => '700 粗體';

  @override
  String get castStroke => '描邊';

  @override
  String get castStrokeUnit => 'px（黑色描邊，壓住背景圖和影片）';

  @override
  String get castShadow => '陰影';

  @override
  String get castCurrentColor => '目前歌詞顏色';

  @override
  String get castOtherColor => '非目前歌詞顏色';

  @override
  String get castOtherOpacity => '非目前歌詞行透明度';

  @override
  String get castKaraokeColorHint => '逐字歌詞：已唱的字用目前歌詞顏色，未唱的字用非目前歌詞顏色。';

  @override
  String get castBackground => '投放背景';

  @override
  String get castGradientTop => '漸層上';

  @override
  String get castGradientBottom => '漸層下';

  @override
  String get castSolidColor => '背景色';

  @override
  String get castNoImage => '還沒選圖片';

  @override
  String get castBrowse => '瀏覽…';

  @override
  String get castClear => '清除';

  @override
  String get castImageFit => '畫面鋪法';

  @override
  String get castFitCover => '鋪滿裁邊';

  @override
  String get castFitContain => '完整顯示';

  @override
  String get castAlign => '水平對齊';

  @override
  String get castVertical => '垂直位置';

  @override
  String get castVerticalUnit => '%（0=貼頂，歌詞塊中心）';

  @override
  String get castOffset => '歌詞偏移';

  @override
  String get castOffsetUnit => 'ms（正值往後推）';

  @override
  String get castExtras => '附加資訊';

  @override
  String get castShowTitle => '歌名';

  @override
  String get castShowArtist => '歌手';

  @override
  String get castShowSeat => '座位號';

  @override
  String get castPreview => '預覽';

  @override
  String get castLiveBadge => '跟隨本機播放';

  @override
  String get castDemoBadge => '演示走詞';

  @override
  String get castPause => '暫停';

  @override
  String get castPlay => '播放';

  @override
  String get castPickScreen => '勾一台螢幕就能在這裡看到實際畫面。';

  @override
  String get castPreviewLiveHint => '預覽按這台螢幕的投放區比例繪製，投放窗用的是同一套繪製。';

  @override
  String get castPreviewDemoHint => '沒在播歌，用演示詞走一遍；開始播放後這裡會自動變成真實歌詞。';

  @override
  String get castPickColor => '選顏色';

  @override
  String get castColorHint => '#RRGGBB 或 #AARRGGBB；A 是文字自身的透明度。';

  @override
  String get castDemoTitle => '晚風不歇';

  @override
  String get castDemoArtist => 'demo 歌手';

  @override
  String get castFontYaHei => '微軟雅黑';

  @override
  String get castFontHei => '黑體';

  @override
  String get castFontSong => '宋體';

  @override
  String get castFontKai => '楷體';

  @override
  String get castFontDeng => '等線';

  @override
  String fileMissing(String path) {
    return '檔案不存在：$path';
  }

  @override
  String castWindowTitle(String name) {
    return 'eNode 歌詞投放 · $name';
  }

  @override
  String get castRuntimeMissing => 'Chromium 執行環境起不來';

  @override
  String get castRegionZero => '投放區尺寸為 0';

  @override
  String get castNoBrowserHandle => '畫布瀏覽器沒有回傳控制代碼';

  @override
  String get castNoPresenter => '畫布沒有可顯示的 presenter（需要 GPU 加速）';

  @override
  String castCanvasFallback(String error) {
    return '畫布投放起不來，退回一屏一窗：$error';
  }

  @override
  String castWindowTimeout(String name) {
    return '$name 的投放窗 12 秒沒起來——多引擎可能被顯卡驅動或安全軟體攔了';
  }

  @override
  String castWindowCreateFailed(String name, String error) {
    return '$name 的投放窗建不起來：$error';
  }

  @override
  String castWebFallback(String reason) {
    return '網頁投放退回自繪：$reason';
  }

  @override
  String castWindowGone(String name, String error) {
    return '$name 的投放窗已經不在了，改一下投放設定會重新開：$error';
  }

  @override
  String castPageLoadFailed(int code, String detail) {
    return '投放頁面載入失敗（$code）$detail';
  }

  @override
  String castPushFailed(String error) {
    return '推送畫面失敗：$error';
  }

  @override
  String castWebError(String error) {
    return '網頁投放異常：$error';
  }

  @override
  String get castModeFull => '整屏';

  @override
  String screenSummary(int monitors, int materials, int placements) {
    return '$monitors 台螢幕 · $materials 個素材 · $placements 個投放';
  }

  @override
  String get screenLiveSync => '投放同步中';

  @override
  String get screenEditOnly => '僅編輯，未投放';

  @override
  String screenCastingValue(int enabled, int total) {
    return '$enabled/$total 投屏';
  }

  @override
  String get screenScreens => '螢幕';

  @override
  String screenCount(int count) {
    return '$count 台';
  }

  @override
  String get screenScreenHint => '點選一台螢幕開始排版';

  @override
  String screenLayersCount(int count) {
    return '$count 個圖層';
  }

  @override
  String screenUrlBadge(int count) {
    return '網頁 $count';
  }

  @override
  String screenVideoBadge(int count) {
    return '影片 $count';
  }

  @override
  String get screenLoadLight => '輕';

  @override
  String get screenLoadMid => '中';

  @override
  String get screenLoadHeavy => '重';

  @override
  String get screenStatus => '狀態';

  @override
  String get screenCastingScreens => '投屏';

  @override
  String get screenSharedCanvas => '共用畫布';

  @override
  String get screenMaterials => '素材';

  @override
  String screenMaterialsValue(int count) {
    return '$count 個';
  }

  @override
  String get screenStatusHintOn => '投放窗由一塊畫布驅動，改樣式會即時同步。';

  @override
  String get screenStatusHintOff => '未勾選任何螢幕時，畫布只做編輯預覽。';

  @override
  String get screenDetect => '偵測';

  @override
  String screenRescanHint(int count) {
    return '目前 $count 台。插拔螢幕或改解析度後重掃。';
  }

  @override
  String get screenAddMaterial => '新增素材';

  @override
  String screenToolbarCounts(int layers, int urls, int videos) {
    return '$layers 層 · 網頁 $urls · 影片 $videos';
  }

  @override
  String get screenCastingBadge => '投放中';

  @override
  String get screenNotCasting => '未投放';

  @override
  String screenPerfWarning(int urls, int videos) {
    return '這一屏有 $urls 個網頁、$videos 支影片。每一路都會多一份解碼與合成開銷，建議同屏各留一個。';
  }

  @override
  String get screenNoSelection => '選中畫面上的素材調整位置 · 拖角縮放';

  @override
  String screenSelectionInfo(String name, int x, int y, int w, int h) {
    return '$name · $x, $y · $w×$h px';
  }

  @override
  String get screenShelf => '素材庫';

  @override
  String get screenShelfHint => '拖到畫面或點一下放上這屏';

  @override
  String get screenShelfMore => '同一素材放到多屏只保留一份樣式；位置、層級與本屏聲音各自獨立。';

  @override
  String screenShelfCount(int count) {
    return '$count 個';
  }

  @override
  String get screenUsageShared => '共用';

  @override
  String get screenUsageHere => '本屏';

  @override
  String get screenUsageOther => '他屏';

  @override
  String get screenUsageNone => '未用';

  @override
  String screenUsageScreens(int count) {
    return '$count 屏使用';
  }

  @override
  String get screenUsageSingle => '獨立素材';

  @override
  String get screenLayers => '圖層';

  @override
  String get screenLayersHint => '拖動排序 · 上層在前';

  @override
  String get screenLayersEmpty => '這一屏還沒有圖層。從素材庫加入，或按「新增素材」。';

  @override
  String get screenShow => '顯示';

  @override
  String get screenHide => '隱藏';

  @override
  String get screenLock => '鎖定';

  @override
  String get screenUnlock => '解鎖';

  @override
  String get screenSound => '聲音';

  @override
  String get screenBackToScreen => '螢幕設定';

  @override
  String get screenMaterialName => '素材名稱';

  @override
  String get screenDuplicate => '複製為獨立素材';

  @override
  String get screenDeleteLayer => '刪除圖層';

  @override
  String get screenAddLayer => '新增圖層';

  @override
  String get screenDeleteMaterial => '刪除素材';

  @override
  String get screenSectionLyric => '歌詞';

  @override
  String get screenFollowNow => '跟隨目前播放';

  @override
  String get screenOverlayAbove => '疊在歌詞上方';

  @override
  String screenLineCount(int count) {
    return '$count 行';
  }

  @override
  String get screenTimeOffset => '時間偏移';

  @override
  String get screenLyricNoBgNote => '歌詞不帶底色。要背景就把圖片或影片拉到滿版、鎖定、放最底層。';

  @override
  String get screenSectionUrl => '網址';

  @override
  String get screenEmbedPage => '嵌入網頁';

  @override
  String get screenUrlPlaceholder => 'https://…';

  @override
  String get screenUrlReloadHint => '改網址或按重新載入才會刷新。';

  @override
  String get screenReload => '重新載入';

  @override
  String get screenRefresh => '刷新間隔';

  @override
  String get screenSeconds => '秒';

  @override
  String get screenUrlEmbedNote =>
      '對方網站若禁止嵌入（X-Frame-Options / CSP），畫面會空白；可改用圖片或影片素材。';

  @override
  String get screenUrlPreviewHint => '投放時在這裡顯示網頁';

  @override
  String get screenScreenSound => '本屏聲音';

  @override
  String get screenVolume => '音量';

  @override
  String get screenSource => '來源';

  @override
  String get screenStaticContent => '靜態內容';

  @override
  String get screenSectionImage => '圖片';

  @override
  String get screenSectionVideo => '影片';

  @override
  String get screenSectionText => '文字';

  @override
  String get screenSectionSound => '本屏播放';

  @override
  String get screenLocalFile => '本機檔案';

  @override
  String get screenUrlSource => '圖片網址';

  @override
  String get screenImageUrl => '圖片網址';

  @override
  String get screenVideoUrl => '影片網址';

  @override
  String get screenFilePath => '檔案路徑';

  @override
  String get screenImageUrlPlaceholder => 'https://…/photo.jpg';

  @override
  String get screenImagePathPlaceholder => '選擇本機圖片…';

  @override
  String get screenVideoUrlPlaceholder => 'https://…/clip.mp4';

  @override
  String get screenVideoPathPlaceholder => '選擇本機影片…';

  @override
  String get screenFill => '填充';

  @override
  String get screenFitStretch => '拉伸';

  @override
  String get screenRadius => '圓角';

  @override
  String get screenLoop => '循環播放';

  @override
  String get screenPlayOnce => '單次';

  @override
  String get screenAutoplay => '自動播放';

  @override
  String get screenMuted => '靜音';

  @override
  String get screenMuteOthersNote => '同一屏只保留一路有聲；開啟時其他素材會自動靜音。';

  @override
  String get screenImageBgNote => '全屏背景照樣用圖片做：拉到滿版、放到最底層、鎖定圖層即可。';

  @override
  String get screenTextPlaceholder => '輸入文字…';

  @override
  String get screenTextNote => '文字本身沒有背景；需要底色或壓暗時，在下面加一個圖片或影片圖層。';

  @override
  String get screenColor => '顏色';

  @override
  String get screenGeometry => '位置與層級';

  @override
  String get screenOpacity => '不透明度';

  @override
  String get screenZOrder => '層級';

  @override
  String get screenZTop => '置頂';

  @override
  String get screenZUp => '上移一層';

  @override
  String get screenZDown => '下移一層';

  @override
  String get screenZBottom => '置底';

  @override
  String get screenShownOn => '顯示於';

  @override
  String get screenLockLayer => '鎖定圖層';

  @override
  String get screenSharedNote => '樣式與內容同步到共用此素材的螢幕；位置、透明度、層級與本屏聲音各自獨立。';

  @override
  String get screenCanvasColor => '畫布底色';

  @override
  String get screenTransparent => '透明';

  @override
  String get screenBlack => '純黑';

  @override
  String get screenMidnight => '午夜';

  @override
  String get screenLightCanvas => '淺色';

  @override
  String get screenCustomColor => '自訂顏色';

  @override
  String get screenCanvasNote => '透明會讓桌面透出來；選顏色則鋪一層不透明底色。';

  @override
  String get screenCast => '投放';

  @override
  String get screenCastThisScreen => '投放這塊螢幕';

  @override
  String get screenCoverage => '覆蓋範圍';

  @override
  String get screenFull => '整屏';

  @override
  String get screenWork => '工作區';

  @override
  String get screenPerformance => '效能';

  @override
  String get screenPerfLayers => '圖層';

  @override
  String get screenPerfUrls => '網頁';

  @override
  String get screenPerfVideos => '影片';

  @override
  String get screenPerfAudio => '有聲';

  @override
  String get screenPerfHint => '網頁與影片每多一路，CPU/GPU 與記憶體都會明顯上升；同屏各留一個最穩。';

  @override
  String get screenTips => '小提示';

  @override
  String get screenTipsText =>
      '拖動素材移動、拖八個角縮放；方向鍵微調（Shift ×10），Delete 刪除，Esc 取消選取。';

  @override
  String get screenSoundFollowsScreen => '聲音跟屏走';

  @override
  String get screenEmptyMaterial => '還沒設定內容';

  @override
  String get screenPickImage => '選擇圖片';

  @override
  String get screenPickVideo => '選擇影片';

  @override
  String get screenNoVideos => '這個資料夾下沒有影片檔案（mp4/webm/mov/mkv/avi/m4v/ogv）';

  @override
  String get screenTagLight => '輕量';

  @override
  String get screenTagNormal => '普通';

  @override
  String get screenTagHeavy => '較重';

  @override
  String get screenTypeLyric => '歌詞';

  @override
  String get screenTypeLyricDesc => '跟隨播放的即時歌詞';

  @override
  String get screenTypeUrl => '網址';

  @override
  String get screenTypeUrlDesc => '嵌入一個網頁';

  @override
  String get screenTypeImage => '圖片';

  @override
  String get screenTypeImageDesc => '本機檔案或圖片網址';

  @override
  String get screenTypeVideo => '影片';

  @override
  String get screenTypeVideoDesc => '本機或網絡影片，可帶聲音';

  @override
  String get screenTypeText => '文字';

  @override
  String get screenTypeTextDesc => '靜態文字';

  @override
  String get sourcesTitle => '音源';

  @override
  String sourcesTotal(int count) {
    return '曲庫共 $count 首';
  }

  @override
  String sourcesSummary(int local, int webdav) {
    return '本地 $local 首 · WebDAV $webdav 首';
  }

  @override
  String get manageSources => '管理';

  @override
  String get localSourceTitle => '本地音源';

  @override
  String get webdavSourceTitle => 'WebDAV 音源';

  @override
  String webdavCount(int count) {
    return '$count 個';
  }

  @override
  String get webdavEmptyTitle => '還沒有 WebDAV 音源';

  @override
  String get webdavEmptyHint => '連接 NAS 或任意 WebDAV 服務，掃描後與本地曲庫一起參與點歌';

  @override
  String get webdavAdd => '新增';

  @override
  String get webdavAddTitle => '新增 WebDAV 音源';

  @override
  String get webdavEditTitle => '編輯 WebDAV 音源';

  @override
  String get webdavName => '名稱';

  @override
  String get webdavUrl => '伺服器位址';

  @override
  String get webdavUsername => '使用者名稱';

  @override
  String get webdavPassword => '密碼';

  @override
  String get webdavAllowSelfSigned => '允許自簽章憑證（NAS 常用）';

  @override
  String get webdavDialogHint => '連線資訊只保存在本機；掃描後可像本地曲庫一樣檢索、點歌和投放。';

  @override
  String get webdavTest => '測試連線';

  @override
  String get webdavSaveAndScan => '儲存並掃描';

  @override
  String get webdavSync => '同步';

  @override
  String get webdavSyncing => '同步中…';

  @override
  String get webdavNeverSynced => '尚未同步';

  @override
  String get webdavEdit => '編輯';

  @override
  String get webdavDelete => '刪除';

  @override
  String get webdavMore => '更多';

  @override
  String webdavDeleteConfirm(String name) {
    return '刪除「$name」？';
  }

  @override
  String get webdavInvalidUrl => '伺服器位址需以 http(s):// 開頭';

  @override
  String get webdavNeedUrl => '請先填寫伺服器位址';

  @override
  String get webdavNeedName => '請先填寫名稱';

  @override
  String webdavTestOk(int count) {
    return '連線正常，根目錄有 $count 個項目';
  }

  @override
  String webdavTestFailed(String error) {
    return '連線失敗：$error';
  }

  @override
  String webdavAuthFailed(int status) {
    return '認證失敗（HTTP $status）';
  }

  @override
  String webdavHttpError(int status) {
    return '伺服器回應 HTTP $status';
  }

  @override
  String webdavConnectFailed(String detail) {
    return '連線失敗：$detail';
  }

  @override
  String webdavTlsFailed(String detail) {
    return '憑證校驗失敗，可允許自簽章憑證：$detail';
  }

  @override
  String get webdavTimeout => '連線逾時';

  @override
  String get webdavInvalidXml => '無法解析 WebDAV 回應';

  @override
  String get webdavNotDav => '這個位址不是 WebDAV 服務';

  @override
  String get webdavNotFound => '遠端資料夾不存在';

  @override
  String webdavPartialFolders(int count) {
    return '$count 個資料夾讀取失敗，已同步其餘曲目';
  }

  @override
  String webdavFileUnavailable(String name) {
    return '遠端檔案不可用：$name';
  }

  @override
  String webdavSyncedAt(String time) {
    return '同步於 $time';
  }

  @override
  String webdavLastScanned(String time) {
    return '上次掃描 $time';
  }

  @override
  String webdavSyncProgress(int tracks, int folders) {
    return '已發現 $tracks 首 · $folders 個資料夾';
  }

  @override
  String get webdavTesting => '測試中…';

  @override
  String get webdavSaving => '儲存中…';
}

/// The translations for Chinese, using the Han script (`zh_Hans`).
class AppL10nZhHans extends AppL10nZh {
  AppL10nZhHans() : super('zh_Hans');

  @override
  String get settingsTitle => '设置';

  @override
  String get done => '完成';

  @override
  String get close => '关闭';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确认';

  @override
  String get delete => '删除';

  @override
  String get notSet => '未设置';

  @override
  String get notAssigned => '未分配';

  @override
  String get tabDisplay => '显示';

  @override
  String get tabBroadcast => '广播';

  @override
  String get tabSources => '音源';

  @override
  String get tabCast => '屏幕管理';

  @override
  String get tabAbout => '关于';

  @override
  String get theme => '主题';

  @override
  String get themeDark => '暗色';

  @override
  String get themeLight => '亮色';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeSystemHint => '「跟随系统」会随设备的深色模式自动切换。';

  @override
  String get textSize => '字体大小';

  @override
  String get textSizeSmall => '小';

  @override
  String get textSizeMedium => '中';

  @override
  String get textSizeLarge => '大';

  @override
  String get textSizeXLarge => '特大';

  @override
  String get displayPrefsHint => '显示偏好保存在本机，重启后保持。';

  @override
  String get language => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageSimplifiedChinese => '简体中文';

  @override
  String get languageTraditionalChinese => '繁體中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageHint => '简体中文系统显示简体中文，繁体中文系统显示繁体中文；其他语言显示英文。';

  @override
  String get aboutVersionNode => '版本与节点';

  @override
  String get aboutVersion => '版本';

  @override
  String get aboutNodeId => '节点 ID';

  @override
  String get aboutConnection => '连接状态';

  @override
  String get aboutLibraryDir => '曲库文件夹';

  @override
  String get aboutLogDir => '调试日志';

  @override
  String get aboutOpenLog => '打开日志目录';

  @override
  String get aboutOpenSource => '开源许可';

  @override
  String get aboutLicense => '许可证';

  @override
  String get aboutViewLicenses => '查看许可与第三方组件';

  @override
  String get aboutOpenSourceHint =>
      '本程序以 AGPL-3.0 授权。第三方组件包含 CEF（BSD-3）、libmpv/FFmpeg（LGPL-2.1-or-later），完整清单见许可页。';

  @override
  String get aboutSourceCode => '源代码';

  @override
  String get aboutSourceCopied => '源代码地址已复制';

  @override
  String get aboutUpdate => '应用更新';

  @override
  String get aboutUpdateIdle => '未检查';

  @override
  String get aboutCheckUpdate => '检查更新';

  @override
  String get aboutCheckingUpdate => '正在检查…';

  @override
  String get aboutUpToDate => '已是最新版本';

  @override
  String get aboutNoRelease => '暂无发布版本';

  @override
  String aboutNewVersion(String version) {
    return '有新版本 $version';
  }

  @override
  String get aboutDownloadUpdate => '下载新版本';

  @override
  String updateAvailableTitle(String version) {
    return '发现新版本 $version';
  }

  @override
  String updateAvailableBody(String current) {
    return '当前版本 $current，前往下载？';
  }

  @override
  String get updateLater => '稍后';

  @override
  String get updateDownload => '前往下载';

  @override
  String get openLinkFailed => '无法打开链接';

  @override
  String get settingsTooltip => '设置';

  @override
  String get trayOpen => '打开 eNode';

  @override
  String get trayAutostart => '开机启动';

  @override
  String get trayQuit => '退出';

  @override
  String get exitTitle => '要退出软件吗？';

  @override
  String get mqttNotConfigured => 'MQTT 未设置';

  @override
  String get mqttInvalidConfig => 'MQTT 参数有误';

  @override
  String get mqttConnected => 'MQTT 已连接';

  @override
  String get mqttConnecting => 'MQTT 连接中';

  @override
  String get mqttFailed => 'MQTT 连接失败';

  @override
  String get mqttDisconnected => 'MQTT 未连接';

  @override
  String get nowPlaying => '播放';

  @override
  String get queueEmpty => '队列为空';

  @override
  String queuePosition(int total) {
    return '第 1 / $total';
  }

  @override
  String get addedHere => '本机新增';

  @override
  String fromGuest(String seat) {
    return 'C端 · $seat';
  }

  @override
  String timeLeft(String time) {
    return '剩 $time';
  }

  @override
  String get volume => '音量';

  @override
  String get queue => '队列';

  @override
  String queueLimit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 首 / 上限 200',
    );
    return '$_temp0';
  }

  @override
  String moveToPosition(String title, int position) {
    return '把「$title」移到第 $position 位？';
  }

  @override
  String get playingNow => '播放中';

  @override
  String get paused => '已暂停';

  @override
  String get removeFromQueue => '移出队列';

  @override
  String get library => '曲库';

  @override
  String trackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 首',
    );
    return '$_temp0';
  }

  @override
  String missingCount(int count) {
    return '缺失 $count';
  }

  @override
  String scanProgress(int scanned, int total) {
    return '扫描中 $scanned / $total';
  }

  @override
  String get demoLibrary => '演示曲库';

  @override
  String get libraryReady => '已就绪';

  @override
  String get noRealFolder => '未接真实文件夹';

  @override
  String get noFolder => '未设置文件夹';

  @override
  String get scanning => '扫描中…';

  @override
  String get scan => '扫描';

  @override
  String get rescan => '重新扫描';

  @override
  String get folder => '文件夹';

  @override
  String get changeFolder => '更改文件夹';

  @override
  String get grantAccess => '去授权';

  @override
  String get systemSettings => '系统设置';

  @override
  String get dirUnreadable => '无法读取该文件夹，可能缺少存储权限';

  @override
  String get chooseLibraryFolder => '选择曲库文件夹';

  @override
  String get parentFolder => '上一级';

  @override
  String get chooseFolderHint => '保存后会立即重新扫描，子文件夹会被递归扫描。';

  @override
  String get chooseThisFolder => '选择此文件夹';

  @override
  String get openStorageSettings => '去系统设置授权';

  @override
  String get noSubfolders => '这里没有子文件夹，可直接选择当前文件夹';

  @override
  String get imageDirUnreadable => '读不到这个文件夹';

  @override
  String get chooseBackgroundImage => '选择背景图片';

  @override
  String get pastePathHint => '也可以直接粘贴路径，例如 D:\\pics\\stage.png';

  @override
  String get imagePathNote => '只存本机绝对路径，不复制文件、不进曲库索引。';

  @override
  String get useThisPath => '用这个路径';

  @override
  String imageDirError(String error) {
    return '$error —— 换个文件夹，或在下面直接粘贴路径';
  }

  @override
  String get noImages => '这个文件夹下没有图片文件（png/jpg/jpeg/webp/bmp/gif）';

  @override
  String get mqttIntro => '把连接信息整段粘贴进来就行，Broker、端口、账号、密码会自动识别，不用逐项填写。';

  @override
  String get mqttIntroUnconfigured => '还没有设置 MQTT。把中继那边的连接信息整段粘贴进来，识别后立即连接。';

  @override
  String get mqttPasteHint => 'mqtt://账号:密码@地址:1883\n或：地址 / 端口 / 账号 / 密码 分多行粘贴';

  @override
  String get mqttApplying => '应用中…';

  @override
  String get mqttApply => '识别并应用';

  @override
  String get mqttClear => '清除本机设置';

  @override
  String get mqttActive => '当前生效';

  @override
  String get mqttNotConfiguredShort => '未设置';

  @override
  String get mqttAnonymous => '匿名';

  @override
  String mqttPasswordMasked(int length) {
    return '••••••（$length 位）';
  }

  @override
  String get mqttTopicPrefix => '主题前缀';

  @override
  String get mqttLocalOnly => '参数只保存在本机，密码不会写进日志。';

  @override
  String mqttApplied(String host, int port) {
    return '已识别并应用 $host:$port';
  }

  @override
  String applyFailed(String error) {
    return '应用失败：$error';
  }

  @override
  String get mqttCleared => '已清除本机设置';

  @override
  String clearFailed(String error) {
    return '清除失败：$error';
  }

  @override
  String get brokerAddress => 'Broker 地址';

  @override
  String get username => '账号';

  @override
  String get password => '密码';

  @override
  String get pasteEmpty => '先粘贴一段连接信息';

  @override
  String get pasteUnrecognized =>
      '没认出连接信息。可以粘贴 mqtt://账号:密码@地址:端口，或地址/端口/账号/密码多行。';

  @override
  String get pasteMissingHost => 'JSON 里缺少 host（Broker 地址）';

  @override
  String get pasteNoWebsocket => '暂不支持 ws/wss 地址，请换成 mqtt://地址:端口';

  @override
  String get pasteBadHost => 'Broker 地址格式不对';

  @override
  String get configHostRequired => 'Broker 地址不能为空';

  @override
  String get configPortRange => '端口需在 1–65535';

  @override
  String get configTopicPrefix => '主题前缀不能为空，且不能含 #、+、空格';

  @override
  String get configClientIdTooLong => 'Client ID 过长';

  @override
  String connectFailed(String error) {
    return '连接失败：$error';
  }

  @override
  String connectNotEstablished(String state) {
    return '连接未建立（$state）';
  }

  @override
  String get connectionClosed => '连接已断开';

  @override
  String publishFailed(String error) {
    return '发布失败：$error';
  }

  @override
  String get searchTimeout => '检索超时';

  @override
  String get permNoPermissionNeeded => '无需授权';

  @override
  String get permAllFiles => '已授权（所有文件访问）';

  @override
  String get permAudioOnly => '仅音频可读；读取 .lrc 与扫描文件夹还需「所有文件访问」';

  @override
  String get permNotGranted => '未授权：请在系统设置中允许访问存储空间';

  @override
  String folderMissing(String root) {
    return '文件夹不存在：$root';
  }

  @override
  String folderUnreadable(String message) {
    return '无法读取文件夹：$message';
  }

  @override
  String get unknownArtist => '未知歌手';

  @override
  String get lyricsEmpty => '歌词为空';

  @override
  String get noLyrics => '没有歌词';

  @override
  String get castNoLyrics => '暂无歌词';

  @override
  String get onlineLibrary => '在线曲库';

  @override
  String get localFolder => '本地目录';

  @override
  String get demoNoLyrics => '演示曲目没有歌词';

  @override
  String get unsupportedSearch => '该音源不支持检索';

  @override
  String get unsupportedPlay => '该音源不支持播放';

  @override
  String get unsupportedLyrics => '该音源不支持歌词';

  @override
  String get kugouSearchFailed => '酷狗搜索失败';

  @override
  String get kugouMissingHash => '酷狗曲目缺少 hash';

  @override
  String get kugouNoLyrics => '酷狗没有找到歌词';

  @override
  String get kugouMissingCredential => '酷狗歌词缺少凭证';

  @override
  String get kugouLyricsEmpty => '酷狗歌词为空';

  @override
  String get kuwoSearchFailed => '酷我搜索失败';

  @override
  String get kuwoNoLyrics => '酷我没有歌词';

  @override
  String get kuwoMissingId => '酷我曲目缺少 ID';

  @override
  String get miguSearchFailed => '咪咕搜索失败';

  @override
  String get miguNoLyricUrl => '咪咕曲目没有歌词地址';

  @override
  String get miguLyricsEmpty => '咪咕歌词为空';

  @override
  String get qqSearchFailed => 'QQ 音乐搜索失败';

  @override
  String get qqMissingMid => 'QQ 音乐曲目缺少 mid';

  @override
  String get qqNoLyrics => 'QQ 音乐没有歌词';

  @override
  String get neteaseMissingId => '网易云曲目缺少 ID';

  @override
  String get neteaseNoLyrics => '网易云没有歌词';

  @override
  String get lyricsDecodeFailed => '歌词内容解码失败';

  @override
  String get httpBadJson => '响应不是有效 JSON';

  @override
  String get httpRateLimited => '请求过速，请稍后再试';

  @override
  String httpUnavailable(int status) {
    return '服务暂时不可用（HTTP $status）';
  }

  @override
  String httpFailed(int status) {
    return '请求失败（HTTP $status）';
  }

  @override
  String get httpTimeout => '网络超时';

  @override
  String get httpError => '网络请求失败';

  @override
  String get networkUnavailable => '网络不可用';

  @override
  String jsHostFailed(String detail) {
    return 'JS 宿主初始化失败：$detail';
  }

  @override
  String scriptRunFailed(String detail) {
    return '脚本执行失败：$detail';
  }

  @override
  String get scriptNoInited => '脚本没有发送 inited 事件';

  @override
  String get scriptNoPlatforms => '脚本没有声明可用的音乐服务';

  @override
  String get sourceNotInitialized => '音源尚未初始化';

  @override
  String scriptCallFailed(String detail) {
    return '脚本调用失败：$detail';
  }

  @override
  String get scriptNoResult => '脚本没有返回结果';

  @override
  String get scriptError => '脚本返回错误';

  @override
  String get scriptBadUrl => '脚本返回的播放地址无效';

  @override
  String jsUnavailable(String error) {
    return 'JS 引擎不可用：$error';
  }

  @override
  String get runtimeDisposed => '运行时已释放';

  @override
  String get scriptBadJson => '脚本返回值不是有效 JSON';

  @override
  String get requestBadUrl => '请求地址无效';

  @override
  String get requestHttpOnly => '只支持 http(s) 请求';

  @override
  String get requestNoMultipart => '暂不支持 multipart 请求';

  @override
  String scriptTimeout(String what) {
    return '$what超时';
  }

  @override
  String get scriptInit => '脚本初始化';

  @override
  String get playbackResolve => '播放地址解析';

  @override
  String get trackNoPlatform => '曲目缺少在线来源标识';

  @override
  String resolveFailed(String error) {
    return '播放地址解析失败：$error';
  }

  @override
  String get resolveFailedShort => '播放地址解析失败';

  @override
  String get noImportedScripts => '尚未导入音源脚本';

  @override
  String get noUsableScripts => '没有可用的音源脚本';

  @override
  String sourceResolveFailed(String detail) {
    return '音源取链失败：$detail';
  }

  @override
  String lyricsFetchFailed(String error) {
    return '歌词获取失败：$error';
  }

  @override
  String get trackNoLyrics => '该曲目没有歌词';

  @override
  String get sourceUrlScheme => '音源地址需以 http(s):// 开头';

  @override
  String downloadFailed(int status) {
    return '下载失败（HTTP $status）';
  }

  @override
  String get sourceInvalid => '不是有效的音源脚本（缺少 @name 标头）';

  @override
  String get downloadTimeout => '下载超时';

  @override
  String get sourceUnavailable => '音源暂不可用';

  @override
  String get platformResolveUnsupported => '该音源不支持此曲目取链';

  @override
  String get sourceNotFound => '音源不存在';

  @override
  String get seatLocal => '本机';

  @override
  String get localTag => '本地';

  @override
  String scanFailed(String error) {
    return '扫描失败：$error';
  }

  @override
  String probeReady(int ms) {
    return '就绪 ${ms}ms';
  }

  @override
  String get probeNoResolve => ' · 无取链动作';

  @override
  String probeFailed(String error) {
    return '失败：$error';
  }

  @override
  String get probeNoOnlineSource => '未接入在线音源';

  @override
  String probeZero(int ms) {
    return '0 条 · ${ms}ms';
  }

  @override
  String probeTracks(int count, int ms, int resolveMs, String host) {
    return '$count 条 · ${ms}ms · 取链 ${resolveMs}ms ($host)';
  }

  @override
  String probeResolveFailed(int count, int ms, String error) {
    return '$count 条 · ${ms}ms · 取链失败：$error';
  }

  @override
  String get audioFormatUnsupported => '无法识别音频格式';

  @override
  String get audioOpenFailed => '无法打开音频文件';

  @override
  String skipResolveFailed(String title) {
    return '无法解析「$title」的播放地址，已跳过';
  }

  @override
  String playOpenFailed(String title, String error) {
    return '无法播放「$title」：$error';
  }

  @override
  String skipUnplayable(String title) {
    return '「$title」无法播放，已跳过';
  }

  @override
  String get castBgSolid => '纯黑';

  @override
  String get castBgGradient => '上下渐变';

  @override
  String get castBgCustom => '自定义色';

  @override
  String get castBgImage => '图片';

  @override
  String get castAlignLeft => '左对齐';

  @override
  String get castAlignCenter => '居中';

  @override
  String get castAlignRight => '右对齐';

  @override
  String get onlineSourcesTitle => '在线音源';

  @override
  String scriptCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个脚本',
    );
    return '$_temp0';
  }

  @override
  String get sourcesIntro => '改动即时生效，不需要另外保存。取链按下面的顺序逐个尝试。';

  @override
  String get sourcesEmpty => '还没有导入音源；在线取链需要至少一个音源脚本。';

  @override
  String get importHint => '粘贴音源脚本地址，例如 https://.../source.js';

  @override
  String get importing => '导入中…';

  @override
  String get importAction => '导入';

  @override
  String importedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已导入并启用 · 共 $count 个脚本',
    );
    return '$_temp0';
  }

  @override
  String importFailedOnline(String error) {
    return '导入失败：$error';
  }

  @override
  String saveFailed(String error) {
    return '保存失败：$error';
  }

  @override
  String get needSourceUrl => '请先填写音源地址';

  @override
  String get sourceEnabled => '已启用';

  @override
  String get sourceDisabled => '已停用';

  @override
  String get sourceOrderUpdated => '取链顺序已更新';

  @override
  String get sourceRemoved => '已删除该音源';

  @override
  String get qualityLabel => '音质';

  @override
  String get qualitySaved => '音质已保存';

  @override
  String get restoreDefaults => '恢复默认音质';

  @override
  String get defaultsRestored => '音质已恢复默认';

  @override
  String statusError(String error) {
    return '错误：$error';
  }

  @override
  String get moveUp => '上移';

  @override
  String get moveDown => '下移';

  @override
  String get testSourceTooltip => '测试：脚本 + 检索 + 取链';

  @override
  String get checkSourceUpdate => '检查更新';

  @override
  String get sourceUpToDate => '已是最新版本';

  @override
  String sourceUpdateFound(String latest, String current) {
    return '发现新版 $latest · 当前 $current';
  }

  @override
  String get sourceUpdateApply => '更新';

  @override
  String get sourceUpdateDismiss => '忽略';

  @override
  String sourceUpdated(String version) {
    return '已更新到 $version';
  }

  @override
  String get sourceUpdatedPlain => '音源已更新';

  @override
  String sourceNotice(String message) {
    return '音源提示：$message';
  }

  @override
  String sourceNoticeLink(String url) {
    return '更新地址：$url';
  }

  @override
  String updateCheckFailed(String error) {
    return '检查更新失败：$error';
  }

  @override
  String get castTitle => '屏幕管理';

  @override
  String castSummary(int monitors, int windows) {
    return '$monitors 台屏幕 · $windows 个投放窗';
  }

  @override
  String get castIntro =>
      '每台勾选的屏幕开一扇置顶穿透窗；样式和时钟只有一份，所以画面天然同步，改动即时生效。投放中在投放屏幕上按右键，可关掉本屏幕或全部投放。';

  @override
  String get castNoMonitors =>
      '没扫到屏幕（screen_retriever 不可用或只有一块屏幕时也可能为空）。插好屏幕后重新扫描。';

  @override
  String get castNoMonitorsFound => '还是没扫到屏幕';

  @override
  String get castDetected => '检测到';

  @override
  String castDetectedValue(int count) {
    return '$count 台';
  }

  @override
  String get castCasting => '投放';

  @override
  String castCastingValue(int count) {
    return '$count 个窗口';
  }

  @override
  String get castOpen => '已开';

  @override
  String castOpenValue(int count) {
    return '$count 扇';
  }

  @override
  String get castMemory => '额外内存';

  @override
  String get castSync => '同步';

  @override
  String get castSyncValue => '一块画布 · 同帧呈现';

  @override
  String get castEnable => '启用投放';

  @override
  String castEnabledHint(int count) {
    return '已开 $count 扇投放窗，鼠标点得穿，结束程序时自动收起。';
  }

  @override
  String get castDisabledHint => '关掉时只有这里的预览，勾选的屏幕上不会开窗。';

  @override
  String get castTargetsTitle => '投放目标';

  @override
  String get castMultiSelect => '可多选';

  @override
  String get castTargetsHint => '只有勾选的屏幕才会出现在下面的地图和预览里。';

  @override
  String castMonitorLabel(int index, String name) {
    return '$index 号 · $name';
  }

  @override
  String castMonitorSpec(
    int fullW,
    int fullH,
    int workW,
    int workH,
    int scale,
  ) {
    return '整屏 $fullW×$fullH · 工作区 $workW×$workH · 缩放 $scale%';
  }

  @override
  String get castFullscreen => '全屏';

  @override
  String get castRegion => '区域';

  @override
  String get castEditing => '编辑中';

  @override
  String get castEditScreen => '编辑这块屏幕';

  @override
  String get castRegionTitle => '区域框选';

  @override
  String get castNoSelection => '还没勾选任何屏幕 —— 在上面勾一台，这里就只出现被选中的屏幕。';

  @override
  String get castPresetBottomStrip => '底部字幕条';

  @override
  String get castPresetLowerHalf => '下半屏';

  @override
  String get castPresetCenterStrip => '居中窄条';

  @override
  String get castMapHint => '在地图上直接拖：框内移动、八向把手缩放、空白处重新框选。';

  @override
  String get castMoveLeft => '左移';

  @override
  String get castMoveUp => '上移';

  @override
  String get castMoveDown => '下移';

  @override
  String get castMoveRight => '右移';

  @override
  String get castCenterH => '水平居中';

  @override
  String get castCenterV => '垂直居中';

  @override
  String get castLeftPx => '左 (px)';

  @override
  String get castTopPx => '上 (px)';

  @override
  String get castWidthPx => '宽 (px)';

  @override
  String get castHeightPx => '高 (px)';

  @override
  String castPercentSummary(
    String left,
    String top,
    String width,
    String height,
    int workW,
    int workH,
  ) {
    return '存成百分比 $left/$top · $width×$height · 该屏幕工作区 $workW×$workH 逻辑 px';
  }

  @override
  String get castStyleTitle => '歌词样式';

  @override
  String get castLines => '显示行数';

  @override
  String get castLinesCurrent => '仅当前句';

  @override
  String get castLinesPrev => '上一句 + 当前';

  @override
  String get castLinesBoth => '上句 + 当前 + 下句';

  @override
  String get castFont => '字体';

  @override
  String get castFontSize => '字号';

  @override
  String get castFontSizeUnit => 'px（按 1080 高折算）';

  @override
  String get castLineGap => '行间距';

  @override
  String get castTextWidth => '文字宽度';

  @override
  String get castTextHeight => '文字高度';

  @override
  String get castWeight => '字重';

  @override
  String get castWeightRegular => '400 一般';

  @override
  String get castWeightMedium => '500 中等';

  @override
  String get castWeightSemibold => '600 半粗';

  @override
  String get castWeightBold => '700 粗体';

  @override
  String get castStroke => '描边';

  @override
  String get castStrokeUnit => 'px（黑色描边，压住背景图和视频）';

  @override
  String get castShadow => '阴影';

  @override
  String get castCurrentColor => '当前歌词颜色';

  @override
  String get castOtherColor => '非当前歌词颜色';

  @override
  String get castOtherOpacity => '非当前歌词行透明度';

  @override
  String get castKaraokeColorHint => '逐字歌词：已唱的字用当前歌词颜色，未唱的字用非当前歌词颜色。';

  @override
  String get castBackground => '投放背景';

  @override
  String get castGradientTop => '渐变上';

  @override
  String get castGradientBottom => '渐变下';

  @override
  String get castSolidColor => '背景色';

  @override
  String get castNoImage => '还没选图片';

  @override
  String get castBrowse => '浏览…';

  @override
  String get castClear => '清除';

  @override
  String get castImageFit => '画面铺法';

  @override
  String get castFitCover => '铺满裁边';

  @override
  String get castFitContain => '完整显示';

  @override
  String get castAlign => '水平对齐';

  @override
  String get castVertical => '垂直位置';

  @override
  String get castVerticalUnit => '%（0=贴顶，歌词块中心）';

  @override
  String get castOffset => '歌词偏移';

  @override
  String get castOffsetUnit => 'ms（正值往后推）';

  @override
  String get castExtras => '附加信息';

  @override
  String get castShowTitle => '歌名';

  @override
  String get castShowArtist => '歌手';

  @override
  String get castShowSeat => '座位号';

  @override
  String get castPreview => '预览';

  @override
  String get castLiveBadge => '跟随本机播放';

  @override
  String get castDemoBadge => '演示走词';

  @override
  String get castPause => '暂停';

  @override
  String get castPlay => '播放';

  @override
  String get castPickScreen => '勾一台屏幕就能在这里看到实际画面。';

  @override
  String get castPreviewLiveHint => '预览按这台屏幕的投放区比例绘制，投放窗用的是同一套绘制。';

  @override
  String get castPreviewDemoHint => '没在播歌，用演示词走一遍；开始播放后这里会自动变成真实歌词。';

  @override
  String get castPickColor => '选颜色';

  @override
  String get castColorHint => '#RRGGBB 或 #AARRGGBB；A 是文字自身的透明度。';

  @override
  String get castDemoTitle => '晚风不歇';

  @override
  String get castDemoArtist => 'demo 歌手';

  @override
  String get castFontYaHei => '微软雅黑';

  @override
  String get castFontHei => '黑体';

  @override
  String get castFontSong => '宋体';

  @override
  String get castFontKai => '楷体';

  @override
  String get castFontDeng => '等线';

  @override
  String fileMissing(String path) {
    return '文件不存在：$path';
  }

  @override
  String castWindowTitle(String name) {
    return 'eNode 歌词投放 · $name';
  }

  @override
  String get castRuntimeMissing => 'Chromium 运行环境起不来';

  @override
  String get castRegionZero => '投放区尺寸为 0';

  @override
  String get castNoBrowserHandle => '画布浏览器没有返回句柄';

  @override
  String get castNoPresenter => '画布没有可显示的 presenter（需要 GPU 加速）';

  @override
  String castCanvasFallback(String error) {
    return '画布投放起不来，退回一屏一窗：$error';
  }

  @override
  String castWindowTimeout(String name) {
    return '$name 的投放窗 12 秒没起来——多引擎可能被显卡驱动或安全软件拦了';
  }

  @override
  String castWindowCreateFailed(String name, String error) {
    return '$name 的投放窗建不起来：$error';
  }

  @override
  String castWebFallback(String reason) {
    return '网页投放退回自绘：$reason';
  }

  @override
  String castWindowGone(String name, String error) {
    return '$name 的投放窗已经不在了，改一下投放设置会重新开：$error';
  }

  @override
  String castPageLoadFailed(int code, String detail) {
    return '投放页面加载失败（$code）$detail';
  }

  @override
  String castPushFailed(String error) {
    return '推送画面失败：$error';
  }

  @override
  String castWebError(String error) {
    return '网页投放异常：$error';
  }

  @override
  String get castModeFull => '整屏';

  @override
  String screenSummary(int monitors, int materials, int placements) {
    return '$monitors 台屏幕 · $materials 个素材 · $placements 个投放';
  }

  @override
  String get screenLiveSync => '投放同步中';

  @override
  String get screenEditOnly => '仅编辑，未投放';

  @override
  String screenCastingValue(int enabled, int total) {
    return '$enabled/$total 投屏';
  }

  @override
  String get screenScreens => '屏幕';

  @override
  String screenCount(int count) {
    return '$count 台';
  }

  @override
  String get screenScreenHint => '点选一台屏幕开始排版';

  @override
  String screenLayersCount(int count) {
    return '$count 个图层';
  }

  @override
  String screenUrlBadge(int count) {
    return '网页 $count';
  }

  @override
  String screenVideoBadge(int count) {
    return '影片 $count';
  }

  @override
  String get screenLoadLight => '轻';

  @override
  String get screenLoadMid => '中';

  @override
  String get screenLoadHeavy => '重';

  @override
  String get screenStatus => '状态';

  @override
  String get screenCastingScreens => '投屏';

  @override
  String get screenSharedCanvas => '共用画布';

  @override
  String get screenMaterials => '素材';

  @override
  String screenMaterialsValue(int count) {
    return '$count 个';
  }

  @override
  String get screenStatusHintOn => '投放窗由一块画布驱动，改样式会即时同步。';

  @override
  String get screenStatusHintOff => '未勾选任何屏幕时，画布只做编辑预览。';

  @override
  String get screenDetect => '检测';

  @override
  String screenRescanHint(int count) {
    return '目前 $count 台。插拔屏幕或改分辨率后重扫。';
  }

  @override
  String get screenAddMaterial => '新增素材';

  @override
  String screenToolbarCounts(int layers, int urls, int videos) {
    return '$layers 层 · 网页 $urls · 影片 $videos';
  }

  @override
  String get screenCastingBadge => '投放中';

  @override
  String get screenNotCasting => '未投放';

  @override
  String screenPerfWarning(int urls, int videos) {
    return '这一屏有 $urls 个网页、$videos 支影片。每一路都会多一份解码与合成开销，建议同屏各留一个。';
  }

  @override
  String get screenNoSelection => '选中画面上的素材调整位置 · 拖角缩放';

  @override
  String screenSelectionInfo(String name, int x, int y, int w, int h) {
    return '$name · $x, $y · $w×$h px';
  }

  @override
  String get screenShelf => '素材库';

  @override
  String get screenShelfHint => '拖到画面或点一下放上这屏';

  @override
  String get screenShelfMore => '同一素材放到多屏只保留一份样式；位置、层级与本屏声音各自独立。';

  @override
  String screenShelfCount(int count) {
    return '$count 个';
  }

  @override
  String get screenUsageShared => '共用';

  @override
  String get screenUsageHere => '本屏';

  @override
  String get screenUsageOther => '他屏';

  @override
  String get screenUsageNone => '未用';

  @override
  String screenUsageScreens(int count) {
    return '$count 屏使用';
  }

  @override
  String get screenUsageSingle => '独立素材';

  @override
  String get screenLayers => '图层';

  @override
  String get screenLayersHint => '拖动排序 · 上层在前';

  @override
  String get screenLayersEmpty => '这一屏还没有图层。从素材库加入，或按“新增素材”。';

  @override
  String get screenShow => '显示';

  @override
  String get screenHide => '隐藏';

  @override
  String get screenLock => '锁定';

  @override
  String get screenUnlock => '解锁';

  @override
  String get screenSound => '声音';

  @override
  String get screenBackToScreen => '屏幕设置';

  @override
  String get screenMaterialName => '素材名称';

  @override
  String get screenDuplicate => '复制为独立素材';

  @override
  String get screenDeleteLayer => '删除图层';

  @override
  String get screenAddLayer => '新增图层';

  @override
  String get screenDeleteMaterial => '删除素材';

  @override
  String get screenSectionLyric => '歌词';

  @override
  String get screenFollowNow => '跟随当前播放';

  @override
  String get screenOverlayAbove => '叠在歌词上方';

  @override
  String screenLineCount(int count) {
    return '$count 行';
  }

  @override
  String get screenTimeOffset => '时间偏移';

  @override
  String get screenLyricNoBgNote => '歌词不带底色。要背景就把图片或影片拉到满版、锁定、放最底层。';

  @override
  String get screenSectionUrl => '网址';

  @override
  String get screenEmbedPage => '嵌入网页';

  @override
  String get screenUrlPlaceholder => 'https://…';

  @override
  String get screenUrlReloadHint => '改网址或按重新加载才会刷新。';

  @override
  String get screenReload => '重新加载';

  @override
  String get screenRefresh => '刷新间隔';

  @override
  String get screenSeconds => '秒';

  @override
  String get screenUrlEmbedNote =>
      '对方网站若禁止嵌入（X-Frame-Options / CSP），画面会空白；可改用图片或影片素材。';

  @override
  String get screenUrlPreviewHint => '投放时在这里显示网页';

  @override
  String get screenScreenSound => '本屏声音';

  @override
  String get screenVolume => '音量';

  @override
  String get screenSource => '来源';

  @override
  String get screenStaticContent => '静态内容';

  @override
  String get screenSectionImage => '图片';

  @override
  String get screenSectionVideo => '影片';

  @override
  String get screenSectionText => '文字';

  @override
  String get screenSectionSound => '本屏播放';

  @override
  String get screenLocalFile => '本机文件';

  @override
  String get screenUrlSource => '图片网址';

  @override
  String get screenImageUrl => '图片网址';

  @override
  String get screenVideoUrl => '影片网址';

  @override
  String get screenFilePath => '文件路径';

  @override
  String get screenImageUrlPlaceholder => 'https://…/photo.jpg';

  @override
  String get screenImagePathPlaceholder => '选择本机图片…';

  @override
  String get screenVideoUrlPlaceholder => 'https://…/clip.mp4';

  @override
  String get screenVideoPathPlaceholder => '选择本机影片…';

  @override
  String get screenFill => '填充';

  @override
  String get screenFitStretch => '拉伸';

  @override
  String get screenRadius => '圆角';

  @override
  String get screenLoop => '循环播放';

  @override
  String get screenPlayOnce => '单次';

  @override
  String get screenAutoplay => '自动播放';

  @override
  String get screenMuted => '静音';

  @override
  String get screenMuteOthersNote => '同一屏只保留一路有声；开启时其他素材会自动静音。';

  @override
  String get screenImageBgNote => '全屏背景照样用图片做：拉到满版、放到最底层、锁定图层即可。';

  @override
  String get screenTextPlaceholder => '输入文字…';

  @override
  String get screenTextNote => '文字本身没有背景；需要底色或压暗时，在下面加一个图片或影片图层。';

  @override
  String get screenColor => '颜色';

  @override
  String get screenGeometry => '位置与层级';

  @override
  String get screenOpacity => '不透明度';

  @override
  String get screenZOrder => '层级';

  @override
  String get screenZTop => '置顶';

  @override
  String get screenZUp => '上移一层';

  @override
  String get screenZDown => '下移一层';

  @override
  String get screenZBottom => '置底';

  @override
  String get screenShownOn => '显示于';

  @override
  String get screenLockLayer => '锁定图层';

  @override
  String get screenSharedNote => '样式与内容同步到共用此素材的屏幕；位置、透明度、层级与本屏声音各自独立。';

  @override
  String get screenCanvasColor => '画布底色';

  @override
  String get screenTransparent => '透明';

  @override
  String get screenBlack => '纯黑';

  @override
  String get screenMidnight => '午夜';

  @override
  String get screenLightCanvas => '浅色';

  @override
  String get screenCustomColor => '自定义颜色';

  @override
  String get screenCanvasNote => '透明会让桌面透出来；选颜色则铺一层不透明底色。';

  @override
  String get screenCast => '投放';

  @override
  String get screenCastThisScreen => '投放这块屏幕';

  @override
  String get screenCoverage => '覆盖范围';

  @override
  String get screenFull => '整屏';

  @override
  String get screenWork => '工作区';

  @override
  String get screenPerformance => '性能';

  @override
  String get screenPerfLayers => '图层';

  @override
  String get screenPerfUrls => '网页';

  @override
  String get screenPerfVideos => '影片';

  @override
  String get screenPerfAudio => '有声';

  @override
  String get screenPerfHint => '网页与影片每多一路，CPU/GPU 与内存都会明显上升；同屏各留一个最稳。';

  @override
  String get screenTips => '小提示';

  @override
  String get screenTipsText =>
      '拖动素材移动、拖八个角缩放；方向键微调（Shift ×10），Delete 删除，Esc 取消选中。';

  @override
  String get screenSoundFollowsScreen => '声音跟屏走';

  @override
  String get screenEmptyMaterial => '还没设置内容';

  @override
  String get screenPickImage => '选择图片';

  @override
  String get screenPickVideo => '选择影片';

  @override
  String get screenNoVideos => '这个文件夹下没有影片文件（mp4/webm/mov/mkv/avi/m4v/ogv）';

  @override
  String get screenTagLight => '轻量';

  @override
  String get screenTagNormal => '普通';

  @override
  String get screenTagHeavy => '较重';

  @override
  String get screenTypeLyric => '歌词';

  @override
  String get screenTypeLyricDesc => '跟随播放的即时歌词';

  @override
  String get screenTypeUrl => '网址';

  @override
  String get screenTypeUrlDesc => '嵌入一个网页';

  @override
  String get screenTypeImage => '图片';

  @override
  String get screenTypeImageDesc => '本机文件或图片网址';

  @override
  String get screenTypeVideo => '影片';

  @override
  String get screenTypeVideoDesc => '本机或网络影片，可带声音';

  @override
  String get screenTypeText => '文字';

  @override
  String get screenTypeTextDesc => '静态文字';

  @override
  String get sourcesTitle => '音源';

  @override
  String sourcesTotal(int count) {
    return '曲库共 $count 首';
  }

  @override
  String sourcesSummary(int local, int webdav) {
    return '本地 $local 首 · WebDAV $webdav 首';
  }

  @override
  String get manageSources => '管理';

  @override
  String get localSourceTitle => '本地音源';

  @override
  String get webdavSourceTitle => 'WebDAV 音源';

  @override
  String webdavCount(int count) {
    return '$count 个';
  }

  @override
  String get webdavEmptyTitle => '还没有 WebDAV 音源';

  @override
  String get webdavEmptyHint => '连接 NAS 或任意 WebDAV 服务，扫描后与本地曲库一起参与点歌';

  @override
  String get webdavAdd => '新增';

  @override
  String get webdavAddTitle => '新增 WebDAV 音源';

  @override
  String get webdavEditTitle => '编辑 WebDAV 音源';

  @override
  String get webdavName => '名称';

  @override
  String get webdavUrl => '服务器地址';

  @override
  String get webdavUsername => '用户名';

  @override
  String get webdavPassword => '密码';

  @override
  String get webdavAllowSelfSigned => '允许自签名证书（NAS 常用）';

  @override
  String get webdavDialogHint => '连接信息只保存在本机；扫描后可像本地曲库一样检索、点歌和投放。';

  @override
  String get webdavTest => '测试连接';

  @override
  String get webdavSaveAndScan => '保存并扫描';

  @override
  String get webdavSync => '同步';

  @override
  String get webdavSyncing => '同步中…';

  @override
  String get webdavNeverSynced => '尚未同步';

  @override
  String get webdavEdit => '编辑';

  @override
  String get webdavDelete => '删除';

  @override
  String get webdavMore => '更多';

  @override
  String webdavDeleteConfirm(String name) {
    return '删除「$name」？';
  }

  @override
  String get webdavInvalidUrl => '服务器地址需以 http(s):// 开头';

  @override
  String get webdavNeedUrl => '请先填写服务器地址';

  @override
  String get webdavNeedName => '请先填写名称';

  @override
  String webdavTestOk(int count) {
    return '连接正常，根目录有 $count 个项目';
  }

  @override
  String webdavTestFailed(String error) {
    return '连接失败：$error';
  }

  @override
  String webdavAuthFailed(int status) {
    return '认证失败（HTTP $status）';
  }

  @override
  String webdavHttpError(int status) {
    return '服务器回应 HTTP $status';
  }

  @override
  String webdavConnectFailed(String detail) {
    return '连接失败：$detail';
  }

  @override
  String webdavTlsFailed(String detail) {
    return '证书校验失败，可允许自签名证书：$detail';
  }

  @override
  String get webdavTimeout => '连接超时';

  @override
  String get webdavInvalidXml => '无法解析 WebDAV 回应';

  @override
  String get webdavNotDav => '这个地址不是 WebDAV 服务';

  @override
  String get webdavNotFound => '远程文件夹不存在';

  @override
  String webdavPartialFolders(int count) {
    return '$count 个文件夹读取失败，已同步其余曲目';
  }

  @override
  String webdavFileUnavailable(String name) {
    return '远程文件不可用：$name';
  }

  @override
  String webdavSyncedAt(String time) {
    return '同步于 $time';
  }

  @override
  String webdavLastScanned(String time) {
    return '上次扫描 $time';
  }

  @override
  String webdavSyncProgress(int tracks, int folders) {
    return '已发现 $tracks 首 · $folders 个文件夹';
  }

  @override
  String get webdavTesting => '测试中…';

  @override
  String get webdavSaving => '保存中…';
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppL10nZhHant extends AppL10nZh {
  AppL10nZhHant() : super('zh_Hant');

  @override
  String get settingsTitle => '設定';

  @override
  String get done => '完成';

  @override
  String get close => '關閉';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '確認';

  @override
  String get delete => '刪除';

  @override
  String get notSet => '未設定';

  @override
  String get notAssigned => '未分配';

  @override
  String get tabDisplay => '顯示';

  @override
  String get tabBroadcast => '廣播';

  @override
  String get tabSources => '音源';

  @override
  String get tabCast => '螢幕管理';

  @override
  String get tabAbout => '關於';

  @override
  String get theme => '主題';

  @override
  String get themeDark => '暗色';

  @override
  String get themeLight => '亮色';

  @override
  String get themeSystem => '跟隨系統';

  @override
  String get themeSystemHint => '「跟隨系統」會隨裝置的深色模式自動切換。';

  @override
  String get textSize => '字型大小';

  @override
  String get textSizeSmall => '小';

  @override
  String get textSizeMedium => '中';

  @override
  String get textSizeLarge => '大';

  @override
  String get textSizeXLarge => '特大';

  @override
  String get displayPrefsHint => '顯示偏好保存在本機，重啟後保持。';

  @override
  String get language => '語言';

  @override
  String get languageSystem => '跟隨系統';

  @override
  String get languageSimplifiedChinese => '简体中文';

  @override
  String get languageTraditionalChinese => '繁體中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageHint => '簡體中文系統顯示簡體中文，繁體中文系統顯示繁體中文；其他語言顯示英文。';

  @override
  String get aboutVersionNode => '版本與節點';

  @override
  String get aboutVersion => '版本';

  @override
  String get aboutNodeId => '節點 ID';

  @override
  String get aboutConnection => '連線狀態';

  @override
  String get aboutLibraryDir => '曲庫資料夾';

  @override
  String get aboutLogDir => '偵錯日誌';

  @override
  String get aboutOpenLog => '開啟日誌資料夾';

  @override
  String get aboutOpenSource => '開源授權';

  @override
  String get aboutLicense => '授權條款';

  @override
  String get aboutViewLicenses => '查看授權與第三方元件';

  @override
  String get aboutOpenSourceHint =>
      '本程式以 AGPL-3.0 授權。第三方元件包含 CEF（BSD-3）、libmpv／FFmpeg（LGPL-2.1-or-later），完整清單見授權頁。';

  @override
  String get aboutSourceCode => '原始碼';

  @override
  String get aboutSourceCopied => '原始碼位址已複製';

  @override
  String get aboutUpdate => '應用程式更新';

  @override
  String get aboutUpdateIdle => '未檢查';

  @override
  String get aboutCheckUpdate => '檢查更新';

  @override
  String get aboutCheckingUpdate => '正在檢查…';

  @override
  String get aboutUpToDate => '已是最新版本';

  @override
  String get aboutNoRelease => '暫無發佈版本';

  @override
  String aboutNewVersion(String version) {
    return '有新版本 $version';
  }

  @override
  String get aboutDownloadUpdate => '下載新版本';

  @override
  String updateAvailableTitle(String version) {
    return '發現新版本 $version';
  }

  @override
  String updateAvailableBody(String current) {
    return '目前 $current，要下載新版本嗎？';
  }

  @override
  String get updateLater => '稍後';

  @override
  String get updateDownload => '前往下載';

  @override
  String get openLinkFailed => '無法開啟連結';

  @override
  String get settingsTooltip => '設定';

  @override
  String get trayOpen => '開啟 eNode';

  @override
  String get trayAutostart => '開機啟動';

  @override
  String get trayQuit => '退出';

  @override
  String get exitTitle => '要退出軟體嗎？';

  @override
  String get mqttNotConfigured => 'MQTT 未設定';

  @override
  String get mqttInvalidConfig => 'MQTT 參數有誤';

  @override
  String get mqttConnected => 'MQTT 已連線';

  @override
  String get mqttConnecting => 'MQTT 連線中';

  @override
  String get mqttFailed => 'MQTT 連線失敗';

  @override
  String get mqttDisconnected => 'MQTT 未連線';

  @override
  String get nowPlaying => '播放';

  @override
  String get queueEmpty => '隊列為空';

  @override
  String queuePosition(int total) {
    return '第 1 / $total';
  }

  @override
  String get addedHere => '本機新增';

  @override
  String fromGuest(String seat) {
    return 'C端 · $seat';
  }

  @override
  String timeLeft(String time) {
    return '剩 $time';
  }

  @override
  String get volume => '音量';

  @override
  String get queue => '隊列';

  @override
  String queueLimit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 首 / 上限 200',
    );
    return '$_temp0';
  }

  @override
  String moveToPosition(String title, int position) {
    return '把「$title」移到第 $position 位？';
  }

  @override
  String get playingNow => '播放中';

  @override
  String get paused => '已暫停';

  @override
  String get removeFromQueue => '移出隊列';

  @override
  String get library => '曲庫';

  @override
  String trackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 首',
    );
    return '$_temp0';
  }

  @override
  String missingCount(int count) {
    return '缺失 $count';
  }

  @override
  String scanProgress(int scanned, int total) {
    return '掃描中 $scanned / $total';
  }

  @override
  String get demoLibrary => '演示曲庫';

  @override
  String get libraryReady => '已就緒';

  @override
  String get noRealFolder => '未接真實資料夾';

  @override
  String get noFolder => '未設定資料夾';

  @override
  String get scanning => '掃描中…';

  @override
  String get scan => '掃描';

  @override
  String get rescan => '重新掃描';

  @override
  String get folder => '資料夾';

  @override
  String get changeFolder => '更改資料夾';

  @override
  String get grantAccess => '去授權';

  @override
  String get systemSettings => '系統設定';

  @override
  String get dirUnreadable => '無法讀取該資料夾，可能缺少儲存權限';

  @override
  String get chooseLibraryFolder => '選擇曲庫資料夾';

  @override
  String get parentFolder => '上一級';

  @override
  String get chooseFolderHint => '儲存後會立即重新掃描，子資料夾會被遞迴掃描。';

  @override
  String get chooseThisFolder => '選擇此資料夾';

  @override
  String get openStorageSettings => '去系統設定授權';

  @override
  String get noSubfolders => '這裡沒有子資料夾，可直接選擇目前資料夾';

  @override
  String get imageDirUnreadable => '讀不到這個資料夾';

  @override
  String get chooseBackgroundImage => '選擇背景圖片';

  @override
  String get pastePathHint => '也可以直接貼路徑，例如 D:\\pics\\stage.png';

  @override
  String get imagePathNote => '只存本機絕對路徑，不複製檔案、不進曲庫索引。';

  @override
  String get useThisPath => '用這個路徑';

  @override
  String imageDirError(String error) {
    return '$error —— 換個資料夾，或在下面直接貼路徑';
  }

  @override
  String get noImages => '這個資料夾下沒有圖片檔案（png/jpg/jpeg/webp/bmp/gif）';

  @override
  String get mqttIntro => '把連線資訊整段貼進來就行，Broker、連接埠、帳號、密碼會自動識別，不用逐項填寫。';

  @override
  String get mqttIntroUnconfigured => '還沒有設定 MQTT。把中繼那邊的連線資訊整段貼進來，識別後立即連線。';

  @override
  String get mqttPasteHint =>
      'mqtt://帳號:密碼@位址:1883\n或：位址 / 連接埠 / 帳號 / 密碼 分多行貼上';

  @override
  String get mqttApplying => '套用中…';

  @override
  String get mqttApply => '識別並套用';

  @override
  String get mqttClear => '清除本機設定';

  @override
  String get mqttActive => '目前生效';

  @override
  String get mqttNotConfiguredShort => '未設定';

  @override
  String get mqttAnonymous => '匿名';

  @override
  String mqttPasswordMasked(int length) {
    return '••••••（$length 位）';
  }

  @override
  String get mqttTopicPrefix => '主題前綴';

  @override
  String get mqttLocalOnly => '參數只保存在本機，密碼不會寫進日誌。';

  @override
  String mqttApplied(String host, int port) {
    return '已識別並套用 $host:$port';
  }

  @override
  String applyFailed(String error) {
    return '套用失敗：$error';
  }

  @override
  String get mqttCleared => '已清除本機設定';

  @override
  String clearFailed(String error) {
    return '清除失敗：$error';
  }

  @override
  String get brokerAddress => 'Broker 位址';

  @override
  String get username => '帳號';

  @override
  String get password => '密碼';

  @override
  String get pasteEmpty => '先貼上一段連線資訊';

  @override
  String get pasteUnrecognized =>
      '沒認出連線資訊。可以貼 mqtt://帳號:密碼@位址:連接埠，或位址/連接埠/帳號/密碼多行。';

  @override
  String get pasteMissingHost => 'JSON 裡缺少 host（Broker 位址）';

  @override
  String get pasteNoWebsocket => '暫不支援 ws/wss 位址，請換成 mqtt://位址:連接埠';

  @override
  String get pasteBadHost => 'Broker 位址格式不對';

  @override
  String get configHostRequired => 'Broker 位址不能為空';

  @override
  String get configPortRange => '連接埠需在 1–65535';

  @override
  String get configTopicPrefix => '主題前綴不能為空，且不能含 #、+、空格';

  @override
  String get configClientIdTooLong => 'Client ID 過長';

  @override
  String connectFailed(String error) {
    return '連線失敗：$error';
  }

  @override
  String connectNotEstablished(String state) {
    return '連線未建立（$state）';
  }

  @override
  String get connectionClosed => '連線已斷開';

  @override
  String publishFailed(String error) {
    return '發佈失敗：$error';
  }

  @override
  String get searchTimeout => '檢索逾時';

  @override
  String get permNoPermissionNeeded => '無需授權';

  @override
  String get permAllFiles => '已授權（所有檔案存取）';

  @override
  String get permAudioOnly => '僅音訊可讀；讀取 .lrc 與掃描資料夾還需「所有檔案存取」';

  @override
  String get permNotGranted => '未授權：請在系統設定中允許存取儲存空間';

  @override
  String folderMissing(String root) {
    return '資料夾不存在：$root';
  }

  @override
  String folderUnreadable(String message) {
    return '無法讀取資料夾：$message';
  }

  @override
  String get unknownArtist => '未知歌手';

  @override
  String get lyricsEmpty => '歌詞為空';

  @override
  String get noLyrics => '沒有歌詞';

  @override
  String get castNoLyrics => '暫無歌詞';

  @override
  String get onlineLibrary => '線上曲庫';

  @override
  String get localFolder => '本地目錄';

  @override
  String get demoNoLyrics => '演示曲目沒有歌詞';

  @override
  String get unsupportedSearch => '該音源不支援檢索';

  @override
  String get unsupportedPlay => '該音源不支援播放';

  @override
  String get unsupportedLyrics => '該音源不支援歌詞';

  @override
  String get kugouSearchFailed => '酷狗搜尋失敗';

  @override
  String get kugouMissingHash => '酷狗曲目缺少 hash';

  @override
  String get kugouNoLyrics => '酷狗沒有找到歌詞';

  @override
  String get kugouMissingCredential => '酷狗歌詞缺少憑證';

  @override
  String get kugouLyricsEmpty => '酷狗歌詞為空';

  @override
  String get kuwoSearchFailed => '酷我搜尋失敗';

  @override
  String get kuwoNoLyrics => '酷我沒有歌詞';

  @override
  String get kuwoMissingId => '酷我曲目缺少 ID';

  @override
  String get miguSearchFailed => '咪咕搜尋失敗';

  @override
  String get miguNoLyricUrl => '咪咕曲目沒有歌詞位址';

  @override
  String get miguLyricsEmpty => '咪咕歌詞為空';

  @override
  String get qqSearchFailed => 'QQ 音樂搜尋失敗';

  @override
  String get qqMissingMid => 'QQ 音樂曲目缺少 mid';

  @override
  String get qqNoLyrics => 'QQ 音樂沒有歌詞';

  @override
  String get neteaseMissingId => '網易雲曲目缺少 ID';

  @override
  String get neteaseNoLyrics => '網易雲沒有歌詞';

  @override
  String get lyricsDecodeFailed => '歌詞內容解碼失敗';

  @override
  String get httpBadJson => '回應不是有效 JSON';

  @override
  String get httpRateLimited => '請求過速，請稍後再試';

  @override
  String httpUnavailable(int status) {
    return '服務暫時不可用（HTTP $status）';
  }

  @override
  String httpFailed(int status) {
    return '請求失敗（HTTP $status）';
  }

  @override
  String get httpTimeout => '網路逾時';

  @override
  String get httpError => '網路請求失敗';

  @override
  String get networkUnavailable => '網路不可用';

  @override
  String jsHostFailed(String detail) {
    return 'JS 宿主初始化失敗：$detail';
  }

  @override
  String scriptRunFailed(String detail) {
    return '腳本執行失敗：$detail';
  }

  @override
  String get scriptNoInited => '腳本沒有發送 inited 事件';

  @override
  String get scriptNoPlatforms => '腳本沒有宣告可用的音樂服務';

  @override
  String get sourceNotInitialized => '音源尚未初始化';

  @override
  String scriptCallFailed(String detail) {
    return '腳本呼叫失敗：$detail';
  }

  @override
  String get scriptNoResult => '腳本沒有返回結果';

  @override
  String get scriptError => '腳本返回錯誤';

  @override
  String get scriptBadUrl => '腳本返回的播放位址無效';

  @override
  String jsUnavailable(String error) {
    return 'JS 引擎不可用：$error';
  }

  @override
  String get runtimeDisposed => '執行時已釋放';

  @override
  String get scriptBadJson => '腳本返回值不是有效 JSON';

  @override
  String get requestBadUrl => '請求位址無效';

  @override
  String get requestHttpOnly => '只支援 http(s) 請求';

  @override
  String get requestNoMultipart => '暫不支援 multipart 請求';

  @override
  String scriptTimeout(String what) {
    return '$what逾時';
  }

  @override
  String get scriptInit => '腳本初始化';

  @override
  String get playbackResolve => '播放位址解析';

  @override
  String get trackNoPlatform => '曲目缺少線上來源標識';

  @override
  String resolveFailed(String error) {
    return '播放位址解析失敗：$error';
  }

  @override
  String get resolveFailedShort => '播放位址解析失敗';

  @override
  String get noImportedScripts => '尚未匯入音源腳本';

  @override
  String get noUsableScripts => '沒有可用的音源腳本';

  @override
  String sourceResolveFailed(String detail) {
    return '音源取鏈失敗：$detail';
  }

  @override
  String lyricsFetchFailed(String error) {
    return '歌詞取得失敗：$error';
  }

  @override
  String get trackNoLyrics => '該曲目沒有歌詞';

  @override
  String get sourceUrlScheme => '音源位址需以 http(s):// 開頭';

  @override
  String downloadFailed(int status) {
    return '下載失敗（HTTP $status）';
  }

  @override
  String get sourceInvalid => '不是有效的音源腳本（缺少 @name 標頭）';

  @override
  String get downloadTimeout => '下載逾時';

  @override
  String get sourceUnavailable => '音源暫不可用';

  @override
  String get platformResolveUnsupported => '該音源不支援此曲目取鏈';

  @override
  String get sourceNotFound => '音源不存在';

  @override
  String get seatLocal => '本機';

  @override
  String get localTag => '本地';

  @override
  String scanFailed(String error) {
    return '掃描失敗：$error';
  }

  @override
  String probeReady(int ms) {
    return '就緒 ${ms}ms';
  }

  @override
  String get probeNoResolve => ' · 無取鏈動作';

  @override
  String probeFailed(String error) {
    return '失敗：$error';
  }

  @override
  String get probeNoOnlineSource => '未接入線上音源';

  @override
  String probeZero(int ms) {
    return '0 條 · ${ms}ms';
  }

  @override
  String probeTracks(int count, int ms, int resolveMs, String host) {
    return '$count 條 · ${ms}ms · 取鏈 ${resolveMs}ms ($host)';
  }

  @override
  String probeResolveFailed(int count, int ms, String error) {
    return '$count 條 · ${ms}ms · 取鏈失敗：$error';
  }

  @override
  String get audioFormatUnsupported => '無法識別音訊格式';

  @override
  String get audioOpenFailed => '無法開啟音訊檔案';

  @override
  String skipResolveFailed(String title) {
    return '無法解析「$title」的播放位址，已跳過';
  }

  @override
  String playOpenFailed(String title, String error) {
    return '無法播放「$title」：$error';
  }

  @override
  String skipUnplayable(String title) {
    return '「$title」無法播放，已跳過';
  }

  @override
  String get castBgSolid => '純黑';

  @override
  String get castBgGradient => '上下漸層';

  @override
  String get castBgCustom => '自訂色';

  @override
  String get castBgImage => '圖片';

  @override
  String get castAlignLeft => '左對齊';

  @override
  String get castAlignCenter => '居中';

  @override
  String get castAlignRight => '右對齊';

  @override
  String get onlineSourcesTitle => '線上音源';

  @override
  String scriptCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 個腳本',
    );
    return '$_temp0';
  }

  @override
  String get sourcesIntro => '改動即時生效，不需要另外儲存。取鏈按下面的順序逐個嘗試。';

  @override
  String get sourcesEmpty => '還沒有匯入音源；線上取鏈需要至少一個音源腳本。';

  @override
  String get importHint => '貼上音源腳本位址，例如 https://.../source.js';

  @override
  String get importing => '匯入中…';

  @override
  String get importAction => '匯入';

  @override
  String importedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已匯入並啟用 · 共 $count 個腳本',
    );
    return '$_temp0';
  }

  @override
  String importFailedOnline(String error) {
    return '匯入失敗：$error';
  }

  @override
  String saveFailed(String error) {
    return '儲存失敗：$error';
  }

  @override
  String get needSourceUrl => '請先填寫音源位址';

  @override
  String get sourceEnabled => '已啟用';

  @override
  String get sourceDisabled => '已停用';

  @override
  String get sourceOrderUpdated => '取鏈順序已更新';

  @override
  String get sourceRemoved => '已刪除該音源';

  @override
  String get qualityLabel => '音質';

  @override
  String get qualitySaved => '音質已儲存';

  @override
  String get restoreDefaults => '恢復預設音質';

  @override
  String get defaultsRestored => '音質已恢復預設';

  @override
  String statusError(String error) {
    return '錯誤：$error';
  }

  @override
  String get moveUp => '上移';

  @override
  String get moveDown => '下移';

  @override
  String get testSourceTooltip => '測試：腳本 + 檢索 + 取鏈';

  @override
  String get checkSourceUpdate => '檢查更新';

  @override
  String get sourceUpToDate => '已是最新版本';

  @override
  String sourceUpdateFound(String latest, String current) {
    return '發現新版 $latest · 目前 $current';
  }

  @override
  String get sourceUpdateApply => '更新';

  @override
  String get sourceUpdateDismiss => '忽略';

  @override
  String sourceUpdated(String version) {
    return '已更新至 $version';
  }

  @override
  String get sourceUpdatedPlain => '音源已更新';

  @override
  String sourceNotice(String message) {
    return '音源提示：$message';
  }

  @override
  String sourceNoticeLink(String url) {
    return '更新地址：$url';
  }

  @override
  String updateCheckFailed(String error) {
    return '檢查更新失敗：$error';
  }

  @override
  String get castTitle => '螢幕管理';

  @override
  String castSummary(int monitors, int windows) {
    return '$monitors 台螢幕 · $windows 個投放窗';
  }

  @override
  String get castIntro =>
      '每台勾選的螢幕開一扇置頂穿透窗；樣式和時鐘只有一份，所以畫面天然同步，改動即時生效。投放中在投放螢幕上按右鍵，可關掉本螢幕或全部投放。';

  @override
  String get castNoMonitors =>
      '沒掃到螢幕（screen_retriever 不可用或只有一塊螢幕時也可能為空）。插好螢幕後重新掃描。';

  @override
  String get castNoMonitorsFound => '還是沒掃到螢幕';

  @override
  String get castDetected => '偵測到';

  @override
  String castDetectedValue(int count) {
    return '$count 台';
  }

  @override
  String get castCasting => '投放';

  @override
  String castCastingValue(int count) {
    return '$count 個視窗';
  }

  @override
  String get castOpen => '已開';

  @override
  String castOpenValue(int count) {
    return '$count 扇';
  }

  @override
  String get castMemory => '額外記憶體';

  @override
  String get castSync => '同步';

  @override
  String get castSyncValue => '一塊畫布 · 同幀呈現';

  @override
  String get castEnable => '啟用投放';

  @override
  String castEnabledHint(int count) {
    return '已開 $count 扇投放窗，滑鼠點得穿，結束程式時自動收起。';
  }

  @override
  String get castDisabledHint => '關掉時只有這裡的預覽，勾選的螢幕上不會開窗。';

  @override
  String get castTargetsTitle => '投放目標';

  @override
  String get castMultiSelect => '可多選';

  @override
  String get castTargetsHint => '只有勾選的螢幕才出現在下面的地圖和預覽裡。';

  @override
  String castMonitorLabel(int index, String name) {
    return '$index 號 · $name';
  }

  @override
  String castMonitorSpec(
    int fullW,
    int fullH,
    int workW,
    int workH,
    int scale,
  ) {
    return '整屏 $fullW×$fullH · 工作區 $workW×$workH · 縮放 $scale%';
  }

  @override
  String get castFullscreen => '全屏';

  @override
  String get castRegion => '區域';

  @override
  String get castEditing => '編輯中';

  @override
  String get castEditScreen => '編輯這塊螢幕';

  @override
  String get castRegionTitle => '區域框選';

  @override
  String get castNoSelection => '還沒勾選任何螢幕 —— 在上面勾一台，這裡就只出現被選中的螢幕。';

  @override
  String get castPresetBottomStrip => '底部字幕條';

  @override
  String get castPresetLowerHalf => '下半屏';

  @override
  String get castPresetCenterStrip => '居中窄條';

  @override
  String get castMapHint => '在地圖上直接拖：框內移動、八向把手縮放、空白處重新框選。';

  @override
  String get castMoveLeft => '左移';

  @override
  String get castMoveUp => '上移';

  @override
  String get castMoveDown => '下移';

  @override
  String get castMoveRight => '右移';

  @override
  String get castCenterH => '水平居中';

  @override
  String get castCenterV => '垂直居中';

  @override
  String get castLeftPx => '左 (px)';

  @override
  String get castTopPx => '上 (px)';

  @override
  String get castWidthPx => '寬 (px)';

  @override
  String get castHeightPx => '高 (px)';

  @override
  String castPercentSummary(
    String left,
    String top,
    String width,
    String height,
    int workW,
    int workH,
  ) {
    return '存成百分比 $left/$top · $width×$height · 該螢幕工作區 $workW×$workH 邏輯 px';
  }

  @override
  String get castStyleTitle => '歌詞樣式';

  @override
  String get castLines => '顯示行數';

  @override
  String get castLinesCurrent => '僅目前句';

  @override
  String get castLinesPrev => '上一句 + 目前';

  @override
  String get castLinesBoth => '上句 + 目前 + 下句';

  @override
  String get castFont => '字型';

  @override
  String get castFontSize => '字號';

  @override
  String get castFontSizeUnit => 'px（按 1080 高折算）';

  @override
  String get castLineGap => '行間距';

  @override
  String get castTextWidth => '文字寬度';

  @override
  String get castTextHeight => '文字高度';

  @override
  String get castWeight => '字重';

  @override
  String get castWeightRegular => '400 一般';

  @override
  String get castWeightMedium => '500 中等';

  @override
  String get castWeightSemibold => '600 半粗';

  @override
  String get castWeightBold => '700 粗體';

  @override
  String get castStroke => '描邊';

  @override
  String get castStrokeUnit => 'px（黑色描邊，壓住背景圖和影片）';

  @override
  String get castShadow => '陰影';

  @override
  String get castCurrentColor => '目前歌詞顏色';

  @override
  String get castOtherColor => '非目前歌詞顏色';

  @override
  String get castOtherOpacity => '非目前歌詞行透明度';

  @override
  String get castKaraokeColorHint => '逐字歌詞：已唱的字用目前歌詞顏色，未唱的字用非目前歌詞顏色。';

  @override
  String get castBackground => '投放背景';

  @override
  String get castGradientTop => '漸層上';

  @override
  String get castGradientBottom => '漸層下';

  @override
  String get castSolidColor => '背景色';

  @override
  String get castNoImage => '還沒選圖片';

  @override
  String get castBrowse => '瀏覽…';

  @override
  String get castClear => '清除';

  @override
  String get castImageFit => '畫面鋪法';

  @override
  String get castFitCover => '鋪滿裁邊';

  @override
  String get castFitContain => '完整顯示';

  @override
  String get castAlign => '水平對齊';

  @override
  String get castVertical => '垂直位置';

  @override
  String get castVerticalUnit => '%（0=貼頂，歌詞塊中心）';

  @override
  String get castOffset => '歌詞偏移';

  @override
  String get castOffsetUnit => 'ms（正值往後推）';

  @override
  String get castExtras => '附加資訊';

  @override
  String get castShowTitle => '歌名';

  @override
  String get castShowArtist => '歌手';

  @override
  String get castShowSeat => '座位號';

  @override
  String get castPreview => '預覽';

  @override
  String get castLiveBadge => '跟隨本機播放';

  @override
  String get castDemoBadge => '演示走詞';

  @override
  String get castPause => '暫停';

  @override
  String get castPlay => '播放';

  @override
  String get castPickScreen => '勾一台螢幕就能在這裡看到實際畫面。';

  @override
  String get castPreviewLiveHint => '預覽按這台螢幕的投放區比例繪製，投放窗用的是同一套繪製。';

  @override
  String get castPreviewDemoHint => '沒在播歌，用演示詞走一遍；開始播放後這裡會自動變成真實歌詞。';

  @override
  String get castPickColor => '選顏色';

  @override
  String get castColorHint => '#RRGGBB 或 #AARRGGBB；A 是文字自身的透明度。';

  @override
  String get castDemoTitle => '晚風不歇';

  @override
  String get castDemoArtist => 'demo 歌手';

  @override
  String get castFontYaHei => '微軟雅黑';

  @override
  String get castFontHei => '黑體';

  @override
  String get castFontSong => '宋體';

  @override
  String get castFontKai => '楷體';

  @override
  String get castFontDeng => '等線';

  @override
  String fileMissing(String path) {
    return '檔案不存在：$path';
  }

  @override
  String castWindowTitle(String name) {
    return 'eNode 歌詞投放 · $name';
  }

  @override
  String get castRuntimeMissing => 'Chromium 執行環境起不來';

  @override
  String get castRegionZero => '投放區尺寸為 0';

  @override
  String get castNoBrowserHandle => '畫布瀏覽器沒有回傳控制代碼';

  @override
  String get castNoPresenter => '畫布沒有可顯示的 presenter（需要 GPU 加速）';

  @override
  String castCanvasFallback(String error) {
    return '畫布投放起不來，退回一屏一窗：$error';
  }

  @override
  String castWindowTimeout(String name) {
    return '$name 的投放窗 12 秒沒起來——多引擎可能被顯卡驅動或安全軟體攔了';
  }

  @override
  String castWindowCreateFailed(String name, String error) {
    return '$name 的投放窗建不起來：$error';
  }

  @override
  String castWebFallback(String reason) {
    return '網頁投放退回自繪：$reason';
  }

  @override
  String castWindowGone(String name, String error) {
    return '$name 的投放窗已經不在了，改一下投放設定會重新開：$error';
  }

  @override
  String castPageLoadFailed(int code, String detail) {
    return '投放頁面載入失敗（$code）$detail';
  }

  @override
  String castPushFailed(String error) {
    return '推送畫面失敗：$error';
  }

  @override
  String castWebError(String error) {
    return '網頁投放異常：$error';
  }

  @override
  String get castModeFull => '整屏';

  @override
  String screenSummary(int monitors, int materials, int placements) {
    return '$monitors 台螢幕 · $materials 個素材 · $placements 個投放';
  }

  @override
  String get screenLiveSync => '投放同步中';

  @override
  String get screenEditOnly => '僅編輯，未投放';

  @override
  String screenCastingValue(int enabled, int total) {
    return '$enabled/$total 投屏';
  }

  @override
  String get screenScreens => '螢幕';

  @override
  String screenCount(int count) {
    return '$count 台';
  }

  @override
  String get screenScreenHint => '點選一台螢幕開始排版';

  @override
  String screenLayersCount(int count) {
    return '$count 個圖層';
  }

  @override
  String screenUrlBadge(int count) {
    return '網頁 $count';
  }

  @override
  String screenVideoBadge(int count) {
    return '影片 $count';
  }

  @override
  String get screenLoadLight => '輕';

  @override
  String get screenLoadMid => '中';

  @override
  String get screenLoadHeavy => '重';

  @override
  String get screenStatus => '狀態';

  @override
  String get screenCastingScreens => '投屏';

  @override
  String get screenSharedCanvas => '共用畫布';

  @override
  String get screenMaterials => '素材';

  @override
  String screenMaterialsValue(int count) {
    return '$count 個';
  }

  @override
  String get screenStatusHintOn => '投放窗由一塊畫布驅動，改樣式會即時同步。';

  @override
  String get screenStatusHintOff => '未勾選任何螢幕時，畫布只做編輯預覽。';

  @override
  String get screenDetect => '偵測';

  @override
  String screenRescanHint(int count) {
    return '目前 $count 台。插拔螢幕或改解析度後重掃。';
  }

  @override
  String get screenAddMaterial => '新增素材';

  @override
  String screenToolbarCounts(int layers, int urls, int videos) {
    return '$layers 層 · 網頁 $urls · 影片 $videos';
  }

  @override
  String get screenCastingBadge => '投放中';

  @override
  String get screenNotCasting => '未投放';

  @override
  String screenPerfWarning(int urls, int videos) {
    return '這一屏有 $urls 個網頁、$videos 支影片。每一路都會多一份解碼與合成開銷，建議同屏各留一個。';
  }

  @override
  String get screenNoSelection => '選中畫面上的素材調整位置 · 拖角縮放';

  @override
  String screenSelectionInfo(String name, int x, int y, int w, int h) {
    return '$name · $x, $y · $w×$h px';
  }

  @override
  String get screenShelf => '素材庫';

  @override
  String get screenShelfHint => '拖到畫面或點一下放上這屏';

  @override
  String get screenShelfMore => '同一素材放到多屏只保留一份樣式；位置、層級與本屏聲音各自獨立。';

  @override
  String screenShelfCount(int count) {
    return '$count 個';
  }

  @override
  String get screenUsageShared => '共用';

  @override
  String get screenUsageHere => '本屏';

  @override
  String get screenUsageOther => '他屏';

  @override
  String get screenUsageNone => '未用';

  @override
  String screenUsageScreens(int count) {
    return '$count 屏使用';
  }

  @override
  String get screenUsageSingle => '獨立素材';

  @override
  String get screenLayers => '圖層';

  @override
  String get screenLayersHint => '拖動排序 · 上層在前';

  @override
  String get screenLayersEmpty => '這一屏還沒有圖層。從素材庫加入，或按「新增素材」。';

  @override
  String get screenShow => '顯示';

  @override
  String get screenHide => '隱藏';

  @override
  String get screenLock => '鎖定';

  @override
  String get screenUnlock => '解鎖';

  @override
  String get screenSound => '聲音';

  @override
  String get screenBackToScreen => '螢幕設定';

  @override
  String get screenMaterialName => '素材名稱';

  @override
  String get screenDuplicate => '複製為獨立素材';

  @override
  String get screenDeleteLayer => '刪除圖層';

  @override
  String get screenAddLayer => '新增圖層';

  @override
  String get screenDeleteMaterial => '刪除素材';

  @override
  String get screenSectionLyric => '歌詞';

  @override
  String get screenFollowNow => '跟隨目前播放';

  @override
  String get screenOverlayAbove => '疊在歌詞上方';

  @override
  String screenLineCount(int count) {
    return '$count 行';
  }

  @override
  String get screenTimeOffset => '時間偏移';

  @override
  String get screenLyricNoBgNote => '歌詞不帶底色。要背景就把圖片或影片拉到滿版、鎖定、放最底層。';

  @override
  String get screenSectionUrl => '網址';

  @override
  String get screenEmbedPage => '嵌入網頁';

  @override
  String get screenUrlPlaceholder => 'https://…';

  @override
  String get screenUrlReloadHint => '改網址或按重新載入才會刷新。';

  @override
  String get screenReload => '重新載入';

  @override
  String get screenRefresh => '刷新間隔';

  @override
  String get screenSeconds => '秒';

  @override
  String get screenUrlEmbedNote =>
      '對方網站若禁止嵌入（X-Frame-Options / CSP），畫面會空白；可改用圖片或影片素材。';

  @override
  String get screenUrlPreviewHint => '投放時在這裡顯示網頁';

  @override
  String get screenScreenSound => '本屏聲音';

  @override
  String get screenVolume => '音量';

  @override
  String get screenSource => '來源';

  @override
  String get screenStaticContent => '靜態內容';

  @override
  String get screenSectionImage => '圖片';

  @override
  String get screenSectionVideo => '影片';

  @override
  String get screenSectionText => '文字';

  @override
  String get screenSectionSound => '本屏播放';

  @override
  String get screenLocalFile => '本機檔案';

  @override
  String get screenUrlSource => '圖片網址';

  @override
  String get screenImageUrl => '圖片網址';

  @override
  String get screenVideoUrl => '影片網址';

  @override
  String get screenFilePath => '檔案路徑';

  @override
  String get screenImageUrlPlaceholder => 'https://…/photo.jpg';

  @override
  String get screenImagePathPlaceholder => '選擇本機圖片…';

  @override
  String get screenVideoUrlPlaceholder => 'https://…/clip.mp4';

  @override
  String get screenVideoPathPlaceholder => '選擇本機影片…';

  @override
  String get screenFill => '填充';

  @override
  String get screenFitStretch => '拉伸';

  @override
  String get screenRadius => '圓角';

  @override
  String get screenLoop => '循環播放';

  @override
  String get screenPlayOnce => '單次';

  @override
  String get screenAutoplay => '自動播放';

  @override
  String get screenMuted => '靜音';

  @override
  String get screenMuteOthersNote => '同一屏只保留一路有聲；開啟時其他素材會自動靜音。';

  @override
  String get screenImageBgNote => '全屏背景照樣用圖片做：拉到滿版、放到最底層、鎖定圖層即可。';

  @override
  String get screenTextPlaceholder => '輸入文字…';

  @override
  String get screenTextNote => '文字本身沒有背景；需要底色或壓暗時，在下面加一個圖片或影片圖層。';

  @override
  String get screenColor => '顏色';

  @override
  String get screenGeometry => '位置與層級';

  @override
  String get screenOpacity => '不透明度';

  @override
  String get screenZOrder => '層級';

  @override
  String get screenZTop => '置頂';

  @override
  String get screenZUp => '上移一層';

  @override
  String get screenZDown => '下移一層';

  @override
  String get screenZBottom => '置底';

  @override
  String get screenShownOn => '顯示於';

  @override
  String get screenLockLayer => '鎖定圖層';

  @override
  String get screenSharedNote => '樣式與內容同步到共用此素材的螢幕；位置、透明度、層級與本屏聲音各自獨立。';

  @override
  String get screenCanvasColor => '畫布底色';

  @override
  String get screenTransparent => '透明';

  @override
  String get screenBlack => '純黑';

  @override
  String get screenMidnight => '午夜';

  @override
  String get screenLightCanvas => '淺色';

  @override
  String get screenCustomColor => '自訂顏色';

  @override
  String get screenCanvasNote => '透明會讓桌面透出來；選顏色則鋪一層不透明底色。';

  @override
  String get screenCast => '投放';

  @override
  String get screenCastThisScreen => '投放這塊螢幕';

  @override
  String get screenCoverage => '覆蓋範圍';

  @override
  String get screenFull => '整屏';

  @override
  String get screenWork => '工作區';

  @override
  String get screenPerformance => '效能';

  @override
  String get screenPerfLayers => '圖層';

  @override
  String get screenPerfUrls => '網頁';

  @override
  String get screenPerfVideos => '影片';

  @override
  String get screenPerfAudio => '有聲';

  @override
  String get screenPerfHint => '網頁與影片每多一路，CPU/GPU 與記憶體都會明顯上升；同屏各留一個最穩。';

  @override
  String get screenTips => '小提示';

  @override
  String get screenTipsText =>
      '拖動素材移動、拖八個角縮放；方向鍵微調（Shift ×10），Delete 刪除，Esc 取消選取。';

  @override
  String get screenSoundFollowsScreen => '聲音跟屏走';

  @override
  String get screenEmptyMaterial => '還沒設定內容';

  @override
  String get screenPickImage => '選擇圖片';

  @override
  String get screenPickVideo => '選擇影片';

  @override
  String get screenNoVideos => '這個資料夾下沒有影片檔案（mp4/webm/mov/mkv/avi/m4v/ogv）';

  @override
  String get screenTagLight => '輕量';

  @override
  String get screenTagNormal => '普通';

  @override
  String get screenTagHeavy => '較重';

  @override
  String get screenTypeLyric => '歌詞';

  @override
  String get screenTypeLyricDesc => '跟隨播放的即時歌詞';

  @override
  String get screenTypeUrl => '網址';

  @override
  String get screenTypeUrlDesc => '嵌入一個網頁';

  @override
  String get screenTypeImage => '圖片';

  @override
  String get screenTypeImageDesc => '本機檔案或圖片網址';

  @override
  String get screenTypeVideo => '影片';

  @override
  String get screenTypeVideoDesc => '本機或網絡影片，可帶聲音';

  @override
  String get screenTypeText => '文字';

  @override
  String get screenTypeTextDesc => '靜態文字';

  @override
  String get sourcesTitle => '音源';

  @override
  String sourcesTotal(int count) {
    return '曲庫共 $count 首';
  }

  @override
  String sourcesSummary(int local, int webdav) {
    return '本地 $local 首 · WebDAV $webdav 首';
  }

  @override
  String get manageSources => '管理';

  @override
  String get localSourceTitle => '本地音源';

  @override
  String get webdavSourceTitle => 'WebDAV 音源';

  @override
  String webdavCount(int count) {
    return '$count 個';
  }

  @override
  String get webdavEmptyTitle => '還沒有 WebDAV 音源';

  @override
  String get webdavEmptyHint => '連接 NAS 或任意 WebDAV 服務，掃描後與本地曲庫一起參與點歌';

  @override
  String get webdavAdd => '新增';

  @override
  String get webdavAddTitle => '新增 WebDAV 音源';

  @override
  String get webdavEditTitle => '編輯 WebDAV 音源';

  @override
  String get webdavName => '名稱';

  @override
  String get webdavUrl => '伺服器位址';

  @override
  String get webdavUsername => '使用者名稱';

  @override
  String get webdavPassword => '密碼';

  @override
  String get webdavAllowSelfSigned => '允許自簽章憑證（NAS 常用）';

  @override
  String get webdavDialogHint => '連線資訊只保存在本機；掃描後可像本地曲庫一樣檢索、點歌和投放。';

  @override
  String get webdavTest => '測試連線';

  @override
  String get webdavSaveAndScan => '儲存並掃描';

  @override
  String get webdavSync => '同步';

  @override
  String get webdavSyncing => '同步中…';

  @override
  String get webdavNeverSynced => '尚未同步';

  @override
  String get webdavEdit => '編輯';

  @override
  String get webdavDelete => '刪除';

  @override
  String get webdavMore => '更多';

  @override
  String webdavDeleteConfirm(String name) {
    return '刪除「$name」？';
  }

  @override
  String get webdavInvalidUrl => '伺服器位址需以 http(s):// 開頭';

  @override
  String get webdavNeedUrl => '請先填寫伺服器位址';

  @override
  String get webdavNeedName => '請先填寫名稱';

  @override
  String webdavTestOk(int count) {
    return '連線正常，根目錄有 $count 個項目';
  }

  @override
  String webdavTestFailed(String error) {
    return '連線失敗：$error';
  }

  @override
  String webdavAuthFailed(int status) {
    return '認證失敗（HTTP $status）';
  }

  @override
  String webdavHttpError(int status) {
    return '伺服器回應 HTTP $status';
  }

  @override
  String webdavConnectFailed(String detail) {
    return '連線失敗：$detail';
  }

  @override
  String webdavTlsFailed(String detail) {
    return '憑證校驗失敗，可允許自簽章憑證：$detail';
  }

  @override
  String get webdavTimeout => '連線逾時';

  @override
  String get webdavInvalidXml => '無法解析 WebDAV 回應';

  @override
  String get webdavNotDav => '這個位址不是 WebDAV 服務';

  @override
  String get webdavNotFound => '遠端資料夾不存在';

  @override
  String webdavPartialFolders(int count) {
    return '$count 個資料夾讀取失敗，已同步其餘曲目';
  }

  @override
  String webdavFileUnavailable(String name) {
    return '遠端檔案不可用：$name';
  }

  @override
  String webdavSyncedAt(String time) {
    return '同步於 $time';
  }

  @override
  String webdavLastScanned(String time) {
    return '上次掃描 $time';
  }

  @override
  String webdavSyncProgress(int tracks, int folders) {
    return '已發現 $tracks 首 · $folders 個資料夾';
  }

  @override
  String get webdavTesting => '測試中…';

  @override
  String get webdavSaving => '儲存中…';
}
