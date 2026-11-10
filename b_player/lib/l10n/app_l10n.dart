import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_l10n_en.dart';
import 'app_l10n_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppL10n
/// returned by `AppL10n.of(context)`.
///
/// Applications need to include `AppL10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_l10n.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppL10n.localizationsDelegates,
///   supportedLocales: AppL10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppL10n.supportedLocales
/// property.
abstract class AppL10n {
  AppL10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppL10n of(BuildContext context) {
    return Localizations.of<AppL10n>(context, AppL10n)!;
  }

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ];

  /// No description provided for @settingsTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'設定'**
  String get settingsTitle;

  /// No description provided for @done.
  ///
  /// In zh_Hant, this message translates to:
  /// **'完成'**
  String get done;

  /// No description provided for @close.
  ///
  /// In zh_Hant, this message translates to:
  /// **'關閉'**
  String get close;

  /// No description provided for @cancel.
  ///
  /// In zh_Hant, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In zh_Hant, this message translates to:
  /// **'確認'**
  String get confirm;

  /// No description provided for @delete.
  ///
  /// In zh_Hant, this message translates to:
  /// **'刪除'**
  String get delete;

  /// No description provided for @notSet.
  ///
  /// In zh_Hant, this message translates to:
  /// **'未設定'**
  String get notSet;

  /// No description provided for @notAssigned.
  ///
  /// In zh_Hant, this message translates to:
  /// **'未分配'**
  String get notAssigned;

  /// No description provided for @tabDisplay.
  ///
  /// In zh_Hant, this message translates to:
  /// **'顯示'**
  String get tabDisplay;

  /// No description provided for @tabBroadcast.
  ///
  /// In zh_Hant, this message translates to:
  /// **'廣播'**
  String get tabBroadcast;

  /// No description provided for @tabSources.
  ///
  /// In zh_Hant, this message translates to:
  /// **'音源'**
  String get tabSources;

  /// No description provided for @tabCast.
  ///
  /// In zh_Hant, this message translates to:
  /// **'螢幕管理'**
  String get tabCast;

  /// No description provided for @tabAbout.
  ///
  /// In zh_Hant, this message translates to:
  /// **'關於'**
  String get tabAbout;

  /// No description provided for @theme.
  ///
  /// In zh_Hant, this message translates to:
  /// **'主題'**
  String get theme;

  /// No description provided for @themeDark.
  ///
  /// In zh_Hant, this message translates to:
  /// **'暗色'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In zh_Hant, this message translates to:
  /// **'亮色'**
  String get themeLight;

  /// No description provided for @themeSystem.
  ///
  /// In zh_Hant, this message translates to:
  /// **'跟隨系統'**
  String get themeSystem;

  /// No description provided for @themeSystemHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'「跟隨系統」會隨裝置的深色模式自動切換。'**
  String get themeSystemHint;

  /// No description provided for @textSize.
  ///
  /// In zh_Hant, this message translates to:
  /// **'字型大小'**
  String get textSize;

  /// No description provided for @textSizeSmall.
  ///
  /// In zh_Hant, this message translates to:
  /// **'小'**
  String get textSizeSmall;

  /// No description provided for @textSizeMedium.
  ///
  /// In zh_Hant, this message translates to:
  /// **'中'**
  String get textSizeMedium;

  /// No description provided for @textSizeLarge.
  ///
  /// In zh_Hant, this message translates to:
  /// **'大'**
  String get textSizeLarge;

  /// No description provided for @textSizeXLarge.
  ///
  /// In zh_Hant, this message translates to:
  /// **'特大'**
  String get textSizeXLarge;

  /// No description provided for @displayPrefsHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'顯示偏好保存在本機，重啟後保持。'**
  String get displayPrefsHint;

  /// No description provided for @language.
  ///
  /// In zh_Hant, this message translates to:
  /// **'語言'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In zh_Hant, this message translates to:
  /// **'跟隨系統'**
  String get languageSystem;

  /// No description provided for @languageSimplifiedChinese.
  ///
  /// In zh_Hant, this message translates to:
  /// **'简体中文'**
  String get languageSimplifiedChinese;

  /// No description provided for @languageTraditionalChinese.
  ///
  /// In zh_Hant, this message translates to:
  /// **'繁體中文'**
  String get languageTraditionalChinese;

  /// No description provided for @languageEnglish.
  ///
  /// In zh_Hant, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'簡體中文系統顯示簡體中文，繁體中文系統顯示繁體中文；其他語言顯示英文。'**
  String get languageHint;

  /// No description provided for @aboutVersionNode.
  ///
  /// In zh_Hant, this message translates to:
  /// **'版本與節點'**
  String get aboutVersionNode;

  /// No description provided for @aboutVersion.
  ///
  /// In zh_Hant, this message translates to:
  /// **'版本'**
  String get aboutVersion;

  /// No description provided for @aboutNodeId.
  ///
  /// In zh_Hant, this message translates to:
  /// **'節點 ID'**
  String get aboutNodeId;

  /// No description provided for @aboutConnection.
  ///
  /// In zh_Hant, this message translates to:
  /// **'連線狀態'**
  String get aboutConnection;

  /// No description provided for @aboutLibraryDir.
  ///
  /// In zh_Hant, this message translates to:
  /// **'曲庫資料夾'**
  String get aboutLibraryDir;

  /// No description provided for @aboutOpenSource.
  ///
  /// In zh_Hant, this message translates to:
  /// **'開源授權'**
  String get aboutOpenSource;

  /// No description provided for @aboutLicense.
  ///
  /// In zh_Hant, this message translates to:
  /// **'授權條款'**
  String get aboutLicense;

  /// No description provided for @aboutViewLicenses.
  ///
  /// In zh_Hant, this message translates to:
  /// **'查看授權與第三方元件'**
  String get aboutViewLicenses;

  /// No description provided for @aboutOpenSourceHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'本程式以 AGPL-3.0 授權。第三方元件包含 CEF（BSD-3）、libmpv／FFmpeg（LGPL-2.1-or-later），完整清單見授權頁。'**
  String get aboutOpenSourceHint;

  /// No description provided for @aboutSourceCode.
  ///
  /// In zh_Hant, this message translates to:
  /// **'原始碼'**
  String get aboutSourceCode;

  /// No description provided for @aboutSourceCopied.
  ///
  /// In zh_Hant, this message translates to:
  /// **'原始碼位址已複製'**
  String get aboutSourceCopied;

  /// No description provided for @settingsTooltip.
  ///
  /// In zh_Hant, this message translates to:
  /// **'設定'**
  String get settingsTooltip;

  /// No description provided for @trayOpen.
  ///
  /// In zh_Hant, this message translates to:
  /// **'開啟 eNode'**
  String get trayOpen;

  /// No description provided for @trayAutostart.
  ///
  /// In zh_Hant, this message translates to:
  /// **'開機啟動'**
  String get trayAutostart;

  /// No description provided for @trayQuit.
  ///
  /// In zh_Hant, this message translates to:
  /// **'退出'**
  String get trayQuit;

  /// No description provided for @exitTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'要退出軟體嗎？'**
  String get exitTitle;

  /// No description provided for @mqttNotConfigured.
  ///
  /// In zh_Hant, this message translates to:
  /// **'MQTT 未設定'**
  String get mqttNotConfigured;

  /// No description provided for @mqttInvalidConfig.
  ///
  /// In zh_Hant, this message translates to:
  /// **'MQTT 參數有誤'**
  String get mqttInvalidConfig;

  /// No description provided for @mqttConnected.
  ///
  /// In zh_Hant, this message translates to:
  /// **'MQTT 已連線'**
  String get mqttConnected;

  /// No description provided for @mqttConnecting.
  ///
  /// In zh_Hant, this message translates to:
  /// **'MQTT 連線中'**
  String get mqttConnecting;

  /// No description provided for @mqttFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'MQTT 連線失敗'**
  String get mqttFailed;

  /// No description provided for @mqttDisconnected.
  ///
  /// In zh_Hant, this message translates to:
  /// **'MQTT 未連線'**
  String get mqttDisconnected;

  /// No description provided for @nowPlaying.
  ///
  /// In zh_Hant, this message translates to:
  /// **'播放'**
  String get nowPlaying;

  /// No description provided for @queueEmpty.
  ///
  /// In zh_Hant, this message translates to:
  /// **'隊列為空'**
  String get queueEmpty;

  /// No description provided for @queuePosition.
  ///
  /// In zh_Hant, this message translates to:
  /// **'第 1 / {total}'**
  String queuePosition(int total);

  /// No description provided for @addedHere.
  ///
  /// In zh_Hant, this message translates to:
  /// **'本機新增'**
  String get addedHere;

  /// No description provided for @fromGuest.
  ///
  /// In zh_Hant, this message translates to:
  /// **'C端 · {seat}'**
  String fromGuest(String seat);

  /// No description provided for @timeLeft.
  ///
  /// In zh_Hant, this message translates to:
  /// **'剩 {time}'**
  String timeLeft(String time);

  /// No description provided for @volume.
  ///
  /// In zh_Hant, this message translates to:
  /// **'音量'**
  String get volume;

  /// No description provided for @queue.
  ///
  /// In zh_Hant, this message translates to:
  /// **'隊列'**
  String get queue;

  /// No description provided for @queueLimit.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{count, plural, other{{count} 首 / 上限 200}}'**
  String queueLimit(int count);

  /// No description provided for @moveToPosition.
  ///
  /// In zh_Hant, this message translates to:
  /// **'把「{title}」移到第 {position} 位？'**
  String moveToPosition(String title, int position);

  /// No description provided for @playingNow.
  ///
  /// In zh_Hant, this message translates to:
  /// **'播放中'**
  String get playingNow;

  /// No description provided for @paused.
  ///
  /// In zh_Hant, this message translates to:
  /// **'已暫停'**
  String get paused;

  /// No description provided for @removeFromQueue.
  ///
  /// In zh_Hant, this message translates to:
  /// **'移出隊列'**
  String get removeFromQueue;

  /// No description provided for @library.
  ///
  /// In zh_Hant, this message translates to:
  /// **'曲庫'**
  String get library;

  /// No description provided for @trackCount.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{count, plural, other{{count} 首}}'**
  String trackCount(int count);

  /// No description provided for @missingCount.
  ///
  /// In zh_Hant, this message translates to:
  /// **'缺失 {count}'**
  String missingCount(int count);

  /// No description provided for @scanProgress.
  ///
  /// In zh_Hant, this message translates to:
  /// **'掃描中 {scanned} / {total}'**
  String scanProgress(int scanned, int total);

  /// No description provided for @demoLibrary.
  ///
  /// In zh_Hant, this message translates to:
  /// **'演示曲庫'**
  String get demoLibrary;

  /// No description provided for @libraryReady.
  ///
  /// In zh_Hant, this message translates to:
  /// **'已就緒'**
  String get libraryReady;

  /// No description provided for @noRealFolder.
  ///
  /// In zh_Hant, this message translates to:
  /// **'未接真實資料夾'**
  String get noRealFolder;

  /// No description provided for @noFolder.
  ///
  /// In zh_Hant, this message translates to:
  /// **'未設定資料夾'**
  String get noFolder;

  /// No description provided for @scanning.
  ///
  /// In zh_Hant, this message translates to:
  /// **'掃描中…'**
  String get scanning;

  /// No description provided for @scan.
  ///
  /// In zh_Hant, this message translates to:
  /// **'掃描'**
  String get scan;

  /// No description provided for @rescan.
  ///
  /// In zh_Hant, this message translates to:
  /// **'重新掃描'**
  String get rescan;

  /// No description provided for @folder.
  ///
  /// In zh_Hant, this message translates to:
  /// **'資料夾'**
  String get folder;

  /// No description provided for @changeFolder.
  ///
  /// In zh_Hant, this message translates to:
  /// **'更改資料夾'**
  String get changeFolder;

  /// No description provided for @grantAccess.
  ///
  /// In zh_Hant, this message translates to:
  /// **'去授權'**
  String get grantAccess;

  /// No description provided for @systemSettings.
  ///
  /// In zh_Hant, this message translates to:
  /// **'系統設定'**
  String get systemSettings;

  /// No description provided for @dirUnreadable.
  ///
  /// In zh_Hant, this message translates to:
  /// **'無法讀取該資料夾，可能缺少儲存權限'**
  String get dirUnreadable;

  /// No description provided for @chooseLibraryFolder.
  ///
  /// In zh_Hant, this message translates to:
  /// **'選擇曲庫資料夾'**
  String get chooseLibraryFolder;

  /// No description provided for @parentFolder.
  ///
  /// In zh_Hant, this message translates to:
  /// **'上一級'**
  String get parentFolder;

  /// No description provided for @chooseFolderHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'儲存後會立即重新掃描，子資料夾會被遞迴掃描。'**
  String get chooseFolderHint;

  /// No description provided for @chooseThisFolder.
  ///
  /// In zh_Hant, this message translates to:
  /// **'選擇此資料夾'**
  String get chooseThisFolder;

  /// No description provided for @openStorageSettings.
  ///
  /// In zh_Hant, this message translates to:
  /// **'去系統設定授權'**
  String get openStorageSettings;

  /// No description provided for @noSubfolders.
  ///
  /// In zh_Hant, this message translates to:
  /// **'這裡沒有子資料夾，可直接選擇目前資料夾'**
  String get noSubfolders;

  /// No description provided for @imageDirUnreadable.
  ///
  /// In zh_Hant, this message translates to:
  /// **'讀不到這個資料夾'**
  String get imageDirUnreadable;

  /// No description provided for @chooseBackgroundImage.
  ///
  /// In zh_Hant, this message translates to:
  /// **'選擇背景圖片'**
  String get chooseBackgroundImage;

  /// No description provided for @pastePathHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'也可以直接貼路徑，例如 D:\\pics\\stage.png'**
  String get pastePathHint;

  /// No description provided for @imagePathNote.
  ///
  /// In zh_Hant, this message translates to:
  /// **'只存本機絕對路徑，不複製檔案、不進曲庫索引。'**
  String get imagePathNote;

  /// No description provided for @useThisPath.
  ///
  /// In zh_Hant, this message translates to:
  /// **'用這個路徑'**
  String get useThisPath;

  /// No description provided for @imageDirError.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{error} —— 換個資料夾，或在下面直接貼路徑'**
  String imageDirError(String error);

  /// No description provided for @noImages.
  ///
  /// In zh_Hant, this message translates to:
  /// **'這個資料夾下沒有圖片檔案（png/jpg/jpeg/webp/bmp/gif）'**
  String get noImages;

  /// No description provided for @mqttIntro.
  ///
  /// In zh_Hant, this message translates to:
  /// **'把連線資訊整段貼進來就行，Broker、連接埠、帳號、密碼會自動識別，不用逐項填寫。'**
  String get mqttIntro;

  /// No description provided for @mqttIntroUnconfigured.
  ///
  /// In zh_Hant, this message translates to:
  /// **'還沒有設定 MQTT。把中繼那邊的連線資訊整段貼進來，識別後立即連線。'**
  String get mqttIntroUnconfigured;

  /// No description provided for @mqttPasteHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'mqtt://帳號:密碼@位址:1883\n或：位址 / 連接埠 / 帳號 / 密碼 分多行貼上'**
  String get mqttPasteHint;

  /// No description provided for @mqttApplying.
  ///
  /// In zh_Hant, this message translates to:
  /// **'套用中…'**
  String get mqttApplying;

  /// No description provided for @mqttApply.
  ///
  /// In zh_Hant, this message translates to:
  /// **'識別並套用'**
  String get mqttApply;

  /// No description provided for @mqttClear.
  ///
  /// In zh_Hant, this message translates to:
  /// **'清除本機設定'**
  String get mqttClear;

  /// No description provided for @mqttActive.
  ///
  /// In zh_Hant, this message translates to:
  /// **'目前生效'**
  String get mqttActive;

  /// No description provided for @mqttNotConfiguredShort.
  ///
  /// In zh_Hant, this message translates to:
  /// **'未設定'**
  String get mqttNotConfiguredShort;

  /// No description provided for @mqttAnonymous.
  ///
  /// In zh_Hant, this message translates to:
  /// **'匿名'**
  String get mqttAnonymous;

  /// No description provided for @mqttPasswordMasked.
  ///
  /// In zh_Hant, this message translates to:
  /// **'••••••（{length} 位）'**
  String mqttPasswordMasked(int length);

  /// No description provided for @mqttTopicPrefix.
  ///
  /// In zh_Hant, this message translates to:
  /// **'主題前綴'**
  String get mqttTopicPrefix;

  /// No description provided for @mqttLocalOnly.
  ///
  /// In zh_Hant, this message translates to:
  /// **'參數只保存在本機，密碼不會寫進日誌。'**
  String get mqttLocalOnly;

  /// No description provided for @mqttApplied.
  ///
  /// In zh_Hant, this message translates to:
  /// **'已識別並套用 {host}:{port}'**
  String mqttApplied(String host, int port);

  /// No description provided for @applyFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'套用失敗：{error}'**
  String applyFailed(String error);

  /// No description provided for @mqttCleared.
  ///
  /// In zh_Hant, this message translates to:
  /// **'已清除本機設定'**
  String get mqttCleared;

  /// No description provided for @clearFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'清除失敗：{error}'**
  String clearFailed(String error);

  /// No description provided for @brokerAddress.
  ///
  /// In zh_Hant, this message translates to:
  /// **'Broker 位址'**
  String get brokerAddress;

  /// No description provided for @username.
  ///
  /// In zh_Hant, this message translates to:
  /// **'帳號'**
  String get username;

  /// No description provided for @password.
  ///
  /// In zh_Hant, this message translates to:
  /// **'密碼'**
  String get password;

  /// No description provided for @pasteEmpty.
  ///
  /// In zh_Hant, this message translates to:
  /// **'先貼上一段連線資訊'**
  String get pasteEmpty;

  /// No description provided for @pasteUnrecognized.
  ///
  /// In zh_Hant, this message translates to:
  /// **'沒認出連線資訊。可以貼 mqtt://帳號:密碼@位址:連接埠，或位址/連接埠/帳號/密碼多行。'**
  String get pasteUnrecognized;

  /// No description provided for @pasteMissingHost.
  ///
  /// In zh_Hant, this message translates to:
  /// **'JSON 裡缺少 host（Broker 位址）'**
  String get pasteMissingHost;

  /// No description provided for @pasteNoWebsocket.
  ///
  /// In zh_Hant, this message translates to:
  /// **'暫不支援 ws/wss 位址，請換成 mqtt://位址:連接埠'**
  String get pasteNoWebsocket;

  /// No description provided for @pasteBadHost.
  ///
  /// In zh_Hant, this message translates to:
  /// **'Broker 位址格式不對'**
  String get pasteBadHost;

  /// No description provided for @configHostRequired.
  ///
  /// In zh_Hant, this message translates to:
  /// **'Broker 位址不能為空'**
  String get configHostRequired;

  /// No description provided for @configPortRange.
  ///
  /// In zh_Hant, this message translates to:
  /// **'連接埠需在 1–65535'**
  String get configPortRange;

  /// No description provided for @configTopicPrefix.
  ///
  /// In zh_Hant, this message translates to:
  /// **'主題前綴不能為空，且不能含 #、+、空格'**
  String get configTopicPrefix;

  /// No description provided for @configClientIdTooLong.
  ///
  /// In zh_Hant, this message translates to:
  /// **'Client ID 過長'**
  String get configClientIdTooLong;

  /// No description provided for @connectFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'連線失敗：{error}'**
  String connectFailed(String error);

  /// No description provided for @connectNotEstablished.
  ///
  /// In zh_Hant, this message translates to:
  /// **'連線未建立（{state}）'**
  String connectNotEstablished(String state);

  /// No description provided for @connectionClosed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'連線已斷開'**
  String get connectionClosed;

  /// No description provided for @publishFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'發佈失敗：{error}'**
  String publishFailed(String error);

  /// No description provided for @searchTimeout.
  ///
  /// In zh_Hant, this message translates to:
  /// **'檢索逾時'**
  String get searchTimeout;

  /// No description provided for @permNoPermissionNeeded.
  ///
  /// In zh_Hant, this message translates to:
  /// **'無需授權'**
  String get permNoPermissionNeeded;

  /// No description provided for @permAllFiles.
  ///
  /// In zh_Hant, this message translates to:
  /// **'已授權（所有檔案存取）'**
  String get permAllFiles;

  /// No description provided for @permAudioOnly.
  ///
  /// In zh_Hant, this message translates to:
  /// **'僅音訊可讀；讀取 .lrc 與掃描資料夾還需「所有檔案存取」'**
  String get permAudioOnly;

  /// No description provided for @permNotGranted.
  ///
  /// In zh_Hant, this message translates to:
  /// **'未授權：請在系統設定中允許存取儲存空間'**
  String get permNotGranted;

  /// No description provided for @folderMissing.
  ///
  /// In zh_Hant, this message translates to:
  /// **'資料夾不存在：{root}'**
  String folderMissing(String root);

  /// No description provided for @folderUnreadable.
  ///
  /// In zh_Hant, this message translates to:
  /// **'無法讀取資料夾：{message}'**
  String folderUnreadable(String message);

  /// No description provided for @unknownArtist.
  ///
  /// In zh_Hant, this message translates to:
  /// **'未知歌手'**
  String get unknownArtist;

  /// No description provided for @lyricsEmpty.
  ///
  /// In zh_Hant, this message translates to:
  /// **'歌詞為空'**
  String get lyricsEmpty;

  /// No description provided for @noLyrics.
  ///
  /// In zh_Hant, this message translates to:
  /// **'沒有歌詞'**
  String get noLyrics;

  /// No description provided for @onlineLibrary.
  ///
  /// In zh_Hant, this message translates to:
  /// **'線上曲庫'**
  String get onlineLibrary;

  /// No description provided for @localFolder.
  ///
  /// In zh_Hant, this message translates to:
  /// **'本地目錄'**
  String get localFolder;

  /// No description provided for @demoNoLyrics.
  ///
  /// In zh_Hant, this message translates to:
  /// **'演示曲目沒有歌詞'**
  String get demoNoLyrics;

  /// No description provided for @unsupportedSearch.
  ///
  /// In zh_Hant, this message translates to:
  /// **'該音源不支援檢索'**
  String get unsupportedSearch;

  /// No description provided for @unsupportedPlay.
  ///
  /// In zh_Hant, this message translates to:
  /// **'該音源不支援播放'**
  String get unsupportedPlay;

  /// No description provided for @unsupportedLyrics.
  ///
  /// In zh_Hant, this message translates to:
  /// **'該音源不支援歌詞'**
  String get unsupportedLyrics;

  /// No description provided for @kugouSearchFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'酷狗搜尋失敗'**
  String get kugouSearchFailed;

  /// No description provided for @kugouMissingHash.
  ///
  /// In zh_Hant, this message translates to:
  /// **'酷狗曲目缺少 hash'**
  String get kugouMissingHash;

  /// No description provided for @kugouNoLyrics.
  ///
  /// In zh_Hant, this message translates to:
  /// **'酷狗沒有找到歌詞'**
  String get kugouNoLyrics;

  /// No description provided for @kugouMissingCredential.
  ///
  /// In zh_Hant, this message translates to:
  /// **'酷狗歌詞缺少憑證'**
  String get kugouMissingCredential;

  /// No description provided for @kugouLyricsEmpty.
  ///
  /// In zh_Hant, this message translates to:
  /// **'酷狗歌詞為空'**
  String get kugouLyricsEmpty;

  /// No description provided for @kuwoSearchFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'酷我搜尋失敗'**
  String get kuwoSearchFailed;

  /// No description provided for @kuwoNoLyrics.
  ///
  /// In zh_Hant, this message translates to:
  /// **'酷我沒有歌詞'**
  String get kuwoNoLyrics;

  /// No description provided for @kuwoMissingId.
  ///
  /// In zh_Hant, this message translates to:
  /// **'酷我曲目缺少 ID'**
  String get kuwoMissingId;

  /// No description provided for @miguSearchFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'咪咕搜尋失敗'**
  String get miguSearchFailed;

  /// No description provided for @miguNoLyricUrl.
  ///
  /// In zh_Hant, this message translates to:
  /// **'咪咕曲目沒有歌詞位址'**
  String get miguNoLyricUrl;

  /// No description provided for @miguLyricsEmpty.
  ///
  /// In zh_Hant, this message translates to:
  /// **'咪咕歌詞為空'**
  String get miguLyricsEmpty;

  /// No description provided for @qqSearchFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'QQ 音樂搜尋失敗'**
  String get qqSearchFailed;

  /// No description provided for @qqMissingMid.
  ///
  /// In zh_Hant, this message translates to:
  /// **'QQ 音樂曲目缺少 mid'**
  String get qqMissingMid;

  /// No description provided for @qqNoLyrics.
  ///
  /// In zh_Hant, this message translates to:
  /// **'QQ 音樂沒有歌詞'**
  String get qqNoLyrics;

  /// No description provided for @neteaseMissingId.
  ///
  /// In zh_Hant, this message translates to:
  /// **'網易雲曲目缺少 ID'**
  String get neteaseMissingId;

  /// No description provided for @neteaseNoLyrics.
  ///
  /// In zh_Hant, this message translates to:
  /// **'網易雲沒有歌詞'**
  String get neteaseNoLyrics;

  /// No description provided for @lyricsDecodeFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'歌詞內容解碼失敗'**
  String get lyricsDecodeFailed;

  /// No description provided for @httpBadJson.
  ///
  /// In zh_Hant, this message translates to:
  /// **'回應不是有效 JSON'**
  String get httpBadJson;

  /// No description provided for @httpRateLimited.
  ///
  /// In zh_Hant, this message translates to:
  /// **'請求過速，請稍後再試'**
  String get httpRateLimited;

  /// No description provided for @httpUnavailable.
  ///
  /// In zh_Hant, this message translates to:
  /// **'服務暫時不可用（HTTP {status}）'**
  String httpUnavailable(int status);

  /// No description provided for @httpFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'請求失敗（HTTP {status}）'**
  String httpFailed(int status);

  /// No description provided for @httpTimeout.
  ///
  /// In zh_Hant, this message translates to:
  /// **'網路逾時'**
  String get httpTimeout;

  /// No description provided for @httpError.
  ///
  /// In zh_Hant, this message translates to:
  /// **'網路請求失敗'**
  String get httpError;

  /// No description provided for @networkUnavailable.
  ///
  /// In zh_Hant, this message translates to:
  /// **'網路不可用'**
  String get networkUnavailable;

  /// No description provided for @jsHostFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'JS 宿主初始化失敗：{detail}'**
  String jsHostFailed(String detail);

  /// No description provided for @scriptRunFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'腳本執行失敗：{detail}'**
  String scriptRunFailed(String detail);

  /// No description provided for @scriptNoInited.
  ///
  /// In zh_Hant, this message translates to:
  /// **'腳本沒有發送 inited 事件'**
  String get scriptNoInited;

  /// No description provided for @scriptNoPlatforms.
  ///
  /// In zh_Hant, this message translates to:
  /// **'腳本沒有宣告可用的音樂服務'**
  String get scriptNoPlatforms;

  /// No description provided for @sourceNotInitialized.
  ///
  /// In zh_Hant, this message translates to:
  /// **'音源尚未初始化'**
  String get sourceNotInitialized;

  /// No description provided for @scriptCallFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'腳本呼叫失敗：{detail}'**
  String scriptCallFailed(String detail);

  /// No description provided for @scriptNoResult.
  ///
  /// In zh_Hant, this message translates to:
  /// **'腳本沒有返回結果'**
  String get scriptNoResult;

  /// No description provided for @scriptError.
  ///
  /// In zh_Hant, this message translates to:
  /// **'腳本返回錯誤'**
  String get scriptError;

  /// No description provided for @scriptBadUrl.
  ///
  /// In zh_Hant, this message translates to:
  /// **'腳本返回的播放位址無效'**
  String get scriptBadUrl;

  /// No description provided for @jsUnavailable.
  ///
  /// In zh_Hant, this message translates to:
  /// **'JS 引擎不可用：{error}'**
  String jsUnavailable(String error);

  /// No description provided for @runtimeDisposed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'執行時已釋放'**
  String get runtimeDisposed;

  /// No description provided for @scriptBadJson.
  ///
  /// In zh_Hant, this message translates to:
  /// **'腳本返回值不是有效 JSON'**
  String get scriptBadJson;

  /// No description provided for @requestBadUrl.
  ///
  /// In zh_Hant, this message translates to:
  /// **'請求位址無效'**
  String get requestBadUrl;

  /// No description provided for @requestHttpOnly.
  ///
  /// In zh_Hant, this message translates to:
  /// **'只支援 http(s) 請求'**
  String get requestHttpOnly;

  /// No description provided for @requestNoMultipart.
  ///
  /// In zh_Hant, this message translates to:
  /// **'暫不支援 multipart 請求'**
  String get requestNoMultipart;

  /// No description provided for @scriptTimeout.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{what}逾時'**
  String scriptTimeout(String what);

  /// No description provided for @scriptInit.
  ///
  /// In zh_Hant, this message translates to:
  /// **'腳本初始化'**
  String get scriptInit;

  /// No description provided for @playbackResolve.
  ///
  /// In zh_Hant, this message translates to:
  /// **'播放位址解析'**
  String get playbackResolve;

  /// No description provided for @trackNoPlatform.
  ///
  /// In zh_Hant, this message translates to:
  /// **'曲目缺少線上來源標識'**
  String get trackNoPlatform;

  /// No description provided for @resolveFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'播放位址解析失敗：{error}'**
  String resolveFailed(String error);

  /// No description provided for @resolveFailedShort.
  ///
  /// In zh_Hant, this message translates to:
  /// **'播放位址解析失敗'**
  String get resolveFailedShort;

  /// No description provided for @noImportedScripts.
  ///
  /// In zh_Hant, this message translates to:
  /// **'尚未匯入音源腳本'**
  String get noImportedScripts;

  /// No description provided for @noUsableScripts.
  ///
  /// In zh_Hant, this message translates to:
  /// **'沒有可用的音源腳本'**
  String get noUsableScripts;

  /// No description provided for @sourceResolveFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'音源取鏈失敗：{detail}'**
  String sourceResolveFailed(String detail);

  /// No description provided for @lyricsFetchFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'歌詞取得失敗：{error}'**
  String lyricsFetchFailed(String error);

  /// No description provided for @trackNoLyrics.
  ///
  /// In zh_Hant, this message translates to:
  /// **'該曲目沒有歌詞'**
  String get trackNoLyrics;

  /// No description provided for @sourceUrlScheme.
  ///
  /// In zh_Hant, this message translates to:
  /// **'音源位址需以 http(s):// 開頭'**
  String get sourceUrlScheme;

  /// No description provided for @downloadFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'下載失敗（HTTP {status}）'**
  String downloadFailed(int status);

  /// No description provided for @sourceInvalid.
  ///
  /// In zh_Hant, this message translates to:
  /// **'不是有效的音源腳本（缺少 @name 標頭）'**
  String get sourceInvalid;

  /// No description provided for @downloadTimeout.
  ///
  /// In zh_Hant, this message translates to:
  /// **'下載逾時'**
  String get downloadTimeout;

  /// No description provided for @sourceUnavailable.
  ///
  /// In zh_Hant, this message translates to:
  /// **'音源暫不可用'**
  String get sourceUnavailable;

  /// No description provided for @platformResolveUnsupported.
  ///
  /// In zh_Hant, this message translates to:
  /// **'該音源不支援此曲目取鏈'**
  String get platformResolveUnsupported;

  /// No description provided for @sourceNotFound.
  ///
  /// In zh_Hant, this message translates to:
  /// **'音源不存在'**
  String get sourceNotFound;

  /// No description provided for @seatLocal.
  ///
  /// In zh_Hant, this message translates to:
  /// **'本機'**
  String get seatLocal;

  /// No description provided for @localTag.
  ///
  /// In zh_Hant, this message translates to:
  /// **'本地'**
  String get localTag;

  /// No description provided for @scanFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'掃描失敗：{error}'**
  String scanFailed(String error);

  /// No description provided for @probeReady.
  ///
  /// In zh_Hant, this message translates to:
  /// **'就緒 {ms}ms'**
  String probeReady(int ms);

  /// No description provided for @probeNoResolve.
  ///
  /// In zh_Hant, this message translates to:
  /// **' · 無取鏈動作'**
  String get probeNoResolve;

  /// No description provided for @probeFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'失敗：{error}'**
  String probeFailed(String error);

  /// No description provided for @probeNoOnlineSource.
  ///
  /// In zh_Hant, this message translates to:
  /// **'未接入線上音源'**
  String get probeNoOnlineSource;

  /// No description provided for @probeZero.
  ///
  /// In zh_Hant, this message translates to:
  /// **'0 條 · {ms}ms'**
  String probeZero(int ms);

  /// No description provided for @probeTracks.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{count} 條 · {ms}ms · 取鏈 {resolveMs}ms ({host})'**
  String probeTracks(int count, int ms, int resolveMs, String host);

  /// No description provided for @probeResolveFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{count} 條 · {ms}ms · 取鏈失敗：{error}'**
  String probeResolveFailed(int count, int ms, String error);

  /// No description provided for @audioFormatUnsupported.
  ///
  /// In zh_Hant, this message translates to:
  /// **'無法識別音訊格式'**
  String get audioFormatUnsupported;

  /// No description provided for @audioOpenFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'無法開啟音訊檔案'**
  String get audioOpenFailed;

  /// No description provided for @skipResolveFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'無法解析「{title}」的播放位址，已跳過'**
  String skipResolveFailed(String title);

  /// No description provided for @playOpenFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'無法播放「{title}」：{error}'**
  String playOpenFailed(String title, String error);

  /// No description provided for @skipUnplayable.
  ///
  /// In zh_Hant, this message translates to:
  /// **'「{title}」無法播放，已跳過'**
  String skipUnplayable(String title);

  /// No description provided for @castBgSolid.
  ///
  /// In zh_Hant, this message translates to:
  /// **'純黑'**
  String get castBgSolid;

  /// No description provided for @castBgGradient.
  ///
  /// In zh_Hant, this message translates to:
  /// **'上下漸層'**
  String get castBgGradient;

  /// No description provided for @castBgCustom.
  ///
  /// In zh_Hant, this message translates to:
  /// **'自訂色'**
  String get castBgCustom;

  /// No description provided for @castBgImage.
  ///
  /// In zh_Hant, this message translates to:
  /// **'圖片'**
  String get castBgImage;

  /// No description provided for @castAlignLeft.
  ///
  /// In zh_Hant, this message translates to:
  /// **'左對齊'**
  String get castAlignLeft;

  /// No description provided for @castAlignCenter.
  ///
  /// In zh_Hant, this message translates to:
  /// **'居中'**
  String get castAlignCenter;

  /// No description provided for @castAlignRight.
  ///
  /// In zh_Hant, this message translates to:
  /// **'右對齊'**
  String get castAlignRight;

  /// No description provided for @onlineSourcesTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'線上音源'**
  String get onlineSourcesTitle;

  /// No description provided for @scriptCount.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{count, plural, other{{count} 個腳本}}'**
  String scriptCount(int count);

  /// No description provided for @sourcesIntro.
  ///
  /// In zh_Hant, this message translates to:
  /// **'改動即時生效，不需要另外儲存。取鏈按下面的順序逐個嘗試。'**
  String get sourcesIntro;

  /// No description provided for @sourcesEmpty.
  ///
  /// In zh_Hant, this message translates to:
  /// **'還沒有匯入音源；線上取鏈需要至少一個音源腳本。'**
  String get sourcesEmpty;

  /// No description provided for @importHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'貼上音源腳本位址，例如 https://.../source.js'**
  String get importHint;

  /// No description provided for @importing.
  ///
  /// In zh_Hant, this message translates to:
  /// **'匯入中…'**
  String get importing;

  /// No description provided for @importAction.
  ///
  /// In zh_Hant, this message translates to:
  /// **'匯入'**
  String get importAction;

  /// No description provided for @importedCount.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{count, plural, other{已匯入並啟用 · 共 {count} 個腳本}}'**
  String importedCount(int count);

  /// No description provided for @importFailedOnline.
  ///
  /// In zh_Hant, this message translates to:
  /// **'匯入失敗：{error}'**
  String importFailedOnline(String error);

  /// No description provided for @saveFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'儲存失敗：{error}'**
  String saveFailed(String error);

  /// No description provided for @needSourceUrl.
  ///
  /// In zh_Hant, this message translates to:
  /// **'請先填寫音源位址'**
  String get needSourceUrl;

  /// No description provided for @sourceEnabled.
  ///
  /// In zh_Hant, this message translates to:
  /// **'已啟用'**
  String get sourceEnabled;

  /// No description provided for @sourceDisabled.
  ///
  /// In zh_Hant, this message translates to:
  /// **'已停用'**
  String get sourceDisabled;

  /// No description provided for @sourceOrderUpdated.
  ///
  /// In zh_Hant, this message translates to:
  /// **'取鏈順序已更新'**
  String get sourceOrderUpdated;

  /// No description provided for @sourceRemoved.
  ///
  /// In zh_Hant, this message translates to:
  /// **'已刪除該音源'**
  String get sourceRemoved;

  /// No description provided for @qualityLabel.
  ///
  /// In zh_Hant, this message translates to:
  /// **'音質'**
  String get qualityLabel;

  /// No description provided for @qualitySaved.
  ///
  /// In zh_Hant, this message translates to:
  /// **'音質已儲存'**
  String get qualitySaved;

  /// No description provided for @restoreDefaults.
  ///
  /// In zh_Hant, this message translates to:
  /// **'恢復預設音質'**
  String get restoreDefaults;

  /// No description provided for @defaultsRestored.
  ///
  /// In zh_Hant, this message translates to:
  /// **'音質已恢復預設'**
  String get defaultsRestored;

  /// No description provided for @statusError.
  ///
  /// In zh_Hant, this message translates to:
  /// **'錯誤：{error}'**
  String statusError(String error);

  /// No description provided for @moveUp.
  ///
  /// In zh_Hant, this message translates to:
  /// **'上移'**
  String get moveUp;

  /// No description provided for @moveDown.
  ///
  /// In zh_Hant, this message translates to:
  /// **'下移'**
  String get moveDown;

  /// No description provided for @testSourceTooltip.
  ///
  /// In zh_Hant, this message translates to:
  /// **'測試：腳本 + 檢索 + 取鏈'**
  String get testSourceTooltip;

  /// No description provided for @checkSourceUpdate.
  ///
  /// In zh_Hant, this message translates to:
  /// **'檢查更新'**
  String get checkSourceUpdate;

  /// No description provided for @sourceUpToDate.
  ///
  /// In zh_Hant, this message translates to:
  /// **'已是最新版本'**
  String get sourceUpToDate;

  /// No description provided for @sourceUpdateFound.
  ///
  /// In zh_Hant, this message translates to:
  /// **'發現新版 {latest} · 目前 {current}'**
  String sourceUpdateFound(String latest, String current);

  /// No description provided for @sourceUpdateApply.
  ///
  /// In zh_Hant, this message translates to:
  /// **'更新'**
  String get sourceUpdateApply;

  /// No description provided for @sourceUpdateDismiss.
  ///
  /// In zh_Hant, this message translates to:
  /// **'忽略'**
  String get sourceUpdateDismiss;

  /// No description provided for @sourceUpdated.
  ///
  /// In zh_Hant, this message translates to:
  /// **'已更新至 {version}'**
  String sourceUpdated(String version);

  /// No description provided for @sourceUpdatedPlain.
  ///
  /// In zh_Hant, this message translates to:
  /// **'音源已更新'**
  String get sourceUpdatedPlain;

  /// No description provided for @sourceNotice.
  ///
  /// In zh_Hant, this message translates to:
  /// **'音源提示：{message}'**
  String sourceNotice(String message);

  /// No description provided for @sourceNoticeLink.
  ///
  /// In zh_Hant, this message translates to:
  /// **'更新地址：{url}'**
  String sourceNoticeLink(String url);

  /// No description provided for @updateCheckFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'檢查更新失敗：{error}'**
  String updateCheckFailed(String error);

  /// No description provided for @castTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'螢幕管理'**
  String get castTitle;

  /// No description provided for @castSummary.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{monitors} 台螢幕 · {windows} 個投放窗'**
  String castSummary(int monitors, int windows);

  /// No description provided for @castIntro.
  ///
  /// In zh_Hant, this message translates to:
  /// **'每台勾選的螢幕開一扇置頂穿透窗；樣式和時鐘只有一份，所以畫面天然同步，改動即時生效。投放中在投放螢幕上按右鍵，可關掉本螢幕或全部投放。'**
  String get castIntro;

  /// No description provided for @castNoMonitors.
  ///
  /// In zh_Hant, this message translates to:
  /// **'沒掃到螢幕（screen_retriever 不可用或只有一塊螢幕時也可能為空）。插好螢幕後重新掃描。'**
  String get castNoMonitors;

  /// No description provided for @castNoMonitorsFound.
  ///
  /// In zh_Hant, this message translates to:
  /// **'還是沒掃到螢幕'**
  String get castNoMonitorsFound;

  /// No description provided for @castDetected.
  ///
  /// In zh_Hant, this message translates to:
  /// **'偵測到'**
  String get castDetected;

  /// No description provided for @castDetectedValue.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{count} 台'**
  String castDetectedValue(int count);

  /// No description provided for @castCasting.
  ///
  /// In zh_Hant, this message translates to:
  /// **'投放'**
  String get castCasting;

  /// No description provided for @castCastingValue.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{count} 個視窗'**
  String castCastingValue(int count);

  /// No description provided for @castOpen.
  ///
  /// In zh_Hant, this message translates to:
  /// **'已開'**
  String get castOpen;

  /// No description provided for @castOpenValue.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{count} 扇'**
  String castOpenValue(int count);

  /// No description provided for @castMemory.
  ///
  /// In zh_Hant, this message translates to:
  /// **'額外記憶體'**
  String get castMemory;

  /// No description provided for @castSync.
  ///
  /// In zh_Hant, this message translates to:
  /// **'同步'**
  String get castSync;

  /// No description provided for @castSyncValue.
  ///
  /// In zh_Hant, this message translates to:
  /// **'一塊畫布 · 同幀呈現'**
  String get castSyncValue;

  /// No description provided for @castEnable.
  ///
  /// In zh_Hant, this message translates to:
  /// **'啟用投放'**
  String get castEnable;

  /// No description provided for @castEnabledHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'已開 {count} 扇投放窗，滑鼠點得穿，結束程式時自動收起。'**
  String castEnabledHint(int count);

  /// No description provided for @castDisabledHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'關掉時只有這裡的預覽，勾選的螢幕上不會開窗。'**
  String get castDisabledHint;

  /// No description provided for @castTargetsTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'投放目標'**
  String get castTargetsTitle;

  /// No description provided for @castMultiSelect.
  ///
  /// In zh_Hant, this message translates to:
  /// **'可多選'**
  String get castMultiSelect;

  /// No description provided for @castTargetsHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'只有勾選的螢幕才出現在下面的地圖和預覽裡。'**
  String get castTargetsHint;

  /// No description provided for @castMonitorLabel.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{index} 號 · {name}'**
  String castMonitorLabel(int index, String name);

  /// No description provided for @castMonitorSpec.
  ///
  /// In zh_Hant, this message translates to:
  /// **'整屏 {fullW}×{fullH} · 工作區 {workW}×{workH} · 縮放 {scale}%'**
  String castMonitorSpec(int fullW, int fullH, int workW, int workH, int scale);

  /// No description provided for @castFullscreen.
  ///
  /// In zh_Hant, this message translates to:
  /// **'全屏'**
  String get castFullscreen;

  /// No description provided for @castRegion.
  ///
  /// In zh_Hant, this message translates to:
  /// **'區域'**
  String get castRegion;

  /// No description provided for @castEditing.
  ///
  /// In zh_Hant, this message translates to:
  /// **'編輯中'**
  String get castEditing;

  /// No description provided for @castEditScreen.
  ///
  /// In zh_Hant, this message translates to:
  /// **'編輯這塊螢幕'**
  String get castEditScreen;

  /// No description provided for @castRegionTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'區域框選'**
  String get castRegionTitle;

  /// No description provided for @castNoSelection.
  ///
  /// In zh_Hant, this message translates to:
  /// **'還沒勾選任何螢幕 —— 在上面勾一台，這裡就只出現被選中的螢幕。'**
  String get castNoSelection;

  /// No description provided for @castPresetBottomStrip.
  ///
  /// In zh_Hant, this message translates to:
  /// **'底部字幕條'**
  String get castPresetBottomStrip;

  /// No description provided for @castPresetLowerHalf.
  ///
  /// In zh_Hant, this message translates to:
  /// **'下半屏'**
  String get castPresetLowerHalf;

  /// No description provided for @castPresetCenterStrip.
  ///
  /// In zh_Hant, this message translates to:
  /// **'居中窄條'**
  String get castPresetCenterStrip;

  /// No description provided for @castMapHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'在地圖上直接拖：框內移動、八向把手縮放、空白處重新框選。'**
  String get castMapHint;

  /// No description provided for @castMoveLeft.
  ///
  /// In zh_Hant, this message translates to:
  /// **'左移'**
  String get castMoveLeft;

  /// No description provided for @castMoveUp.
  ///
  /// In zh_Hant, this message translates to:
  /// **'上移'**
  String get castMoveUp;

  /// No description provided for @castMoveDown.
  ///
  /// In zh_Hant, this message translates to:
  /// **'下移'**
  String get castMoveDown;

  /// No description provided for @castMoveRight.
  ///
  /// In zh_Hant, this message translates to:
  /// **'右移'**
  String get castMoveRight;

  /// No description provided for @castCenterH.
  ///
  /// In zh_Hant, this message translates to:
  /// **'水平居中'**
  String get castCenterH;

  /// No description provided for @castCenterV.
  ///
  /// In zh_Hant, this message translates to:
  /// **'垂直居中'**
  String get castCenterV;

  /// No description provided for @castLeftPx.
  ///
  /// In zh_Hant, this message translates to:
  /// **'左 (px)'**
  String get castLeftPx;

  /// No description provided for @castTopPx.
  ///
  /// In zh_Hant, this message translates to:
  /// **'上 (px)'**
  String get castTopPx;

  /// No description provided for @castWidthPx.
  ///
  /// In zh_Hant, this message translates to:
  /// **'寬 (px)'**
  String get castWidthPx;

  /// No description provided for @castHeightPx.
  ///
  /// In zh_Hant, this message translates to:
  /// **'高 (px)'**
  String get castHeightPx;

  /// No description provided for @castPercentSummary.
  ///
  /// In zh_Hant, this message translates to:
  /// **'存成百分比 {left}/{top} · {width}×{height} · 該螢幕工作區 {workW}×{workH} 邏輯 px'**
  String castPercentSummary(
    String left,
    String top,
    String width,
    String height,
    int workW,
    int workH,
  );

  /// No description provided for @castStyleTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'歌詞樣式'**
  String get castStyleTitle;

  /// No description provided for @castLines.
  ///
  /// In zh_Hant, this message translates to:
  /// **'顯示行數'**
  String get castLines;

  /// No description provided for @castLinesCurrent.
  ///
  /// In zh_Hant, this message translates to:
  /// **'僅目前句'**
  String get castLinesCurrent;

  /// No description provided for @castLinesPrev.
  ///
  /// In zh_Hant, this message translates to:
  /// **'上一句 + 目前'**
  String get castLinesPrev;

  /// No description provided for @castLinesBoth.
  ///
  /// In zh_Hant, this message translates to:
  /// **'上句 + 目前 + 下句'**
  String get castLinesBoth;

  /// No description provided for @castFont.
  ///
  /// In zh_Hant, this message translates to:
  /// **'字型'**
  String get castFont;

  /// No description provided for @castFontSize.
  ///
  /// In zh_Hant, this message translates to:
  /// **'字號'**
  String get castFontSize;

  /// No description provided for @castFontSizeUnit.
  ///
  /// In zh_Hant, this message translates to:
  /// **'px（按 1080 高折算）'**
  String get castFontSizeUnit;

  /// No description provided for @castLineGap.
  ///
  /// In zh_Hant, this message translates to:
  /// **'行間距'**
  String get castLineGap;

  /// No description provided for @castTextWidth.
  ///
  /// In zh_Hant, this message translates to:
  /// **'文字寬度'**
  String get castTextWidth;

  /// No description provided for @castTextHeight.
  ///
  /// In zh_Hant, this message translates to:
  /// **'文字高度'**
  String get castTextHeight;

  /// No description provided for @castWeight.
  ///
  /// In zh_Hant, this message translates to:
  /// **'字重'**
  String get castWeight;

  /// No description provided for @castWeightRegular.
  ///
  /// In zh_Hant, this message translates to:
  /// **'400 一般'**
  String get castWeightRegular;

  /// No description provided for @castWeightMedium.
  ///
  /// In zh_Hant, this message translates to:
  /// **'500 中等'**
  String get castWeightMedium;

  /// No description provided for @castWeightSemibold.
  ///
  /// In zh_Hant, this message translates to:
  /// **'600 半粗'**
  String get castWeightSemibold;

  /// No description provided for @castWeightBold.
  ///
  /// In zh_Hant, this message translates to:
  /// **'700 粗體'**
  String get castWeightBold;

  /// No description provided for @castStroke.
  ///
  /// In zh_Hant, this message translates to:
  /// **'描邊'**
  String get castStroke;

  /// No description provided for @castStrokeUnit.
  ///
  /// In zh_Hant, this message translates to:
  /// **'px（黑色描邊，壓住背景圖和影片）'**
  String get castStrokeUnit;

  /// No description provided for @castShadow.
  ///
  /// In zh_Hant, this message translates to:
  /// **'陰影'**
  String get castShadow;

  /// No description provided for @castCurrentColor.
  ///
  /// In zh_Hant, this message translates to:
  /// **'目前歌詞顏色'**
  String get castCurrentColor;

  /// No description provided for @castOtherColor.
  ///
  /// In zh_Hant, this message translates to:
  /// **'非目前歌詞顏色'**
  String get castOtherColor;

  /// No description provided for @castOtherOpacity.
  ///
  /// In zh_Hant, this message translates to:
  /// **'非目前歌詞行透明度'**
  String get castOtherOpacity;

  /// No description provided for @castKaraokeColorHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'逐字歌詞：已唱的字用目前歌詞顏色，未唱的字用非目前歌詞顏色。'**
  String get castKaraokeColorHint;

  /// No description provided for @castBackground.
  ///
  /// In zh_Hant, this message translates to:
  /// **'投放背景'**
  String get castBackground;

  /// No description provided for @castGradientTop.
  ///
  /// In zh_Hant, this message translates to:
  /// **'漸層上'**
  String get castGradientTop;

  /// No description provided for @castGradientBottom.
  ///
  /// In zh_Hant, this message translates to:
  /// **'漸層下'**
  String get castGradientBottom;

  /// No description provided for @castSolidColor.
  ///
  /// In zh_Hant, this message translates to:
  /// **'背景色'**
  String get castSolidColor;

  /// No description provided for @castNoImage.
  ///
  /// In zh_Hant, this message translates to:
  /// **'還沒選圖片'**
  String get castNoImage;

  /// No description provided for @castBrowse.
  ///
  /// In zh_Hant, this message translates to:
  /// **'瀏覽…'**
  String get castBrowse;

  /// No description provided for @castClear.
  ///
  /// In zh_Hant, this message translates to:
  /// **'清除'**
  String get castClear;

  /// No description provided for @castImageFit.
  ///
  /// In zh_Hant, this message translates to:
  /// **'畫面鋪法'**
  String get castImageFit;

  /// No description provided for @castFitCover.
  ///
  /// In zh_Hant, this message translates to:
  /// **'鋪滿裁邊'**
  String get castFitCover;

  /// No description provided for @castFitContain.
  ///
  /// In zh_Hant, this message translates to:
  /// **'完整顯示'**
  String get castFitContain;

  /// No description provided for @castAlign.
  ///
  /// In zh_Hant, this message translates to:
  /// **'水平對齊'**
  String get castAlign;

  /// No description provided for @castVertical.
  ///
  /// In zh_Hant, this message translates to:
  /// **'垂直位置'**
  String get castVertical;

  /// No description provided for @castVerticalUnit.
  ///
  /// In zh_Hant, this message translates to:
  /// **'%（0=貼頂，歌詞塊中心）'**
  String get castVerticalUnit;

  /// No description provided for @castOffset.
  ///
  /// In zh_Hant, this message translates to:
  /// **'歌詞偏移'**
  String get castOffset;

  /// No description provided for @castOffsetUnit.
  ///
  /// In zh_Hant, this message translates to:
  /// **'ms（正值往後推）'**
  String get castOffsetUnit;

  /// No description provided for @castExtras.
  ///
  /// In zh_Hant, this message translates to:
  /// **'附加資訊'**
  String get castExtras;

  /// No description provided for @castShowTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'歌名'**
  String get castShowTitle;

  /// No description provided for @castShowArtist.
  ///
  /// In zh_Hant, this message translates to:
  /// **'歌手'**
  String get castShowArtist;

  /// No description provided for @castShowSeat.
  ///
  /// In zh_Hant, this message translates to:
  /// **'座位號'**
  String get castShowSeat;

  /// No description provided for @castPreview.
  ///
  /// In zh_Hant, this message translates to:
  /// **'預覽'**
  String get castPreview;

  /// No description provided for @castLiveBadge.
  ///
  /// In zh_Hant, this message translates to:
  /// **'跟隨本機播放'**
  String get castLiveBadge;

  /// No description provided for @castDemoBadge.
  ///
  /// In zh_Hant, this message translates to:
  /// **'演示走詞'**
  String get castDemoBadge;

  /// No description provided for @castPause.
  ///
  /// In zh_Hant, this message translates to:
  /// **'暫停'**
  String get castPause;

  /// No description provided for @castPlay.
  ///
  /// In zh_Hant, this message translates to:
  /// **'播放'**
  String get castPlay;

  /// No description provided for @castPickScreen.
  ///
  /// In zh_Hant, this message translates to:
  /// **'勾一台螢幕就能在這裡看到實際畫面。'**
  String get castPickScreen;

  /// No description provided for @castPreviewLiveHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'預覽按這台螢幕的投放區比例繪製，投放窗用的是同一套繪製。'**
  String get castPreviewLiveHint;

  /// No description provided for @castPreviewDemoHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'沒在播歌，用演示詞走一遍；開始播放後這裡會自動變成真實歌詞。'**
  String get castPreviewDemoHint;

  /// No description provided for @castPickColor.
  ///
  /// In zh_Hant, this message translates to:
  /// **'選顏色'**
  String get castPickColor;

  /// No description provided for @castColorHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'#RRGGBB 或 #AARRGGBB；A 是文字自身的透明度。'**
  String get castColorHint;

  /// No description provided for @castDemoTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'晚風不歇'**
  String get castDemoTitle;

  /// No description provided for @castDemoArtist.
  ///
  /// In zh_Hant, this message translates to:
  /// **'demo 歌手'**
  String get castDemoArtist;

  /// No description provided for @castFontYaHei.
  ///
  /// In zh_Hant, this message translates to:
  /// **'微軟雅黑'**
  String get castFontYaHei;

  /// No description provided for @castFontHei.
  ///
  /// In zh_Hant, this message translates to:
  /// **'黑體'**
  String get castFontHei;

  /// No description provided for @castFontSong.
  ///
  /// In zh_Hant, this message translates to:
  /// **'宋體'**
  String get castFontSong;

  /// No description provided for @castFontKai.
  ///
  /// In zh_Hant, this message translates to:
  /// **'楷體'**
  String get castFontKai;

  /// No description provided for @castFontDeng.
  ///
  /// In zh_Hant, this message translates to:
  /// **'等線'**
  String get castFontDeng;

  /// No description provided for @fileMissing.
  ///
  /// In zh_Hant, this message translates to:
  /// **'檔案不存在：{path}'**
  String fileMissing(String path);

  /// No description provided for @castWindowTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'eNode 歌詞投放 · {name}'**
  String castWindowTitle(String name);

  /// No description provided for @castRuntimeMissing.
  ///
  /// In zh_Hant, this message translates to:
  /// **'Chromium 執行環境起不來'**
  String get castRuntimeMissing;

  /// No description provided for @castRegionZero.
  ///
  /// In zh_Hant, this message translates to:
  /// **'投放區尺寸為 0'**
  String get castRegionZero;

  /// No description provided for @castNoBrowserHandle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'畫布瀏覽器沒有回傳控制代碼'**
  String get castNoBrowserHandle;

  /// No description provided for @castNoPresenter.
  ///
  /// In zh_Hant, this message translates to:
  /// **'畫布沒有可顯示的 presenter（需要 GPU 加速）'**
  String get castNoPresenter;

  /// No description provided for @castCanvasFallback.
  ///
  /// In zh_Hant, this message translates to:
  /// **'畫布投放起不來，退回一屏一窗：{error}'**
  String castCanvasFallback(String error);

  /// No description provided for @castWindowTimeout.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{name} 的投放窗 12 秒沒起來——多引擎可能被顯卡驅動或安全軟體攔了'**
  String castWindowTimeout(String name);

  /// No description provided for @castWindowCreateFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{name} 的投放窗建不起來：{error}'**
  String castWindowCreateFailed(String name, String error);

  /// No description provided for @castWebFallback.
  ///
  /// In zh_Hant, this message translates to:
  /// **'網頁投放退回自繪：{reason}'**
  String castWebFallback(String reason);

  /// No description provided for @castWindowGone.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{name} 的投放窗已經不在了，改一下投放設定會重新開：{error}'**
  String castWindowGone(String name, String error);

  /// No description provided for @castPageLoadFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'投放頁面載入失敗（{code}）{detail}'**
  String castPageLoadFailed(int code, String detail);

  /// No description provided for @castPushFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'推送畫面失敗：{error}'**
  String castPushFailed(String error);

  /// No description provided for @castWebError.
  ///
  /// In zh_Hant, this message translates to:
  /// **'網頁投放異常：{error}'**
  String castWebError(String error);

  /// No description provided for @castModeFull.
  ///
  /// In zh_Hant, this message translates to:
  /// **'整屏'**
  String get castModeFull;

  /// No description provided for @screenSummary.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{monitors} 台螢幕 · {materials} 個素材 · {placements} 個投放'**
  String screenSummary(int monitors, int materials, int placements);

  /// No description provided for @screenLiveSync.
  ///
  /// In zh_Hant, this message translates to:
  /// **'投放同步中'**
  String get screenLiveSync;

  /// No description provided for @screenEditOnly.
  ///
  /// In zh_Hant, this message translates to:
  /// **'僅編輯，未投放'**
  String get screenEditOnly;

  /// No description provided for @screenCastingValue.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{enabled}/{total} 投屏'**
  String screenCastingValue(int enabled, int total);

  /// No description provided for @screenScreens.
  ///
  /// In zh_Hant, this message translates to:
  /// **'螢幕'**
  String get screenScreens;

  /// No description provided for @screenCount.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{count} 台'**
  String screenCount(int count);

  /// No description provided for @screenScreenHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'點選一台螢幕開始排版'**
  String get screenScreenHint;

  /// No description provided for @screenLayersCount.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{count} 個圖層'**
  String screenLayersCount(int count);

  /// No description provided for @screenUrlBadge.
  ///
  /// In zh_Hant, this message translates to:
  /// **'網頁 {count}'**
  String screenUrlBadge(int count);

  /// No description provided for @screenVideoBadge.
  ///
  /// In zh_Hant, this message translates to:
  /// **'影片 {count}'**
  String screenVideoBadge(int count);

  /// No description provided for @screenLoadLight.
  ///
  /// In zh_Hant, this message translates to:
  /// **'輕'**
  String get screenLoadLight;

  /// No description provided for @screenLoadMid.
  ///
  /// In zh_Hant, this message translates to:
  /// **'中'**
  String get screenLoadMid;

  /// No description provided for @screenLoadHeavy.
  ///
  /// In zh_Hant, this message translates to:
  /// **'重'**
  String get screenLoadHeavy;

  /// No description provided for @screenStatus.
  ///
  /// In zh_Hant, this message translates to:
  /// **'狀態'**
  String get screenStatus;

  /// No description provided for @screenCastingScreens.
  ///
  /// In zh_Hant, this message translates to:
  /// **'投屏'**
  String get screenCastingScreens;

  /// No description provided for @screenSharedCanvas.
  ///
  /// In zh_Hant, this message translates to:
  /// **'共用畫布'**
  String get screenSharedCanvas;

  /// No description provided for @screenMaterials.
  ///
  /// In zh_Hant, this message translates to:
  /// **'素材'**
  String get screenMaterials;

  /// No description provided for @screenMaterialsValue.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{count} 個'**
  String screenMaterialsValue(int count);

  /// No description provided for @screenStatusHintOn.
  ///
  /// In zh_Hant, this message translates to:
  /// **'投放窗由一塊畫布驅動，改樣式會即時同步。'**
  String get screenStatusHintOn;

  /// No description provided for @screenStatusHintOff.
  ///
  /// In zh_Hant, this message translates to:
  /// **'未勾選任何螢幕時，畫布只做編輯預覽。'**
  String get screenStatusHintOff;

  /// No description provided for @screenDetect.
  ///
  /// In zh_Hant, this message translates to:
  /// **'偵測'**
  String get screenDetect;

  /// No description provided for @screenRescanHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'目前 {count} 台。插拔螢幕或改解析度後重掃。'**
  String screenRescanHint(int count);

  /// No description provided for @screenAddMaterial.
  ///
  /// In zh_Hant, this message translates to:
  /// **'新增素材'**
  String get screenAddMaterial;

  /// No description provided for @screenToolbarCounts.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{layers} 層 · 網頁 {urls} · 影片 {videos}'**
  String screenToolbarCounts(int layers, int urls, int videos);

  /// No description provided for @screenCastingBadge.
  ///
  /// In zh_Hant, this message translates to:
  /// **'投放中'**
  String get screenCastingBadge;

  /// No description provided for @screenNotCasting.
  ///
  /// In zh_Hant, this message translates to:
  /// **'未投放'**
  String get screenNotCasting;

  /// No description provided for @screenPerfWarning.
  ///
  /// In zh_Hant, this message translates to:
  /// **'這一屏有 {urls} 個網頁、{videos} 支影片。每一路都會多一份解碼與合成開銷，建議同屏各留一個。'**
  String screenPerfWarning(int urls, int videos);

  /// No description provided for @screenNoSelection.
  ///
  /// In zh_Hant, this message translates to:
  /// **'選中畫面上的素材調整位置 · 拖角縮放'**
  String get screenNoSelection;

  /// No description provided for @screenSelectionInfo.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{name} · {x}, {y} · {w}×{h} px'**
  String screenSelectionInfo(String name, int x, int y, int w, int h);

  /// No description provided for @screenShelf.
  ///
  /// In zh_Hant, this message translates to:
  /// **'素材庫'**
  String get screenShelf;

  /// No description provided for @screenShelfHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'拖到畫面或點一下放上這屏'**
  String get screenShelfHint;

  /// No description provided for @screenShelfMore.
  ///
  /// In zh_Hant, this message translates to:
  /// **'同一素材放到多屏只保留一份樣式；位置、層級與本屏聲音各自獨立。'**
  String get screenShelfMore;

  /// No description provided for @screenShelfCount.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{count} 個'**
  String screenShelfCount(int count);

  /// No description provided for @screenUsageShared.
  ///
  /// In zh_Hant, this message translates to:
  /// **'共用'**
  String get screenUsageShared;

  /// No description provided for @screenUsageHere.
  ///
  /// In zh_Hant, this message translates to:
  /// **'本屏'**
  String get screenUsageHere;

  /// No description provided for @screenUsageOther.
  ///
  /// In zh_Hant, this message translates to:
  /// **'他屏'**
  String get screenUsageOther;

  /// No description provided for @screenUsageNone.
  ///
  /// In zh_Hant, this message translates to:
  /// **'未用'**
  String get screenUsageNone;

  /// No description provided for @screenUsageScreens.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{count} 屏使用'**
  String screenUsageScreens(int count);

  /// No description provided for @screenUsageSingle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'獨立素材'**
  String get screenUsageSingle;

  /// No description provided for @screenLayers.
  ///
  /// In zh_Hant, this message translates to:
  /// **'圖層'**
  String get screenLayers;

  /// No description provided for @screenLayersHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'拖動排序 · 上層在前'**
  String get screenLayersHint;

  /// No description provided for @screenLayersEmpty.
  ///
  /// In zh_Hant, this message translates to:
  /// **'這一屏還沒有圖層。從素材庫加入，或按「新增素材」。'**
  String get screenLayersEmpty;

  /// No description provided for @screenShow.
  ///
  /// In zh_Hant, this message translates to:
  /// **'顯示'**
  String get screenShow;

  /// No description provided for @screenHide.
  ///
  /// In zh_Hant, this message translates to:
  /// **'隱藏'**
  String get screenHide;

  /// No description provided for @screenLock.
  ///
  /// In zh_Hant, this message translates to:
  /// **'鎖定'**
  String get screenLock;

  /// No description provided for @screenUnlock.
  ///
  /// In zh_Hant, this message translates to:
  /// **'解鎖'**
  String get screenUnlock;

  /// No description provided for @screenSound.
  ///
  /// In zh_Hant, this message translates to:
  /// **'聲音'**
  String get screenSound;

  /// No description provided for @screenBackToScreen.
  ///
  /// In zh_Hant, this message translates to:
  /// **'螢幕設定'**
  String get screenBackToScreen;

  /// No description provided for @screenMaterialName.
  ///
  /// In zh_Hant, this message translates to:
  /// **'素材名稱'**
  String get screenMaterialName;

  /// No description provided for @screenDuplicate.
  ///
  /// In zh_Hant, this message translates to:
  /// **'複製為獨立素材'**
  String get screenDuplicate;

  /// No description provided for @screenDeleteLayer.
  ///
  /// In zh_Hant, this message translates to:
  /// **'刪除圖層'**
  String get screenDeleteLayer;

  /// No description provided for @screenAddLayer.
  ///
  /// In zh_Hant, this message translates to:
  /// **'新增圖層'**
  String get screenAddLayer;

  /// No description provided for @screenDeleteMaterial.
  ///
  /// In zh_Hant, this message translates to:
  /// **'刪除素材'**
  String get screenDeleteMaterial;

  /// No description provided for @screenSectionLyric.
  ///
  /// In zh_Hant, this message translates to:
  /// **'歌詞'**
  String get screenSectionLyric;

  /// No description provided for @screenFollowNow.
  ///
  /// In zh_Hant, this message translates to:
  /// **'跟隨目前播放'**
  String get screenFollowNow;

  /// No description provided for @screenOverlayAbove.
  ///
  /// In zh_Hant, this message translates to:
  /// **'疊在歌詞上方'**
  String get screenOverlayAbove;

  /// No description provided for @screenLineCount.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{count} 行'**
  String screenLineCount(int count);

  /// No description provided for @screenTimeOffset.
  ///
  /// In zh_Hant, this message translates to:
  /// **'時間偏移'**
  String get screenTimeOffset;

  /// No description provided for @screenLyricNoBgNote.
  ///
  /// In zh_Hant, this message translates to:
  /// **'歌詞不帶底色。要背景就把圖片或影片拉到滿版、鎖定、放最底層。'**
  String get screenLyricNoBgNote;

  /// No description provided for @screenSectionUrl.
  ///
  /// In zh_Hant, this message translates to:
  /// **'網址'**
  String get screenSectionUrl;

  /// No description provided for @screenEmbedPage.
  ///
  /// In zh_Hant, this message translates to:
  /// **'嵌入網頁'**
  String get screenEmbedPage;

  /// No description provided for @screenUrlPlaceholder.
  ///
  /// In zh_Hant, this message translates to:
  /// **'https://…'**
  String get screenUrlPlaceholder;

  /// No description provided for @screenUrlReloadHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'改網址或按重新載入才會刷新。'**
  String get screenUrlReloadHint;

  /// No description provided for @screenReload.
  ///
  /// In zh_Hant, this message translates to:
  /// **'重新載入'**
  String get screenReload;

  /// No description provided for @screenRefresh.
  ///
  /// In zh_Hant, this message translates to:
  /// **'刷新間隔'**
  String get screenRefresh;

  /// No description provided for @screenSeconds.
  ///
  /// In zh_Hant, this message translates to:
  /// **'秒'**
  String get screenSeconds;

  /// No description provided for @screenUrlEmbedNote.
  ///
  /// In zh_Hant, this message translates to:
  /// **'對方網站若禁止嵌入（X-Frame-Options / CSP），畫面會空白；可改用圖片或影片素材。'**
  String get screenUrlEmbedNote;

  /// No description provided for @screenUrlPreviewHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'投放時在這裡顯示網頁'**
  String get screenUrlPreviewHint;

  /// No description provided for @screenScreenSound.
  ///
  /// In zh_Hant, this message translates to:
  /// **'本屏聲音'**
  String get screenScreenSound;

  /// No description provided for @screenVolume.
  ///
  /// In zh_Hant, this message translates to:
  /// **'音量'**
  String get screenVolume;

  /// No description provided for @screenSource.
  ///
  /// In zh_Hant, this message translates to:
  /// **'來源'**
  String get screenSource;

  /// No description provided for @screenStaticContent.
  ///
  /// In zh_Hant, this message translates to:
  /// **'靜態內容'**
  String get screenStaticContent;

  /// No description provided for @screenSectionImage.
  ///
  /// In zh_Hant, this message translates to:
  /// **'圖片'**
  String get screenSectionImage;

  /// No description provided for @screenSectionVideo.
  ///
  /// In zh_Hant, this message translates to:
  /// **'影片'**
  String get screenSectionVideo;

  /// No description provided for @screenSectionText.
  ///
  /// In zh_Hant, this message translates to:
  /// **'文字'**
  String get screenSectionText;

  /// No description provided for @screenSectionSound.
  ///
  /// In zh_Hant, this message translates to:
  /// **'本屏播放'**
  String get screenSectionSound;

  /// No description provided for @screenLocalFile.
  ///
  /// In zh_Hant, this message translates to:
  /// **'本機檔案'**
  String get screenLocalFile;

  /// No description provided for @screenUrlSource.
  ///
  /// In zh_Hant, this message translates to:
  /// **'圖片網址'**
  String get screenUrlSource;

  /// No description provided for @screenImageUrl.
  ///
  /// In zh_Hant, this message translates to:
  /// **'圖片網址'**
  String get screenImageUrl;

  /// No description provided for @screenVideoUrl.
  ///
  /// In zh_Hant, this message translates to:
  /// **'影片網址'**
  String get screenVideoUrl;

  /// No description provided for @screenFilePath.
  ///
  /// In zh_Hant, this message translates to:
  /// **'檔案路徑'**
  String get screenFilePath;

  /// No description provided for @screenImageUrlPlaceholder.
  ///
  /// In zh_Hant, this message translates to:
  /// **'https://…/photo.jpg'**
  String get screenImageUrlPlaceholder;

  /// No description provided for @screenImagePathPlaceholder.
  ///
  /// In zh_Hant, this message translates to:
  /// **'選擇本機圖片…'**
  String get screenImagePathPlaceholder;

  /// No description provided for @screenVideoUrlPlaceholder.
  ///
  /// In zh_Hant, this message translates to:
  /// **'https://…/clip.mp4'**
  String get screenVideoUrlPlaceholder;

  /// No description provided for @screenVideoPathPlaceholder.
  ///
  /// In zh_Hant, this message translates to:
  /// **'選擇本機影片…'**
  String get screenVideoPathPlaceholder;

  /// No description provided for @screenFill.
  ///
  /// In zh_Hant, this message translates to:
  /// **'填充'**
  String get screenFill;

  /// No description provided for @screenFitStretch.
  ///
  /// In zh_Hant, this message translates to:
  /// **'拉伸'**
  String get screenFitStretch;

  /// No description provided for @screenRadius.
  ///
  /// In zh_Hant, this message translates to:
  /// **'圓角'**
  String get screenRadius;

  /// No description provided for @screenLoop.
  ///
  /// In zh_Hant, this message translates to:
  /// **'循環播放'**
  String get screenLoop;

  /// No description provided for @screenPlayOnce.
  ///
  /// In zh_Hant, this message translates to:
  /// **'單次'**
  String get screenPlayOnce;

  /// No description provided for @screenAutoplay.
  ///
  /// In zh_Hant, this message translates to:
  /// **'自動播放'**
  String get screenAutoplay;

  /// No description provided for @screenMuted.
  ///
  /// In zh_Hant, this message translates to:
  /// **'靜音'**
  String get screenMuted;

  /// No description provided for @screenMuteOthersNote.
  ///
  /// In zh_Hant, this message translates to:
  /// **'同一屏只保留一路有聲；開啟時其他素材會自動靜音。'**
  String get screenMuteOthersNote;

  /// No description provided for @screenImageBgNote.
  ///
  /// In zh_Hant, this message translates to:
  /// **'全屏背景照樣用圖片做：拉到滿版、放到最底層、鎖定圖層即可。'**
  String get screenImageBgNote;

  /// No description provided for @screenTextPlaceholder.
  ///
  /// In zh_Hant, this message translates to:
  /// **'輸入文字…'**
  String get screenTextPlaceholder;

  /// No description provided for @screenTextNote.
  ///
  /// In zh_Hant, this message translates to:
  /// **'文字本身沒有背景；需要底色或壓暗時，在下面加一個圖片或影片圖層。'**
  String get screenTextNote;

  /// No description provided for @screenColor.
  ///
  /// In zh_Hant, this message translates to:
  /// **'顏色'**
  String get screenColor;

  /// No description provided for @screenGeometry.
  ///
  /// In zh_Hant, this message translates to:
  /// **'位置與層級'**
  String get screenGeometry;

  /// No description provided for @screenOpacity.
  ///
  /// In zh_Hant, this message translates to:
  /// **'不透明度'**
  String get screenOpacity;

  /// No description provided for @screenZOrder.
  ///
  /// In zh_Hant, this message translates to:
  /// **'層級'**
  String get screenZOrder;

  /// No description provided for @screenZTop.
  ///
  /// In zh_Hant, this message translates to:
  /// **'置頂'**
  String get screenZTop;

  /// No description provided for @screenZUp.
  ///
  /// In zh_Hant, this message translates to:
  /// **'上移一層'**
  String get screenZUp;

  /// No description provided for @screenZDown.
  ///
  /// In zh_Hant, this message translates to:
  /// **'下移一層'**
  String get screenZDown;

  /// No description provided for @screenZBottom.
  ///
  /// In zh_Hant, this message translates to:
  /// **'置底'**
  String get screenZBottom;

  /// No description provided for @screenShownOn.
  ///
  /// In zh_Hant, this message translates to:
  /// **'顯示於'**
  String get screenShownOn;

  /// No description provided for @screenLockLayer.
  ///
  /// In zh_Hant, this message translates to:
  /// **'鎖定圖層'**
  String get screenLockLayer;

  /// No description provided for @screenSharedNote.
  ///
  /// In zh_Hant, this message translates to:
  /// **'樣式與內容同步到共用此素材的螢幕；位置、透明度、層級與本屏聲音各自獨立。'**
  String get screenSharedNote;

  /// No description provided for @screenCanvasColor.
  ///
  /// In zh_Hant, this message translates to:
  /// **'畫布底色'**
  String get screenCanvasColor;

  /// No description provided for @screenTransparent.
  ///
  /// In zh_Hant, this message translates to:
  /// **'透明'**
  String get screenTransparent;

  /// No description provided for @screenBlack.
  ///
  /// In zh_Hant, this message translates to:
  /// **'純黑'**
  String get screenBlack;

  /// No description provided for @screenMidnight.
  ///
  /// In zh_Hant, this message translates to:
  /// **'午夜'**
  String get screenMidnight;

  /// No description provided for @screenLightCanvas.
  ///
  /// In zh_Hant, this message translates to:
  /// **'淺色'**
  String get screenLightCanvas;

  /// No description provided for @screenCustomColor.
  ///
  /// In zh_Hant, this message translates to:
  /// **'自訂顏色'**
  String get screenCustomColor;

  /// No description provided for @screenCanvasNote.
  ///
  /// In zh_Hant, this message translates to:
  /// **'透明會讓桌面透出來；選顏色則鋪一層不透明底色。'**
  String get screenCanvasNote;

  /// No description provided for @screenCast.
  ///
  /// In zh_Hant, this message translates to:
  /// **'投放'**
  String get screenCast;

  /// No description provided for @screenCastThisScreen.
  ///
  /// In zh_Hant, this message translates to:
  /// **'投放這塊螢幕'**
  String get screenCastThisScreen;

  /// No description provided for @screenCoverage.
  ///
  /// In zh_Hant, this message translates to:
  /// **'覆蓋範圍'**
  String get screenCoverage;

  /// No description provided for @screenFull.
  ///
  /// In zh_Hant, this message translates to:
  /// **'整屏'**
  String get screenFull;

  /// No description provided for @screenWork.
  ///
  /// In zh_Hant, this message translates to:
  /// **'工作區'**
  String get screenWork;

  /// No description provided for @screenPerformance.
  ///
  /// In zh_Hant, this message translates to:
  /// **'效能'**
  String get screenPerformance;

  /// No description provided for @screenPerfLayers.
  ///
  /// In zh_Hant, this message translates to:
  /// **'圖層'**
  String get screenPerfLayers;

  /// No description provided for @screenPerfUrls.
  ///
  /// In zh_Hant, this message translates to:
  /// **'網頁'**
  String get screenPerfUrls;

  /// No description provided for @screenPerfVideos.
  ///
  /// In zh_Hant, this message translates to:
  /// **'影片'**
  String get screenPerfVideos;

  /// No description provided for @screenPerfAudio.
  ///
  /// In zh_Hant, this message translates to:
  /// **'有聲'**
  String get screenPerfAudio;

  /// No description provided for @screenPerfHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'網頁與影片每多一路，CPU/GPU 與記憶體都會明顯上升；同屏各留一個最穩。'**
  String get screenPerfHint;

  /// No description provided for @screenTips.
  ///
  /// In zh_Hant, this message translates to:
  /// **'小提示'**
  String get screenTips;

  /// No description provided for @screenTipsText.
  ///
  /// In zh_Hant, this message translates to:
  /// **'拖動素材移動、拖八個角縮放；方向鍵微調（Shift ×10），Delete 刪除，Esc 取消選取。'**
  String get screenTipsText;

  /// No description provided for @screenSoundFollowsScreen.
  ///
  /// In zh_Hant, this message translates to:
  /// **'聲音跟屏走'**
  String get screenSoundFollowsScreen;

  /// No description provided for @screenEmptyMaterial.
  ///
  /// In zh_Hant, this message translates to:
  /// **'還沒設定內容'**
  String get screenEmptyMaterial;

  /// No description provided for @screenPickImage.
  ///
  /// In zh_Hant, this message translates to:
  /// **'選擇圖片'**
  String get screenPickImage;

  /// No description provided for @screenPickVideo.
  ///
  /// In zh_Hant, this message translates to:
  /// **'選擇影片'**
  String get screenPickVideo;

  /// No description provided for @screenNoVideos.
  ///
  /// In zh_Hant, this message translates to:
  /// **'這個資料夾下沒有影片檔案（mp4/webm/mov/mkv/avi/m4v/ogv）'**
  String get screenNoVideos;

  /// No description provided for @screenTagLight.
  ///
  /// In zh_Hant, this message translates to:
  /// **'輕量'**
  String get screenTagLight;

  /// No description provided for @screenTagNormal.
  ///
  /// In zh_Hant, this message translates to:
  /// **'普通'**
  String get screenTagNormal;

  /// No description provided for @screenTagHeavy.
  ///
  /// In zh_Hant, this message translates to:
  /// **'較重'**
  String get screenTagHeavy;

  /// No description provided for @screenTypeLyric.
  ///
  /// In zh_Hant, this message translates to:
  /// **'歌詞'**
  String get screenTypeLyric;

  /// No description provided for @screenTypeLyricDesc.
  ///
  /// In zh_Hant, this message translates to:
  /// **'跟隨播放的即時歌詞'**
  String get screenTypeLyricDesc;

  /// No description provided for @screenTypeUrl.
  ///
  /// In zh_Hant, this message translates to:
  /// **'網址'**
  String get screenTypeUrl;

  /// No description provided for @screenTypeUrlDesc.
  ///
  /// In zh_Hant, this message translates to:
  /// **'嵌入一個網頁'**
  String get screenTypeUrlDesc;

  /// No description provided for @screenTypeImage.
  ///
  /// In zh_Hant, this message translates to:
  /// **'圖片'**
  String get screenTypeImage;

  /// No description provided for @screenTypeImageDesc.
  ///
  /// In zh_Hant, this message translates to:
  /// **'本機檔案或圖片網址'**
  String get screenTypeImageDesc;

  /// No description provided for @screenTypeVideo.
  ///
  /// In zh_Hant, this message translates to:
  /// **'影片'**
  String get screenTypeVideo;

  /// No description provided for @screenTypeVideoDesc.
  ///
  /// In zh_Hant, this message translates to:
  /// **'本機或網絡影片，可帶聲音'**
  String get screenTypeVideoDesc;

  /// No description provided for @screenTypeText.
  ///
  /// In zh_Hant, this message translates to:
  /// **'文字'**
  String get screenTypeText;

  /// No description provided for @screenTypeTextDesc.
  ///
  /// In zh_Hant, this message translates to:
  /// **'靜態文字'**
  String get screenTypeTextDesc;

  /// No description provided for @sourcesTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'音源'**
  String get sourcesTitle;

  /// No description provided for @sourcesTotal.
  ///
  /// In zh_Hant, this message translates to:
  /// **'曲庫共 {count} 首'**
  String sourcesTotal(int count);

  /// No description provided for @sourcesSummary.
  ///
  /// In zh_Hant, this message translates to:
  /// **'本地 {local} 首 · WebDAV {webdav} 首'**
  String sourcesSummary(int local, int webdav);

  /// No description provided for @manageSources.
  ///
  /// In zh_Hant, this message translates to:
  /// **'管理'**
  String get manageSources;

  /// No description provided for @localSourceTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'本地音源'**
  String get localSourceTitle;

  /// No description provided for @webdavSourceTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'WebDAV 音源'**
  String get webdavSourceTitle;

  /// No description provided for @webdavCount.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{count} 個'**
  String webdavCount(int count);

  /// No description provided for @webdavEmptyTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'還沒有 WebDAV 音源'**
  String get webdavEmptyTitle;

  /// No description provided for @webdavEmptyHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'連接 NAS 或任意 WebDAV 服務，掃描後與本地曲庫一起參與點歌'**
  String get webdavEmptyHint;

  /// No description provided for @webdavAdd.
  ///
  /// In zh_Hant, this message translates to:
  /// **'新增'**
  String get webdavAdd;

  /// No description provided for @webdavAddTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'新增 WebDAV 音源'**
  String get webdavAddTitle;

  /// No description provided for @webdavEditTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'編輯 WebDAV 音源'**
  String get webdavEditTitle;

  /// No description provided for @webdavName.
  ///
  /// In zh_Hant, this message translates to:
  /// **'名稱'**
  String get webdavName;

  /// No description provided for @webdavUrl.
  ///
  /// In zh_Hant, this message translates to:
  /// **'伺服器位址'**
  String get webdavUrl;

  /// No description provided for @webdavUsername.
  ///
  /// In zh_Hant, this message translates to:
  /// **'使用者名稱'**
  String get webdavUsername;

  /// No description provided for @webdavPassword.
  ///
  /// In zh_Hant, this message translates to:
  /// **'密碼'**
  String get webdavPassword;

  /// No description provided for @webdavAllowSelfSigned.
  ///
  /// In zh_Hant, this message translates to:
  /// **'允許自簽章憑證（NAS 常用）'**
  String get webdavAllowSelfSigned;

  /// No description provided for @webdavDialogHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'連線資訊只保存在本機；掃描後可像本地曲庫一樣檢索、點歌和投放。'**
  String get webdavDialogHint;

  /// No description provided for @webdavTest.
  ///
  /// In zh_Hant, this message translates to:
  /// **'測試連線'**
  String get webdavTest;

  /// No description provided for @webdavSaveAndScan.
  ///
  /// In zh_Hant, this message translates to:
  /// **'儲存並掃描'**
  String get webdavSaveAndScan;

  /// No description provided for @webdavSync.
  ///
  /// In zh_Hant, this message translates to:
  /// **'同步'**
  String get webdavSync;

  /// No description provided for @webdavSyncing.
  ///
  /// In zh_Hant, this message translates to:
  /// **'同步中…'**
  String get webdavSyncing;

  /// No description provided for @webdavNeverSynced.
  ///
  /// In zh_Hant, this message translates to:
  /// **'尚未同步'**
  String get webdavNeverSynced;

  /// No description provided for @webdavEdit.
  ///
  /// In zh_Hant, this message translates to:
  /// **'編輯'**
  String get webdavEdit;

  /// No description provided for @webdavDelete.
  ///
  /// In zh_Hant, this message translates to:
  /// **'刪除'**
  String get webdavDelete;

  /// No description provided for @webdavMore.
  ///
  /// In zh_Hant, this message translates to:
  /// **'更多'**
  String get webdavMore;

  /// No description provided for @webdavDeleteConfirm.
  ///
  /// In zh_Hant, this message translates to:
  /// **'刪除「{name}」？'**
  String webdavDeleteConfirm(String name);

  /// No description provided for @webdavInvalidUrl.
  ///
  /// In zh_Hant, this message translates to:
  /// **'伺服器位址需以 http(s):// 開頭'**
  String get webdavInvalidUrl;

  /// No description provided for @webdavNeedUrl.
  ///
  /// In zh_Hant, this message translates to:
  /// **'請先填寫伺服器位址'**
  String get webdavNeedUrl;

  /// No description provided for @webdavNeedName.
  ///
  /// In zh_Hant, this message translates to:
  /// **'請先填寫名稱'**
  String get webdavNeedName;

  /// No description provided for @webdavTestOk.
  ///
  /// In zh_Hant, this message translates to:
  /// **'連線正常，根目錄有 {count} 個項目'**
  String webdavTestOk(int count);

  /// No description provided for @webdavTestFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'連線失敗：{error}'**
  String webdavTestFailed(String error);

  /// No description provided for @webdavAuthFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'認證失敗（HTTP {status}）'**
  String webdavAuthFailed(int status);

  /// No description provided for @webdavHttpError.
  ///
  /// In zh_Hant, this message translates to:
  /// **'伺服器回應 HTTP {status}'**
  String webdavHttpError(int status);

  /// No description provided for @webdavConnectFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'連線失敗：{detail}'**
  String webdavConnectFailed(String detail);

  /// No description provided for @webdavTlsFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'憑證校驗失敗，可允許自簽章憑證：{detail}'**
  String webdavTlsFailed(String detail);

  /// No description provided for @webdavTimeout.
  ///
  /// In zh_Hant, this message translates to:
  /// **'連線逾時'**
  String get webdavTimeout;

  /// No description provided for @webdavInvalidXml.
  ///
  /// In zh_Hant, this message translates to:
  /// **'無法解析 WebDAV 回應'**
  String get webdavInvalidXml;

  /// No description provided for @webdavNotDav.
  ///
  /// In zh_Hant, this message translates to:
  /// **'這個位址不是 WebDAV 服務'**
  String get webdavNotDav;

  /// No description provided for @webdavNotFound.
  ///
  /// In zh_Hant, this message translates to:
  /// **'遠端資料夾不存在'**
  String get webdavNotFound;

  /// No description provided for @webdavPartialFolders.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{count} 個資料夾讀取失敗，已同步其餘曲目'**
  String webdavPartialFolders(int count);

  /// No description provided for @webdavFileUnavailable.
  ///
  /// In zh_Hant, this message translates to:
  /// **'遠端檔案不可用：{name}'**
  String webdavFileUnavailable(String name);

  /// No description provided for @webdavSyncedAt.
  ///
  /// In zh_Hant, this message translates to:
  /// **'同步於 {time}'**
  String webdavSyncedAt(String time);

  /// No description provided for @webdavLastScanned.
  ///
  /// In zh_Hant, this message translates to:
  /// **'上次掃描 {time}'**
  String webdavLastScanned(String time);

  /// No description provided for @webdavSyncProgress.
  ///
  /// In zh_Hant, this message translates to:
  /// **'已發現 {tracks} 首 · {folders} 個資料夾'**
  String webdavSyncProgress(int tracks, int folders);

  /// No description provided for @webdavTesting.
  ///
  /// In zh_Hant, this message translates to:
  /// **'測試中…'**
  String get webdavTesting;

  /// No description provided for @webdavSaving.
  ///
  /// In zh_Hant, this message translates to:
  /// **'儲存中…'**
  String get webdavSaving;
}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  @override
  Future<AppL10n> load(Locale locale) {
    return SynchronousFuture<AppL10n>(lookupAppL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}

AppL10n lookupAppL10n(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hans':
            return AppL10nZhHans();
          case 'Hant':
            return AppL10nZhHant();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppL10nEn();
    case 'zh':
      return AppL10nZh();
  }

  throw FlutterError(
    'AppL10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
