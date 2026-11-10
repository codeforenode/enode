// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_l10n.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppL10nEn extends AppL10n {
  AppL10nEn([String locale = 'en']) : super(locale);

  @override
  String get settingsTitle => 'Settings';

  @override
  String get done => 'Done';

  @override
  String get close => 'Close';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get delete => 'Delete';

  @override
  String get notSet => 'Not set';

  @override
  String get notAssigned => 'Unassigned';

  @override
  String get tabDisplay => 'Display';

  @override
  String get tabBroadcast => 'Broadcast';

  @override
  String get tabSources => 'Sources';

  @override
  String get tabCast => 'Screens';

  @override
  String get tabAbout => 'About';

  @override
  String get theme => 'Theme';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';

  @override
  String get themeSystem => 'System';

  @override
  String get themeSystemHint => '\"System\" follows the device\'s dark mode.';

  @override
  String get textSize => 'Text size';

  @override
  String get textSizeSmall => 'Small';

  @override
  String get textSizeMedium => 'Medium';

  @override
  String get textSizeLarge => 'Large';

  @override
  String get textSizeXLarge => 'Extra large';

  @override
  String get displayPrefsHint =>
      'Display preferences are saved on this device.';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get languageSimplifiedChinese => '简体中文';

  @override
  String get languageTraditionalChinese => '繁體中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageHint =>
      'Simplified or Traditional Chinese follows the system script; other languages use English.';

  @override
  String get aboutVersionNode => 'Version & node';

  @override
  String get aboutVersion => 'Version';

  @override
  String get aboutNodeId => 'Node ID';

  @override
  String get aboutConnection => 'Connection';

  @override
  String get aboutLibraryDir => 'Library folder';

  @override
  String get aboutOpenSource => 'Open source';

  @override
  String get aboutLicense => 'License';

  @override
  String get aboutViewLicenses => 'View licenses & third-party notices';

  @override
  String get aboutOpenSourceHint =>
      'Licensed under AGPL-3.0. Third-party components include CEF (BSD-3) and libmpv/FFmpeg (LGPL-2.1-or-later); see the license page for the full list.';

  @override
  String get aboutSourceCode => 'Source code';

  @override
  String get aboutSourceCopied => 'Source URL copied';

  @override
  String get settingsTooltip => 'Settings';

  @override
  String get trayOpen => 'Open eNode';

  @override
  String get trayAutostart => 'Start with Windows';

  @override
  String get trayQuit => 'Quit';

  @override
  String get exitTitle => 'Quit the app?';

  @override
  String get mqttNotConfigured => 'MQTT not configured';

  @override
  String get mqttInvalidConfig => 'Invalid MQTT settings';

  @override
  String get mqttConnected => 'MQTT connected';

  @override
  String get mqttConnecting => 'MQTT connecting';

  @override
  String get mqttFailed => 'MQTT connection failed';

  @override
  String get mqttDisconnected => 'MQTT not connected';

  @override
  String get nowPlaying => 'Now playing';

  @override
  String get queueEmpty => 'Queue is empty';

  @override
  String queuePosition(int total) {
    return '1 / $total';
  }

  @override
  String get addedHere => 'Added here';

  @override
  String fromGuest(String seat) {
    return 'Guest · $seat';
  }

  @override
  String timeLeft(String time) {
    return '$time left';
  }

  @override
  String get volume => 'Volume';

  @override
  String get queue => 'Queue';

  @override
  String queueLimit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs / limit 200',
      one: '1 song / limit 200',
    );
    return '$_temp0';
  }

  @override
  String moveToPosition(String title, int position) {
    return 'Move \"$title\" to position $position?';
  }

  @override
  String get playingNow => 'Playing';

  @override
  String get paused => 'Paused';

  @override
  String get removeFromQueue => 'Remove from queue';

  @override
  String get library => 'Library';

  @override
  String trackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs',
      one: '1 song',
    );
    return '$_temp0';
  }

  @override
  String missingCount(int count) {
    return '$count missing';
  }

  @override
  String scanProgress(int scanned, int total) {
    return 'Scanning $scanned / $total';
  }

  @override
  String get demoLibrary => 'Demo library';

  @override
  String get libraryReady => 'Ready';

  @override
  String get noRealFolder => 'No real folder';

  @override
  String get noFolder => 'No folder set';

  @override
  String get scanning => 'Scanning…';

  @override
  String get scan => 'Scan';

  @override
  String get rescan => 'Rescan';

  @override
  String get folder => 'Folder';

  @override
  String get changeFolder => 'Change folder';

  @override
  String get grantAccess => 'Grant access';

  @override
  String get systemSettings => 'System settings';

  @override
  String get dirUnreadable =>
      'Can\'t read this folder. Storage permission may be missing.';

  @override
  String get chooseLibraryFolder => 'Choose library folder';

  @override
  String get parentFolder => 'Up';

  @override
  String get chooseFolderHint =>
      'This folder is rescanned right away, including subfolders.';

  @override
  String get chooseThisFolder => 'Use this folder';

  @override
  String get openStorageSettings => 'Open system settings';

  @override
  String get noSubfolders => 'No subfolders here; you can use this folder.';

  @override
  String get imageDirUnreadable => 'Can\'t read this folder';

  @override
  String get chooseBackgroundImage => 'Choose background image';

  @override
  String get pastePathHint =>
      'You can also paste a path, e.g. D:\\pics\\stage.png';

  @override
  String get imagePathNote =>
      'Only the local absolute path is stored; nothing is copied or indexed.';

  @override
  String get useThisPath => 'Use this path';

  @override
  String imageDirError(String error) {
    return '$error — try another folder, or paste a path below';
  }

  @override
  String get noImages => 'No images in this folder (png/jpg/jpeg/webp/bmp/gif)';

  @override
  String get mqttIntro =>
      'Paste the whole connection block; broker, port, username and password are detected automatically.';

  @override
  String get mqttIntroUnconfigured =>
      'MQTT isn\'t configured yet. Paste the connection block from the relay; it connects as soon as it\'s recognized.';

  @override
  String get mqttPasteHint =>
      'mqtt://user:password@host:1883\nor: host / port / username / password on separate lines';

  @override
  String get mqttApplying => 'Applying…';

  @override
  String get mqttApply => 'Parse & apply';

  @override
  String get mqttClear => 'Clear this device\'s settings';

  @override
  String get mqttActive => 'Active';

  @override
  String get mqttNotConfiguredShort => 'Not configured';

  @override
  String get mqttAnonymous => 'Anonymous';

  @override
  String mqttPasswordMasked(int length) {
    return '•••••• ($length chars)';
  }

  @override
  String get mqttTopicPrefix => 'Topic prefix';

  @override
  String get mqttLocalOnly =>
      'Settings are stored only on this device; passwords never go to logs.';

  @override
  String mqttApplied(String host, int port) {
    return 'Applied $host:$port';
  }

  @override
  String applyFailed(String error) {
    return 'Couldn\'t apply: $error';
  }

  @override
  String get mqttCleared => 'Cleared this device\'s settings';

  @override
  String clearFailed(String error) {
    return 'Couldn\'t clear: $error';
  }

  @override
  String get brokerAddress => 'Broker address';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get pasteEmpty => 'Paste the connection details first';

  @override
  String get pasteUnrecognized =>
      'Couldn\'t recognize that. Paste mqtt://user:password@host:port, or host/port/username/password on separate lines.';

  @override
  String get pasteMissingHost => 'JSON is missing \"host\" (broker address)';

  @override
  String get pasteNoWebsocket =>
      'ws/wss isn\'t supported yet; use mqtt://host:port';

  @override
  String get pasteBadHost => 'Invalid broker address';

  @override
  String get configHostRequired => 'Broker address is required';

  @override
  String get configPortRange => 'Port must be 1–65535';

  @override
  String get configTopicPrefix =>
      'Topic prefix can\'t be empty or contain #, + or spaces';

  @override
  String get configClientIdTooLong => 'Client ID is too long';

  @override
  String connectFailed(String error) {
    return 'Connection failed: $error';
  }

  @override
  String connectNotEstablished(String state) {
    return 'Connection not established ($state)';
  }

  @override
  String get connectionClosed => 'Connection closed';

  @override
  String publishFailed(String error) {
    return 'Publish failed: $error';
  }

  @override
  String get searchTimeout => 'Search timed out';

  @override
  String get permNoPermissionNeeded => 'No permission needed';

  @override
  String get permAllFiles => 'Granted (all files access)';

  @override
  String get permAudioOnly =>
      'Audio only; reading .lrc and scanning folders needs \"All files access\"';

  @override
  String get permNotGranted =>
      'Not granted: allow storage access in system settings';

  @override
  String folderMissing(String root) {
    return 'Folder not found: $root';
  }

  @override
  String folderUnreadable(String message) {
    return 'Can\'t read folder: $message';
  }

  @override
  String get unknownArtist => 'Unknown artist';

  @override
  String get lyricsEmpty => 'Lyrics are empty';

  @override
  String get noLyrics => 'No lyrics';

  @override
  String get castNoLyrics => 'No lyrics';

  @override
  String get onlineLibrary => 'Online library';

  @override
  String get localFolder => 'Local folder';

  @override
  String get demoNoLyrics => 'The demo track has no lyrics';

  @override
  String get unsupportedSearch => 'This source doesn\'t support search';

  @override
  String get unsupportedPlay => 'This source doesn\'t support playback';

  @override
  String get unsupportedLyrics => 'This source doesn\'t support lyrics';

  @override
  String get kugouSearchFailed => 'Kugou search failed';

  @override
  String get kugouMissingHash => 'Kugou track is missing a hash';

  @override
  String get kugouNoLyrics => 'No lyrics found on Kugou';

  @override
  String get kugouMissingCredential => 'Kugou lyrics are missing a token';

  @override
  String get kugouLyricsEmpty => 'Kugou lyrics are empty';

  @override
  String get kuwoSearchFailed => 'Kuwo search failed';

  @override
  String get kuwoNoLyrics => 'No lyrics on Kuwo';

  @override
  String get kuwoMissingId => 'Kuwo track is missing an ID';

  @override
  String get miguSearchFailed => 'Migu search failed';

  @override
  String get miguNoLyricUrl => 'Migu track has no lyrics URL';

  @override
  String get miguLyricsEmpty => 'Migu lyrics are empty';

  @override
  String get qqSearchFailed => 'QQ Music search failed';

  @override
  String get qqMissingMid => 'QQ Music track is missing a mid';

  @override
  String get qqNoLyrics => 'No lyrics on QQ Music';

  @override
  String get neteaseMissingId => 'NetEase track is missing an ID';

  @override
  String get neteaseNoLyrics => 'No lyrics on NetEase';

  @override
  String get lyricsDecodeFailed => 'Couldn\'t decode lyrics';

  @override
  String get httpBadJson => 'Response isn\'t valid JSON';

  @override
  String get httpRateLimited => 'Too many requests; try again later';

  @override
  String httpUnavailable(int status) {
    return 'Service unavailable (HTTP $status)';
  }

  @override
  String httpFailed(int status) {
    return 'Request failed (HTTP $status)';
  }

  @override
  String get httpTimeout => 'Network timed out';

  @override
  String get httpError => 'Network request failed';

  @override
  String get networkUnavailable => 'Network unavailable';

  @override
  String jsHostFailed(String detail) {
    return 'JS host init failed: $detail';
  }

  @override
  String scriptRunFailed(String detail) {
    return 'Script failed: $detail';
  }

  @override
  String get scriptNoInited => 'Script didn\'t send the \"inited\" event';

  @override
  String get scriptNoPlatforms => 'Script declares no music services';

  @override
  String get sourceNotInitialized => 'Source isn\'t initialized';

  @override
  String scriptCallFailed(String detail) {
    return 'Script call failed: $detail';
  }

  @override
  String get scriptNoResult => 'Script returned no result';

  @override
  String get scriptError => 'Script returned an error';

  @override
  String get scriptBadUrl => 'Script returned an invalid playback URL';

  @override
  String jsUnavailable(String error) {
    return 'JS engine unavailable: $error';
  }

  @override
  String get runtimeDisposed => 'Runtime has been disposed';

  @override
  String get scriptBadJson => 'Script returned invalid JSON';

  @override
  String get requestBadUrl => 'Invalid request URL';

  @override
  String get requestHttpOnly => 'Only http(s) requests are supported';

  @override
  String get requestNoMultipart => 'multipart requests aren\'t supported yet';

  @override
  String scriptTimeout(String what) {
    return '$what timed out';
  }

  @override
  String get scriptInit => 'Script init';

  @override
  String get playbackResolve => 'Playback URL resolve';

  @override
  String get trackNoPlatform => 'Track has no online source tag';

  @override
  String resolveFailed(String error) {
    return 'Couldn\'t resolve playback URL: $error';
  }

  @override
  String get resolveFailedShort => 'Couldn\'t resolve playback URL';

  @override
  String get noImportedScripts => 'No source scripts imported';

  @override
  String get noUsableScripts => 'No usable source scripts';

  @override
  String sourceResolveFailed(String detail) {
    return 'Source couldn\'t resolve the URL: $detail';
  }

  @override
  String lyricsFetchFailed(String error) {
    return 'Couldn\'t fetch lyrics: $error';
  }

  @override
  String get trackNoLyrics => 'This track has no lyrics';

  @override
  String get sourceUrlScheme => 'Source URL must start with http(s)://';

  @override
  String downloadFailed(int status) {
    return 'Download failed (HTTP $status)';
  }

  @override
  String get sourceInvalid =>
      'Not a valid source script (missing @name header)';

  @override
  String get downloadTimeout => 'Download timed out';

  @override
  String get sourceUnavailable => 'Source is unavailable';

  @override
  String get platformResolveUnsupported =>
      'This source can\'t resolve this track';

  @override
  String get sourceNotFound => 'Source not found';

  @override
  String get seatLocal => 'Local';

  @override
  String get localTag => 'Local';

  @override
  String scanFailed(String error) {
    return 'Scan failed: $error';
  }

  @override
  String probeReady(int ms) {
    return 'Ready · ${ms}ms';
  }

  @override
  String get probeNoResolve => ' · no resolver';

  @override
  String probeFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String get probeNoOnlineSource => 'No online source connected';

  @override
  String probeZero(int ms) {
    return '0 results · ${ms}ms';
  }

  @override
  String probeTracks(int count, int ms, int resolveMs, String host) {
    return '$count results · ${ms}ms · resolve ${resolveMs}ms ($host)';
  }

  @override
  String probeResolveFailed(int count, int ms, String error) {
    return '$count results · ${ms}ms · resolve failed: $error';
  }

  @override
  String get audioFormatUnsupported => 'Unsupported audio format';

  @override
  String get audioOpenFailed => 'Couldn\'t open the audio file';

  @override
  String skipResolveFailed(String title) {
    return 'Couldn\'t resolve \"$title\"; skipped';
  }

  @override
  String playOpenFailed(String title, String error) {
    return 'Couldn\'t play \"$title\": $error';
  }

  @override
  String skipUnplayable(String title) {
    return '\"$title\" can\'t be played; skipped';
  }

  @override
  String get castBgSolid => 'Solid black';

  @override
  String get castBgGradient => 'Vertical gradient';

  @override
  String get castBgCustom => 'Custom color';

  @override
  String get castBgImage => 'Image';

  @override
  String get castAlignLeft => 'Left';

  @override
  String get castAlignCenter => 'Center';

  @override
  String get castAlignRight => 'Right';

  @override
  String get onlineSourcesTitle => 'Online sources';

  @override
  String scriptCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count scripts',
      one: '1 script',
    );
    return '$_temp0';
  }

  @override
  String get sourcesIntro =>
      'Changes apply immediately; no separate save needed. Resolution tries each source below in order.';

  @override
  String get sourcesEmpty =>
      'No sources imported yet. Online playback needs at least one source script.';

  @override
  String get importHint =>
      'Paste a source script URL, e.g. https://.../source.js';

  @override
  String get importing => 'Importing…';

  @override
  String get importAction => 'Import';

  @override
  String importedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Imported and enabled · $count scripts',
      one: 'Imported and enabled · 1 script',
    );
    return '$_temp0';
  }

  @override
  String importFailedOnline(String error) {
    return 'Couldn\'t import: $error';
  }

  @override
  String saveFailed(String error) {
    return 'Couldn\'t save: $error';
  }

  @override
  String get needSourceUrl => 'Enter a source URL first';

  @override
  String get sourceEnabled => 'Enabled';

  @override
  String get sourceDisabled => 'Disabled';

  @override
  String get sourceOrderUpdated => 'Resolve order updated';

  @override
  String get sourceRemoved => 'Source deleted';

  @override
  String get qualityLabel => 'Quality';

  @override
  String get qualitySaved => 'Quality saved';

  @override
  String get restoreDefaults => 'Restore default quality';

  @override
  String get defaultsRestored => 'Quality restored to default';

  @override
  String statusError(String error) {
    return 'Error: $error';
  }

  @override
  String get moveUp => 'Move up';

  @override
  String get moveDown => 'Move down';

  @override
  String get testSourceTooltip => 'Test: script + search + resolve';

  @override
  String get checkSourceUpdate => 'Check for updates';

  @override
  String get sourceUpToDate => 'Already up to date';

  @override
  String sourceUpdateFound(String latest, String current) {
    return 'New $latest available · current $current';
  }

  @override
  String get sourceUpdateApply => 'Update';

  @override
  String get sourceUpdateDismiss => 'Dismiss';

  @override
  String sourceUpdated(String version) {
    return 'Updated to $version';
  }

  @override
  String get sourceUpdatedPlain => 'Source updated';

  @override
  String sourceNotice(String message) {
    return 'Source notice: $message';
  }

  @override
  String sourceNoticeLink(String url) {
    return 'Update link: $url';
  }

  @override
  String updateCheckFailed(String error) {
    return 'Update check failed: $error';
  }

  @override
  String get castTitle => 'Screen manager';

  @override
  String castSummary(int monitors, int windows) {
    return '$monitors screens · $windows cast windows';
  }

  @override
  String get castIntro =>
      'Each selected display opens a topmost click-through window. Style and clock exist once, so every screen stays in sync and edits apply instantly. Right-click a casting screen to close that screen or all casts.';

  @override
  String get castNoMonitors =>
      'No displays found (this can also be empty when screen_retriever is unavailable or there is only one screen). Connect the display and rescan.';

  @override
  String get castNoMonitorsFound => 'Still no displays found';

  @override
  String get castDetected => 'Detected';

  @override
  String castDetectedValue(int count) {
    return '$count';
  }

  @override
  String get castCasting => 'Casting';

  @override
  String castCastingValue(int count) {
    return '$count windows';
  }

  @override
  String get castOpen => 'Open';

  @override
  String castOpenValue(int count) {
    return '$count';
  }

  @override
  String get castMemory => 'Extra memory';

  @override
  String get castSync => 'Sync';

  @override
  String get castSyncValue => 'One canvas · same frame';

  @override
  String get castEnable => 'Enable casting';

  @override
  String castEnabledHint(int count) {
    return '$count cast windows are open; clicks pass through and they close when the app exits.';
  }

  @override
  String get castDisabledHint =>
      'When off, only this preview runs; selected screens stay empty.';

  @override
  String get castTargetsTitle => 'Cast targets';

  @override
  String get castMultiSelect => 'Multi-select';

  @override
  String get castTargetsHint =>
      'Only selected screens appear in the map and preview below.';

  @override
  String castMonitorLabel(int index, String name) {
    return 'Display $index · $name';
  }

  @override
  String castMonitorSpec(
    int fullW,
    int fullH,
    int workW,
    int workH,
    int scale,
  ) {
    return 'Full $fullW×$fullH · Work area $workW×$workH · Scale $scale%';
  }

  @override
  String get castFullscreen => 'Full screen';

  @override
  String get castRegion => 'Region';

  @override
  String get castEditing => 'Editing';

  @override
  String get castEditScreen => 'Edit this screen';

  @override
  String get castRegionTitle => 'Region';

  @override
  String get castNoSelection =>
      'No screen selected yet — pick one above and only that screen appears here.';

  @override
  String get castPresetBottomStrip => 'Bottom subtitle strip';

  @override
  String get castPresetLowerHalf => 'Lower half';

  @override
  String get castPresetCenterStrip => 'Centered strip';

  @override
  String get castMapHint =>
      'Drag on the map: move inside the box, resize with the eight handles, or drag empty space to redraw.';

  @override
  String get castMoveLeft => 'Move left';

  @override
  String get castMoveUp => 'Move up';

  @override
  String get castMoveDown => 'Move down';

  @override
  String get castMoveRight => 'Move right';

  @override
  String get castCenterH => 'Center horizontally';

  @override
  String get castCenterV => 'Center vertically';

  @override
  String get castLeftPx => 'Left (px)';

  @override
  String get castTopPx => 'Top (px)';

  @override
  String get castWidthPx => 'Width (px)';

  @override
  String get castHeightPx => 'Height (px)';

  @override
  String castPercentSummary(
    String left,
    String top,
    String width,
    String height,
    int workW,
    int workH,
  ) {
    return 'Stored as $left/$top · $width×$height · work area $workW×$workH logical px';
  }

  @override
  String get castStyleTitle => 'Lyric style';

  @override
  String get castLines => 'Lines shown';

  @override
  String get castLinesCurrent => 'Current line only';

  @override
  String get castLinesPrev => 'Previous + current';

  @override
  String get castLinesBoth => 'Previous + current + next';

  @override
  String get castFont => 'Font';

  @override
  String get castFontSize => 'Size';

  @override
  String get castFontSizeUnit => 'px (scaled to 1080 height)';

  @override
  String get castLineGap => 'Line gap';

  @override
  String get castTextWidth => 'Text width';

  @override
  String get castTextHeight => 'Text height';

  @override
  String get castWeight => 'Weight';

  @override
  String get castWeightRegular => '400 Regular';

  @override
  String get castWeightMedium => '500 Medium';

  @override
  String get castWeightSemibold => '600 Semibold';

  @override
  String get castWeightBold => '700 Bold';

  @override
  String get castStroke => 'Outline';

  @override
  String get castStrokeUnit =>
      'px (black outline over background images and video)';

  @override
  String get castShadow => 'Shadow';

  @override
  String get castCurrentColor => 'Current lyric color';

  @override
  String get castOtherColor => 'Non-current lyric color';

  @override
  String get castOtherOpacity => 'Non-current row opacity';

  @override
  String get castKaraokeColorHint =>
      'Word-by-word: sung words use the current lyric color, unsung words use the non-current color.';

  @override
  String get castBackground => 'Cast background';

  @override
  String get castGradientTop => 'Gradient top';

  @override
  String get castGradientBottom => 'Gradient bottom';

  @override
  String get castSolidColor => 'Background color';

  @override
  String get castNoImage => 'No image selected';

  @override
  String get castBrowse => 'Browse…';

  @override
  String get castClear => 'Clear';

  @override
  String get castImageFit => 'Image fit';

  @override
  String get castFitCover => 'Cover';

  @override
  String get castFitContain => 'Contain';

  @override
  String get castAlign => 'Horizontal align';

  @override
  String get castVertical => 'Vertical position';

  @override
  String get castVerticalUnit => '% (0 = top, lyric block center)';

  @override
  String get castOffset => 'Lyric offset';

  @override
  String get castOffsetUnit => 'ms (positive delays lyrics)';

  @override
  String get castExtras => 'Extra info';

  @override
  String get castShowTitle => 'Title';

  @override
  String get castShowArtist => 'Artist';

  @override
  String get castShowSeat => 'Seat';

  @override
  String get castPreview => 'Preview';

  @override
  String get castLiveBadge => 'Following playback';

  @override
  String get castDemoBadge => 'Demo lyrics';

  @override
  String get castPause => 'Pause';

  @override
  String get castPlay => 'Play';

  @override
  String get castPickScreen => 'Select a screen to preview the actual output.';

  @override
  String get castPreviewLiveHint =>
      'Preview uses this screen\'s cast area ratio; the cast window draws with the same code.';

  @override
  String get castPreviewDemoHint =>
      'Not playing, so demo lyrics run; they switch to real lyrics once playback starts.';

  @override
  String get castPickColor => 'Pick a color';

  @override
  String get castColorHint =>
      '#RRGGBB or #AARRGGBB; A is the text\'s own opacity.';

  @override
  String get castDemoTitle => 'Evening Breeze';

  @override
  String get castDemoArtist => 'Demo artist';

  @override
  String get castFontYaHei => 'Microsoft YaHei';

  @override
  String get castFontHei => 'SimHei';

  @override
  String get castFontSong => 'SimSun';

  @override
  String get castFontKai => 'KaiTi';

  @override
  String get castFontDeng => 'DengXian';

  @override
  String fileMissing(String path) {
    return 'File not found: $path';
  }

  @override
  String castWindowTitle(String name) {
    return 'eNode Lyrics · $name';
  }

  @override
  String get castRuntimeMissing => 'Could not start the Chromium runtime';

  @override
  String get castRegionZero => 'Cast region has zero size';

  @override
  String get castNoBrowserHandle =>
      'The canvas browser did not return a handle';

  @override
  String get castNoPresenter =>
      'The canvas has no visible presenter (GPU acceleration required)';

  @override
  String castCanvasFallback(String error) {
    return 'Canvas casting failed, falling back to one window per screen: $error';
  }

  @override
  String castWindowTimeout(String name) {
    return 'The cast window for $name did not start within 12 seconds — a GPU driver or security software may be blocking the extra engine';
  }

  @override
  String castWindowCreateFailed(String name, String error) {
    return 'Could not create the cast window for $name: $error';
  }

  @override
  String castWebFallback(String reason) {
    return 'Web casting fell back to native drawing: $reason';
  }

  @override
  String castWindowGone(String name, String error) {
    return 'The cast window for $name is gone; changing cast settings will reopen it: $error';
  }

  @override
  String castPageLoadFailed(int code, String detail) {
    return 'Cast page failed to load ($code) $detail';
  }

  @override
  String castPushFailed(String error) {
    return 'Failed to push the frame: $error';
  }

  @override
  String castWebError(String error) {
    return 'Web casting error: $error';
  }

  @override
  String get castModeFull => 'Full screen';

  @override
  String screenSummary(int monitors, int materials, int placements) {
    return '$monitors screens · $materials materials · $placements placements';
  }

  @override
  String get screenLiveSync => 'Casting live';

  @override
  String get screenEditOnly => 'Editing only';

  @override
  String screenCastingValue(int enabled, int total) {
    return '$enabled/$total casting';
  }

  @override
  String get screenScreens => 'Screens';

  @override
  String screenCount(int count) {
    return '$count';
  }

  @override
  String get screenScreenHint => 'Pick a screen to start laying out';

  @override
  String screenLayersCount(int count) {
    return '$count layers';
  }

  @override
  String screenUrlBadge(int count) {
    return 'Web $count';
  }

  @override
  String screenVideoBadge(int count) {
    return 'Video $count';
  }

  @override
  String get screenLoadLight => 'Light';

  @override
  String get screenLoadMid => 'Medium';

  @override
  String get screenLoadHeavy => 'Heavy';

  @override
  String get screenStatus => 'Status';

  @override
  String get screenCastingScreens => 'Casting';

  @override
  String get screenSharedCanvas => 'Shared canvas';

  @override
  String get screenMaterials => 'Materials';

  @override
  String screenMaterialsValue(int count) {
    return '$count';
  }

  @override
  String get screenStatusHintOn =>
      'One canvas drives every cast window, so style edits apply instantly.';

  @override
  String get screenStatusHintOff =>
      'With no screen selected, the canvas is just a layout preview.';

  @override
  String get screenDetect => 'Detect';

  @override
  String screenRescanHint(int count) {
    return '$count found. Rescan after plugging in a screen or changing resolution.';
  }

  @override
  String get screenAddMaterial => 'Add material';

  @override
  String screenToolbarCounts(int layers, int urls, int videos) {
    return '$layers layers · $urls web · $videos video';
  }

  @override
  String get screenCastingBadge => 'Casting';

  @override
  String get screenNotCasting => 'Not casting';

  @override
  String screenPerfWarning(int urls, int videos) {
    return 'This screen has $urls web pages and $videos videos. Each extra stream adds decoding and compositing cost; keep one of each per screen.';
  }

  @override
  String get screenNoSelection =>
      'Select a material to move it · drag handles to resize';

  @override
  String screenSelectionInfo(String name, int x, int y, int w, int h) {
    return '$name · $x, $y · $w×$h px';
  }

  @override
  String get screenShelf => 'Materials';

  @override
  String get screenShelfHint => 'Drag onto the canvas or click to place here';

  @override
  String get screenShelfMore =>
      'A material used on several screens keeps one shared style; position, layer and per-screen sound stay independent.';

  @override
  String screenShelfCount(int count) {
    return '$count';
  }

  @override
  String get screenUsageShared => 'Shared';

  @override
  String get screenUsageHere => 'This screen';

  @override
  String get screenUsageOther => 'Other screen';

  @override
  String get screenUsageNone => 'Unused';

  @override
  String screenUsageScreens(int count) {
    return 'On $count screens';
  }

  @override
  String get screenUsageSingle => 'Standalone material';

  @override
  String get screenLayers => 'Layers';

  @override
  String get screenLayersHint => 'Drag to reorder · top first';

  @override
  String get screenLayersEmpty =>
      'No layers on this screen yet. Add from the material shelf or press “Add material”.';

  @override
  String get screenShow => 'Show';

  @override
  String get screenHide => 'Hide';

  @override
  String get screenLock => 'Lock';

  @override
  String get screenUnlock => 'Unlock';

  @override
  String get screenSound => 'Sound';

  @override
  String get screenBackToScreen => 'Screen settings';

  @override
  String get screenMaterialName => 'Material name';

  @override
  String get screenDuplicate => 'Duplicate as standalone';

  @override
  String get screenDeleteLayer => 'Delete layer';

  @override
  String get screenAddLayer => 'Add layer';

  @override
  String get screenDeleteMaterial => 'Delete material';

  @override
  String get screenSectionLyric => 'Lyrics';

  @override
  String get screenFollowNow => 'Follows playback';

  @override
  String get screenOverlayAbove => 'Stacked above lyrics';

  @override
  String screenLineCount(int count) {
    return '$count lines';
  }

  @override
  String get screenTimeOffset => 'Offset';

  @override
  String get screenLyricNoBgNote =>
      'Lyrics have no background. For one, stretch an image or video to full size, lock it and send it to the back.';

  @override
  String get screenSectionUrl => 'Web page';

  @override
  String get screenEmbedPage => 'Embedded page';

  @override
  String get screenUrlPlaceholder => 'https://…';

  @override
  String get screenUrlReloadHint =>
      'The page refreshes when the URL changes or you reload.';

  @override
  String get screenReload => 'Reload';

  @override
  String get screenRefresh => 'Refresh';

  @override
  String get screenSeconds => 'sec';

  @override
  String get screenUrlEmbedNote =>
      'If the site blocks embedding (X-Frame-Options / CSP) the area stays blank; use an image or video instead.';

  @override
  String get screenUrlPreviewHint => 'The web page appears here while casting';

  @override
  String get screenScreenSound => 'Sound on this screen';

  @override
  String get screenVolume => 'Volume';

  @override
  String get screenSource => 'Source';

  @override
  String get screenStaticContent => 'Static content';

  @override
  String get screenSectionImage => 'Image';

  @override
  String get screenSectionVideo => 'Video';

  @override
  String get screenSectionText => 'Text';

  @override
  String get screenSectionSound => 'Playback on this screen';

  @override
  String get screenLocalFile => 'Local file';

  @override
  String get screenUrlSource => 'Image URL';

  @override
  String get screenImageUrl => 'Image URL';

  @override
  String get screenVideoUrl => 'Video URL';

  @override
  String get screenFilePath => 'File path';

  @override
  String get screenImageUrlPlaceholder => 'https://…/photo.jpg';

  @override
  String get screenImagePathPlaceholder => 'Pick a local image…';

  @override
  String get screenVideoUrlPlaceholder => 'https://…/clip.mp4';

  @override
  String get screenVideoPathPlaceholder => 'Pick a local video…';

  @override
  String get screenFill => 'Fill';

  @override
  String get screenFitStretch => 'Stretch';

  @override
  String get screenRadius => 'Corner radius';

  @override
  String get screenLoop => 'Loop';

  @override
  String get screenPlayOnce => 'Once';

  @override
  String get screenAutoplay => 'Autoplay';

  @override
  String get screenMuted => 'Muted';

  @override
  String get screenMuteOthersNote =>
      'Only one audio track plays per screen; enabling this mutes the others.';

  @override
  String get screenImageBgNote =>
      'For a full-screen backdrop, use an image: stretch to full size, send to back and lock the layer.';

  @override
  String get screenTextPlaceholder => 'Type text…';

  @override
  String get screenTextNote =>
      'Text has no background; add an image or video layer underneath for a backdrop.';

  @override
  String get screenColor => 'Color';

  @override
  String get screenGeometry => 'Position & layer';

  @override
  String get screenOpacity => 'Opacity';

  @override
  String get screenZOrder => 'Layer';

  @override
  String get screenZTop => 'Bring to front';

  @override
  String get screenZUp => 'Move up';

  @override
  String get screenZDown => 'Move down';

  @override
  String get screenZBottom => 'Send to back';

  @override
  String get screenShownOn => 'Shown on';

  @override
  String get screenLockLayer => 'Lock layer';

  @override
  String get screenSharedNote =>
      'Style and content are shared with every screen using this material; position, opacity, layer and per-screen sound stay independent.';

  @override
  String get screenCanvasColor => 'Canvas color';

  @override
  String get screenTransparent => 'Transparent';

  @override
  String get screenBlack => 'Black';

  @override
  String get screenMidnight => 'Midnight';

  @override
  String get screenLightCanvas => 'Light';

  @override
  String get screenCustomColor => 'Custom';

  @override
  String get screenCanvasNote =>
      'Transparent lets the desktop show through; a color paints an opaque backdrop.';

  @override
  String get screenCast => 'Cast';

  @override
  String get screenCastThisScreen => 'Cast this screen';

  @override
  String get screenCoverage => 'Coverage';

  @override
  String get screenFull => 'Full screen';

  @override
  String get screenWork => 'Work area';

  @override
  String get screenPerformance => 'Performance';

  @override
  String get screenPerfLayers => 'Layers';

  @override
  String get screenPerfUrls => 'Web';

  @override
  String get screenPerfVideos => 'Video';

  @override
  String get screenPerfAudio => 'Audio';

  @override
  String get screenPerfHint =>
      'Every extra web page or video noticeably raises CPU/GPU and memory; one of each per screen is safest.';

  @override
  String get screenTips => 'Tips';

  @override
  String get screenTipsText =>
      'Drag to move, drag any corner to resize; arrows nudge (Shift ×10), Delete removes, Esc deselects.';

  @override
  String get screenSoundFollowsScreen => 'Sound follows the screen';

  @override
  String get screenEmptyMaterial => 'No content yet';

  @override
  String get screenPickImage => 'Choose image';

  @override
  String get screenPickVideo => 'Choose video';

  @override
  String get screenNoVideos =>
      'No videos in this folder (mp4/webm/mov/mkv/avi/m4v/ogv)';

  @override
  String get screenTagLight => 'Light';

  @override
  String get screenTagNormal => 'Normal';

  @override
  String get screenTagHeavy => 'Heavy';

  @override
  String get screenTypeLyric => 'Lyrics';

  @override
  String get screenTypeLyricDesc => 'Live lyrics following playback';

  @override
  String get screenTypeUrl => 'Web page';

  @override
  String get screenTypeUrlDesc => 'Embed a web page';

  @override
  String get screenTypeImage => 'Image';

  @override
  String get screenTypeImageDesc => 'Local file or image URL';

  @override
  String get screenTypeVideo => 'Video';

  @override
  String get screenTypeVideoDesc => 'Local or network video, with sound';

  @override
  String get screenTypeText => 'Text';

  @override
  String get screenTypeTextDesc => 'Static text';

  @override
  String get sourcesTitle => 'Sources';

  @override
  String sourcesTotal(int count) {
    return '$count tracks in library';
  }

  @override
  String sourcesSummary(int local, int webdav) {
    return 'Local $local · WebDAV $webdav';
  }

  @override
  String get manageSources => 'Manage';

  @override
  String get localSourceTitle => 'Local folder';

  @override
  String get webdavSourceTitle => 'WebDAV';

  @override
  String webdavCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count servers',
      one: '1 server',
    );
    return '$_temp0';
  }

  @override
  String get webdavEmptyTitle => 'No WebDAV source yet';

  @override
  String get webdavEmptyHint =>
      'Connect a NAS or any WebDAV server and scan it into the same library';

  @override
  String get webdavAdd => 'Add';

  @override
  String get webdavAddTitle => 'Add WebDAV source';

  @override
  String get webdavEditTitle => 'Edit WebDAV source';

  @override
  String get webdavName => 'Name';

  @override
  String get webdavUrl => 'Server URL';

  @override
  String get webdavUsername => 'Username';

  @override
  String get webdavPassword => 'Password';

  @override
  String get webdavAllowSelfSigned =>
      'Allow self-signed certificate (common for NAS)';

  @override
  String get webdavDialogHint =>
      'Connection details stay on this machine. After scanning, tracks can be searched, queued and cast like local ones.';

  @override
  String get webdavTest => 'Test';

  @override
  String get webdavSaveAndScan => 'Save & scan';

  @override
  String get webdavSync => 'Sync';

  @override
  String get webdavSyncing => 'Syncing…';

  @override
  String get webdavNeverSynced => 'Never synced';

  @override
  String get webdavEdit => 'Edit';

  @override
  String get webdavDelete => 'Delete';

  @override
  String get webdavMore => 'More';

  @override
  String webdavDeleteConfirm(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get webdavInvalidUrl => 'Server URL must start with http(s)://';

  @override
  String get webdavNeedUrl => 'Enter the server URL first';

  @override
  String get webdavNeedName => 'Enter a name first';

  @override
  String webdavTestOk(int count) {
    return 'Connected, $count items at the root';
  }

  @override
  String webdavTestFailed(String error) {
    return 'Connection failed: $error';
  }

  @override
  String webdavAuthFailed(int status) {
    return 'Authentication failed (HTTP $status)';
  }

  @override
  String webdavHttpError(int status) {
    return 'Server returned HTTP $status';
  }

  @override
  String webdavConnectFailed(String detail) {
    return 'Connection failed: $detail';
  }

  @override
  String webdavTlsFailed(String detail) {
    return 'Certificate check failed; allow self-signed certificates to continue: $detail';
  }

  @override
  String get webdavTimeout => 'Connection timed out';

  @override
  String get webdavInvalidXml => 'Could not parse the WebDAV response';

  @override
  String get webdavNotDav => 'This address is not a WebDAV service';

  @override
  String get webdavNotFound => 'Remote folder not found';

  @override
  String webdavPartialFolders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count folders failed',
      one: '1 folder failed',
    );
    return '$_temp0; the rest were synced';
  }

  @override
  String webdavFileUnavailable(String name) {
    return 'Remote file unavailable: $name';
  }

  @override
  String webdavSyncedAt(String time) {
    return 'Synced $time';
  }

  @override
  String webdavLastScanned(String time) {
    return 'Last scan $time';
  }

  @override
  String webdavSyncProgress(int tracks, int folders) {
    return '$tracks tracks · $folders folders found';
  }

  @override
  String get webdavTesting => 'Testing…';

  @override
  String get webdavSaving => 'Saving…';
}
