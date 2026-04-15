import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_yandex_ads/components/banner.dart';
import 'package:flutter_yandex_ads/components/interstitial.dart';
import 'package:flutter_yandex_ads/widgets/banner.dart';
import 'package:flutter_yandex_ads/widgets/native.dart';
import 'package:flutter_yandex_ads/yandex.dart';

final appSettings = AppSettingsController();
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterYandexAds.initialize();
  await appSettings.load();
  runApp(QuranApp(settings: appSettings));
}

class QuranApp extends StatelessWidget {
  const QuranApp({super.key, required this.settings});

  final AppSettingsController settings;

  @override
  Widget build(BuildContext context) {
    final darkScheme = ColorScheme.fromSeed(
      seedColor: AppColors.mint,
      brightness: Brightness.dark,
      primary: AppColors.mint,
      secondary: AppColors.coral,
      surface: AppColors.card,
      background: AppColors.backgroundTop,
      onPrimary: AppColors.backgroundTop,
      onSecondary: AppColors.backgroundTop,
      onSurface: AppColors.textPrimary,
      onBackground: AppColors.textPrimary,
    );

    final lightScheme = ColorScheme.fromSeed(
      seedColor: AppColors.mint,
      brightness: Brightness.light,
    );

    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Quroni karim',
          themeMode: settings.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: lightScheme,
            scaffoldBackgroundColor: Colors.transparent,
            textTheme: GoogleFonts.playfairDisplayTextTheme()
                .apply(
                  bodyColor: Colors.black87,
                  displayColor: Colors.black87,
                )
                .copyWith(
                  titleLarge: GoogleFonts.playfairDisplay(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                  titleMedium: GoogleFonts.playfairDisplay(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  bodyLarge: GoogleFonts.spaceGrotesk(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                  bodyMedium: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black54,
                  ),
                  labelLarge: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: Colors.black87,
                  ),
                ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: darkScheme,
            scaffoldBackgroundColor: Colors.transparent,
            textTheme: GoogleFonts.playfairDisplayTextTheme()
                .apply(
                  bodyColor: AppColors.textPrimary,
                  displayColor: AppColors.textPrimary,
                )
                .copyWith(
                  titleLarge: GoogleFonts.playfairDisplay(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  titleMedium: GoogleFonts.playfairDisplay(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  bodyLarge: GoogleFonts.spaceGrotesk(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                  bodyMedium: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                  labelLarge: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: AppColors.textPrimary,
                  ),
                ),
          ),
          home: const HomeScreen(),
        );
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Ad unit IDs
  static const String _bannerAdUnitId = 'R-M-19102623-1';
  static const String _bannerTopAdUnitId = 'R-M-19102623-2';
  static const String _interstitialAdUnitId = 'R-M-19102623-3';
  static const String _nativeAdUnitId = 'R-M-19102623-4';
  static const int _bannerHeight = 50;
  static const int _nativeHeight = 120;

  static const Duration _interstitialInterval = Duration(minutes: 6);
  Timer? _interstitialTimer;
  YandexAdsInterstitialComponent? _interstitial;
  VoidCallback? _pendingNavAfterAd;
  DateTime? _lastInterstitialShownAt;
  bool _isNativeReady = false;

  YandexAdsBannerComponent? _bannerComponent;
  bool _isBannerReady = false;
  int? _bannerWidth;

  YandexAdsBannerComponent? _topBannerComponent;
  bool _isTopBannerReady = false;
  int? _topBannerWidth;

  int _languageIndex = 0;
  int _navIndex = 0;
  final AudioPlayer _player = AudioPlayer();
  final Map<int, bool> _downloaded = {};
  final Map<int, bool> _downloading = {};
  final Set<int> _favoriteSurahs = {};
  List<SurahItem> _surahItems = [];
  bool _isLoading = true;
  String? _nowPlaying;
  SurahItem? _currentSurah;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  static const List<String> _languageKeys = ['tajik', 'uzbek', 'russian'];

  String get _currentLanguage => _languageKeys[_languageIndex];
  AppStrings get _strings => AppStrings.forLanguage(_currentLanguage);
  bool get _showAds => true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _player.setSpeed(appSettings.playbackSpeed);
    _loadLanguage().then((_) => _loadSurahs());
    _initInterstitial();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _player.dispose();
    _destroyBanner();
    _interstitialTimer?.cancel();
    _interstitial = null;
    super.dispose();
  }

  void _destroyBanner() {
    _bannerComponent = null;
    _isBannerReady = false;
    _bannerWidth = null;
    _topBannerComponent = null;
    _isTopBannerReady = false;
    _topBannerWidth = null;
  }

  // ── Interstitial (R-M-19102623-3) ─────────────────────────────────────────
  void _initInterstitial() {
    if (!_showAds) return;
    _interstitial = YandexAdsInterstitialComponent(
      id: _interstitialAdUnitId,
      onAdLoaded: () {
        if (_pendingNavAfterAd != null) {
          _showInterstitialAd();
        }
      },
      onAdShown: () {
        _lastInterstitialShownAt = DateTime.now();
      },
      onAdFailedToLoad: (_) => _runPendingNavAfterAd(),
      onAdFailedToShow: (_) => _runPendingNavAfterAd(),
      onAdDismissed: () => _runPendingNavAfterAd(),
    );
  }

  void _showInterstitialAd() {
    if (_interstitial == null || !mounted) return;
    _interstitial!.show();
  }

  void _scheduleInterstitialReload() {
    _interstitialTimer?.cancel();
    _interstitialTimer = Timer(_interstitialInterval, () {
      if (!mounted) return;
      _interstitial?.load();
    });
  }

  void _runPendingNavAfterAd() {
    final action = _pendingNavAfterAd;
    _pendingNavAfterAd = null;
    if (action != null && mounted) {
      action();
    }
    _scheduleInterstitialReload();
  }

  void _navigateWithInterstitial(VoidCallback after) {
    if (!_showAds || _interstitial == null) {
      after();
      return;
    }
    if (_lastInterstitialShownAt != null) {
      final elapsed = DateTime.now().difference(_lastInterstitialShownAt!);
      if (elapsed < _interstitialInterval) {
        after();
        return;
      }
    }
    _pendingNavAfterAd = after;
    _interstitial?.load();
  }
  // ── Native ad (R-M-19102623-4) ─────────────────────────────────────────────
  Widget _buildNativeAd() {
    if (!_showAds) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.round();
        return SizedBox(
          height: _nativeHeight.toDouble(),
          child: Visibility(
            visible: _isNativeReady,
            maintainState: true,
            maintainAnimation: true,
            maintainSize: true,
            child: YandexAdsNativeWidget(
              id: _nativeAdUnitId,
              width: width,
              height: _nativeHeight,
              onAdLoaded: () {
                if (!mounted) return;
                setState(() {
                  _isNativeReady = true;
                });
              },
              onAdFailedToLoad: (_) {
                if (!mounted) return;
                setState(() {
                  _isNativeReady = false;
                });
              },
            ),
          ),
        );
      },
    );
  }

  // ── Top banner (R-M-19102623-2) ────────────────────────────────────────────
  void _createTopBannerIfNeeded(int width) {
    if (!_showAds) return;
    if (_topBannerComponent != null && _topBannerWidth == width) return;
    _topBannerWidth = width;
    _isTopBannerReady = false;
    _topBannerComponent = YandexAdsBannerComponent(
      id: _bannerTopAdUnitId,
      width: width,
      height: _bannerHeight,
      onAdLoaded: () {
        if (!mounted) return;
        setState(() => _isTopBannerReady = true);
      },
      onAdFailedToLoad: (_) {
        if (!mounted) return;
        setState(() => _isTopBannerReady = false);
      },
    );
    _topBannerComponent!.load();
  }

  Widget _buildTopBanner() {
    if (!_showAds) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.round();
        _createTopBannerIfNeeded(width);
        if (!_isTopBannerReady || _topBannerComponent == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: SizedBox(
            height: _bannerHeight.toDouble(),
            child: YandexAdsBannerWidget(banner: _topBannerComponent!),
          ),
        );
      },
    );
  }

  void _createBannerIfNeeded(int width) {
    if (!_showAds) return;
    if (_bannerComponent != null && _bannerWidth == width) return;

    _bannerWidth = width;
    _isBannerReady = false;
    _bannerComponent = YandexAdsBannerComponent(
      id: _bannerAdUnitId,
      width: width,
      height: _bannerHeight,
      onAdLoaded: () {
        if (!mounted) return;
        setState(() => _isBannerReady = true);
      },
      onAdFailedToLoad: (_) {
        if (!mounted) return;
        setState(() => _isBannerReady = false);
      },
    );
    _bannerComponent!.load();
  }

  Widget _buildBanner() {
    if (!_showAds) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.round();
        _createBannerIfNeeded(width);

        if (!_isBannerReady || _bannerComponent == null) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: SizedBox(
            height: _bannerHeight.toDouble(),
            child: YandexAdsBannerWidget(banner: _bannerComponent!),
          ),
        );
      },
    );
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('favorite_surahs') ?? [];
    final nums = raw
        .map((e) => int.tryParse(e))
        .whereType<int>()
        .toSet();
    if (!mounted) return;
    setState(() {
      _favoriteSurahs
        ..clear()
        ..addAll(nums);
    });
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt('language_index') ?? 0;
    if (!mounted) return;
    setState(() {
      _languageIndex = stored.clamp(0, _languageKeys.length - 1);
    });
  }

  Future<void> _toggleFavorite(int surahNumber) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_favoriteSurahs.contains(surahNumber)) {
        _favoriteSurahs.remove(surahNumber);
      } else {
        _favoriteSurahs.add(surahNumber);
      }
    });
    await prefs.setStringList(
      'favorite_surahs',
      _favoriteSurahs.map((e) => e.toString()).toList(),
    );
  }

  Future<void> _selectLanguage() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _strings.languageLabels.length,
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(_strings.languageLabels[index]),
                trailing: index == _languageIndex
                    ? Icon(Icons.check_rounded, color: AppColors.mint)
                    : null,
                onTap: () => Navigator.of(context).pop(index),
              );
            },
          ),
        );
      },
    );
    if (selected != null && selected != _languageIndex) {
      setState(() {
        _languageIndex = selected;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('language_index', selected);
      await _loadSurahs();
    }
  }

  Future<void> _selectPlaybackSpeed() async {
    final selected = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: FullPlayerScreen.speedOptions
                .map(
                  (speed) => ListTile(
                    title: Text('${speed}x'),
                    trailing: (speed - appSettings.playbackSpeed).abs() < 0.01
                        ? const Icon(Icons.check_rounded,
                            color: AppColors.mint)
                        : null,
                    onTap: () => Navigator.of(context).pop(speed),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
    if (selected != null) {
      await appSettings.setPlaybackSpeed(selected);
      await _player.setSpeed(selected);
      if (mounted) setState(() {});
    }
  }

  Future<void> _editReciterBase() async {
    final controller =
        TextEditingController(text: appSettings.reciterBaseUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: Text(_strings.reciter),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: 'https://cdn.equran.id/audio-full/Reciter',
              hintStyle: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(_strings.cancel),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: Text(_strings.save),
            ),
          ],
        );
      },
    );
    if (result != null) {
      await appSettings.setReciterBaseUrl(result);
      if (mounted) setState(() {});
    }
  }

  Future<void> _clearDownloads() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: Text(_strings.clearDownloads),
          content: Text(_strings.clearDownloadsHint),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(_strings.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(_strings.delete),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/audio');
    if (await folder.exists()) {
      await folder.delete(recursive: true);
    }
    await _refreshDownloadStatus();
    _showMessage(_strings.downloadsCleared);
  }

  Future<void> _loadSurahs() async {
    setState(() {
      _isLoading = true;
    });

    final assetPath = 'assets/quran/$_currentLanguage.json';
    try {
      final jsonString = await rootBundle.loadString(assetPath);
      final data = json.decode(jsonString) as Map<String, dynamic>;
      final items = (data['surahs'] as List<dynamic>? ?? [])
          .map((item) => SurahItem.fromJson(item as Map<String, dynamic>))
          .toList();
      _surahItems = items;
      await _refreshDownloadStatus();
    } catch (_) {
      _surahItems = [];
      _showMessage('Failed to load surah data.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshDownloadStatus() async {
    final Map<int, bool> statuses = {};
    for (final item in _surahItems) {
      final file = await _audioFileFor(item);
      statuses[item.number] = await file.exists();
    }
    if (!mounted) return;
    setState(() {
      _downloaded
        ..clear()
        ..addAll(statuses);
    });
  }

  Future<File> _audioFileFor(SurahItem item) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/audio/$_currentLanguage');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    final extension = _extensionFromUrl(_resolveAudioUrl(item));
    final name = item.number.toString().padLeft(3, '0');
    return File('${folder.path}/$name$extension');
  }

  String _extensionFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final path = uri?.path ?? '';
    final lastDot = path.lastIndexOf('.');
    if (lastDot != -1 && lastDot > path.lastIndexOf('/')) {
      return path.substring(lastDot);
    }
    return '.mp3';
  }

  String _resolveAudioUrl(SurahItem item) {
    final base = appSettings.reciterBaseUrl.trim();
    if (base.isNotEmpty) {
      final sep = base.endsWith('/') ? '' : '/';
      return '$base$sep${item.number.toString().padLeft(3, '0')}.mp3';
    }
    return item.audioUrl;
  }

  Future<void> _playSurah(SurahItem item) async {
    final audioUrl = _resolveAudioUrl(item);
    if (audioUrl.isEmpty) {
      _showMessage(_strings.audioMissing);
      return;
    }

    _currentSurah = item;
    final file = await _audioFileFor(item);
    if (await file.exists()) {
      await _player.setFilePath(file.path);
    } else {
      await _player.setUrl(audioUrl);
    }
    await _player.setSpeed(appSettings.playbackSpeed);
    await _player.play();
    if (!mounted) return;
    setState(() {
      _nowPlaying = item.name;
    });
  }

  Future<void> _downloadSurah(SurahItem item) async {
    final audioUrl = _resolveAudioUrl(item);
    if (audioUrl.isEmpty) {
      _showMessage(_strings.audioMissing);
      return;
    }
    if (_downloading[item.number] == true) return;

    setState(() {
      _downloading[item.number] = true;
    });

    try {
      final file = await _audioFileFor(item);
      if (!await file.exists()) {
        final response = await http.get(Uri.parse(audioUrl));
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        await file.writeAsBytes(response.bodyBytes);
      }
      if (!mounted) return;
      setState(() {
        _downloaded[item.number] = true;
      });
      _showMessage(_strings.downloaded(item.name));
    } catch (_) {
      _showMessage(_strings.downloadFailed);
    } finally {
      if (mounted) {
        setState(() {
          _downloading[item.number] = false;
        });
      }
    }
  }

  Future<void> _openSurah(SurahItem item) async {
    _navigateWithInterstitial(() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SurahDetailScreen(
            surah: item,
            strings: _strings,
            topBanner: _buildTopBanner(),
          ),
        ),
      );
    });
  }

  void _openPlayer() {
    _navigateWithInterstitial(() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FullPlayerScreen(
            player: _player,
            title: _nowPlaying,
            currentSurah: _currentSurah,
            surahs: _surahItems,
            onPlaySurah: _playSurah,
            strings: _strings,
          ),
        ),
      );
    });
  }

  void _onNavChanged(int index) {
    setState(() {
      _navIndex = index;
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _navIndex,
        children: [
          _buildHomeBody(textTheme),
          _buildAudioBody(textTheme),
          _buildSavedBody(textTheme),
          _buildSettingsBody(textTheme),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildBanner(),
            _BottomNav(
              strings: _strings,
              currentIndex: _navIndex,
              onTap: _onNavChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeBody(TextTheme textTheme) {
    return Stack(
      children: [
        const _BackgroundLayer(),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 140),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top banner ad (R-M-1763838-1)
                _buildTopBanner(),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Quroni Karim', style: textTheme.titleLarge),
                          const SizedBox(height: 6),
                          Text(
                            _strings.subtitle,
                            style: textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          if (_nowPlaying != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              _strings.nowPlaying(_nowPlaying!),
                              style: textTheme.bodyMedium?.copyWith(
                                color: AppColors.mint,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const _AvatarBadge(),
                  ],
                ),
                const SizedBox(height: 18),
                _SearchBar(
                  textTheme: textTheme,
                  placeholder: _strings.searchPlaceholder,
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.trim().toLowerCase();
                    });
                  },
                ),
                const SizedBox(height: 18),
                _LanguageChips(
                  currentIndex: _languageIndex,
                  onChanged: (index) {
                    setState(() {
                      _languageIndex = index;
                    });
                    SharedPreferences.getInstance().then(
                      (prefs) => prefs.setInt('language_index', index),
                    );
                    _loadSurahs();
                  },
                  labels: _strings.languageLabels,
                ),
                const SizedBox(height: 12),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_strings.surahsTitle, style: textTheme.titleMedium),
                    Text(
                      _strings.viewAll,
                      style: textTheme.labelLarge?.copyWith(
                        color: AppColors.coral,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _TagChip(label: _strings.tagAll, isSelected: true),
                    const SizedBox(width: 8),
                    _TagChip(label: _strings.tagMeccan),
                    const SizedBox(width: 8),
                    _TagChip(label: _strings.tagMedinan),
                  ],
                ),
                const SizedBox(height: 16),
                ..._buildSurahList(
                  textTheme,
                  openDetails: true,
                  showAudioActions: false,
                  showNativeAd: _navIndex == 0,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAudioBody(TextTheme textTheme) {
    return Stack(
      children: [
        const _BackgroundLayer(),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 140),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopBanner(),
                Text(_strings.audio, style: textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  _strings.subtitle,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (_nowPlaying != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: AppColors.cardAlt,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.graphic_eq,
                            color: AppColors.mint,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _strings.nowPlaying(_nowPlaying!),
                                style: textTheme.bodyLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _strings.currentLanguageLabel,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        StreamBuilder<PlayerState>(
                          stream: _player.playerStateStream,
                          builder: (context, snapshot) {
                            final state = snapshot.data;
                            final playing = state?.playing ?? false;
                            return IconButton(
                              onPressed: () {
                                if (playing) {
                                  _player.pause();
                                } else {
                                  _player.play();
                                }
                              },
                              icon: Icon(
                                playing
                                    ? Icons.pause_circle_filled_rounded
                                    : Icons.play_circle_fill_rounded,
                                color: AppColors.mint,
                                size: 36,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _openPlayer,
                    icon: const Icon(Icons.open_in_full_rounded),
                    label: Text(_strings.openPlayer),
                  ),
                ],
                const SizedBox(height: 16),
                _LanguageChips(
                  currentIndex: _languageIndex,
                  onChanged: (index) {
                    setState(() {
                      _languageIndex = index;
                    });
                    SharedPreferences.getInstance().then(
                      (prefs) => prefs.setInt('language_index', index),
                    );
                    _loadSurahs();
                  },
                  labels: _strings.languageLabels,
                ),
                const SizedBox(height: 18),
                Text(_strings.surahsTitle, style: textTheme.titleMedium),
                const SizedBox(height: 12),
                ..._buildSurahList(
                  textTheme,
                  openPlayerAfterPlay: true,
                  openDetails: false,
                  showNativeAd: _navIndex == 1,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildSurahList(
    TextTheme textTheme, {
    bool openPlayerAfterPlay = false,
    bool openDetails = true,
    List<SurahItem>? source,
    bool showAudioActions = true,
    bool showNativeAd = false,
  }) {
    final list = source ?? _surahItems;
    final filtered = _searchQuery.isEmpty || source != null
        ? list
        : list.where((s) {
            final q = _searchQuery;
            return s.name.toLowerCase().contains(q) ||
                s.translation.toLowerCase().contains(q) ||
                s.number.toString().contains(q);
          }).toList();
    if (_isLoading && source == null) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: LinearProgressIndicator(
            minHeight: 2,
            color: AppColors.mint,
            backgroundColor: AppColors.cardAlt,
          ),
        ),
      ];
    }
    if (filtered.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text(
            _strings.noSurahs,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ];
    }
    return [
      ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = filtered[index];
          final tile = _SurahTile(
            item: item,
            isDownloaded: _downloaded[item.number] ?? false,
            isDownloading: _downloading[item.number] ?? false,
            onPlay: () async {
              await _playSurah(item);
              if (openPlayerAfterPlay) {
                _openPlayer();
              }
            },
            onDownload: () => _downloadSurah(item),
            playLabel: _strings.play,
            onOpen: () async {
              if (!openDetails) {
                await _playSurah(item);
                _openPlayer();
                return;
              }
              await _openSurah(item);
            },
            isFavorite: _favoriteSurahs.contains(item.number),
            onToggleFavorite: () => _toggleFavorite(item.number),
            showAudioActions: showAudioActions,
          );
          // Show a native ad after the 10th surah item
          if (_showAds && showNativeAd && index == 9) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                tile,
                const SizedBox(height: 12),
                _buildNativeAd(),
              ],
            );
          }
          return tile;
        },
      ),
    ];
  }

  Widget _buildPlaceholder(TextTheme textTheme, String title) {
    return Stack(
      children: [
        const _BackgroundLayer(),
        SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  _strings.comingSoon,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSavedBody(TextTheme textTheme) {
    final favorites = _surahItems
        .where((s) => _favoriteSurahs.contains(s.number))
        .toList();
    return Stack(
      children: [
        const _BackgroundLayer(),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 140),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_strings.favoritesTitle, style: textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  _strings.subtitle,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                if (favorites.isEmpty)
                  Text(
                    _strings.noFavorites,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  )
                else
                  ..._buildSurahList(
                    textTheme,
                    source: favorites,
                    showAudioActions: false,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsBody(TextTheme textTheme) {
    return Stack(
      children: [
        const _BackgroundLayer(),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 140),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_strings.settingsTitle, style: textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  _strings.subtitle,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                _SettingsSwitchTile(
                  title: _strings.theme,
                  subtitle: appSettings.themeMode == ThemeMode.dark
                      ? _strings.darkLabel
                      : _strings.lightLabel,
                  value: appSettings.themeMode == ThemeMode.dark,
                  onChanged: (value) {
                    appSettings.setThemeMode(
                      value ? ThemeMode.dark : ThemeMode.light,
                    );
                    setState(() {});
                  },
                ),
                _SettingsTile(
                  title: _strings.languageLabel,
                  subtitle: _strings.languageLabels[_languageIndex],
                  onTap: _selectLanguage,
                ),
                _SettingsTile(
                  title: _strings.reciter,
                  subtitle: appSettings.reciterBaseUrl,
                  onTap: _editReciterBase,
                ),
                _SettingsTile(
                  title: _strings.speed,
                  subtitle: '${appSettings.playbackSpeed}x',
                  onTap: _selectPlaybackSpeed,
                ),
                _SettingsSliderTile(
                  title: _strings.fontSize,
                  value: appSettings.ayahFontScale,
                  min: 0.85,
                  max: 1.3,
                  onChanged: (value) {
                    appSettings.setAyahFontScale(value);
                    setState(() {});
                  },
                ),
                _SettingsTile(
                  title: _strings.audio,
                  subtitle: _strings.audioMode,
                  onTap: () {},
                ),
                _SettingsTile(
                  title: _strings.clearDownloads,
                  subtitle: _strings.clearDownloadsHint,
                  onTap: _clearDownloads,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.textTheme,
    required this.placeholder,
    required this.controller,
    required this.onChanged,
  });

  final TextTheme textTheme;
  final String placeholder;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: AppColors.textPrimary),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: placeholder,
                hintStyle: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              onPressed: () {
                controller.clear();
                onChanged('');
              },
              icon: Icon(Icons.close_rounded, color: AppColors.textSecondary),
            )
          else
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.mint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.tune, color: AppColors.backgroundTop),
            ),
        ],
      ),
    );
  }
}

class _LanguageChips extends StatelessWidget {
  const _LanguageChips({
    required this.currentIndex,
    required this.onChanged,
    required this.labels,
  });

  final int currentIndex;
  final ValueChanged<int> onChanged;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: List.generate(labels.length, (index) {
        final isActive = index == currentIndex;
        return GestureDetector(
          onTap: () => onChanged(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isActive ? AppColors.mint : AppColors.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isActive)
                  Icon(
                    Icons.check_circle,
                    size: 16,
                    color: AppColors.backgroundTop,
                  ),
                if (isActive) const SizedBox(width: 6),
                Text(
                  labels[index],
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: isActive
                            ? AppColors.backgroundTop
                            : AppColors.textPrimary,
                      ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.languageLabel,
    required this.heroRange,
    required this.badgeFriday,
    required this.badgeMinutes,
  });

  final String languageLabel;
  final String heroRange;
  final String badgeFriday;
  final String badgeMinutes;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Al-Kahf', style: textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  '$heroRange • $languageLabel',
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _Badge(
                      text: badgeFriday,
                      color: AppColors.mint.withOpacity(0.2),
                    ),
                    const SizedBox(width: 8),
                    _Badge(
                      text: badgeMinutes,
                      color: AppColors.coral.withOpacity(0.2),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AppColors.coral,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AppColors.coral.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              size: 34,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColors.textPrimary,
            ),
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionCard(
            icon: Icons.menu_book_rounded,
            label: strings.surahsTitle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionCard(
            icon: Icons.grid_view_rounded,
            label: strings.juz,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionCard(
            icon: Icons.bookmark_border_rounded,
            label: strings.saved,
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.cardAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.mint),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class SurahItem {
  final int number;
  final String name;
  final String translation;
  final int ayahs;
  final String duration;
  final String audioUrl;
  final List<AyahItem> ayahItems;
  final String revelation;

  const SurahItem({
    required this.number,
    required this.name,
    required this.translation,
    required this.ayahs,
    required this.duration,
    required this.audioUrl,
    required this.ayahItems,
    required this.revelation,
  });

  factory SurahItem.fromJson(Map<String, dynamic> json) {
    final audio = (json['audio'] as Map<String, dynamic>?) ?? {};
    final durationSec = (audio['duration_sec'] as num?)?.toInt() ?? 0;
    final nameLocal = (json['name_local'] as String?)?.trim() ?? '';
    final nameLatin = (json['name_latin'] as String?)?.trim() ?? '';
    final ayahs = (json['ayahs'] as List<dynamic>? ?? [])
        .map((item) => AyahItem.fromJson(item as Map<String, dynamic>))
        .toList();

    return SurahItem(
      number: (json['number'] as num?)?.toInt() ?? 0,
      name: nameLocal.isNotEmpty ? nameLocal : nameLatin,
      translation: nameLatin,
      ayahs: (json['ayah_count'] as num?)?.toInt() ?? 0,
      duration: _formatDuration(durationSec),
      audioUrl: (audio['full'] as String?)?.trim() ?? '',
      ayahItems: ayahs,
      revelation: (json['revelation'] as String?)?.trim() ?? '',
    );
  }

  static String _formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '--:--';
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString()}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString()}:${seconds.toString().padLeft(2, '0')}';
  }
}

class AyahItem {
  final int number;
  final String text;
  final String audio;

  const AyahItem({
    required this.number,
    required this.text,
    required this.audio,
  });

  factory AyahItem.fromJson(Map<String, dynamic> json) {
    return AyahItem(
      number: (json['number'] as num?)?.toInt() ?? 0,
      text: (json['text'] as String?)?.trim() ?? '',
      audio: (json['audio'] as String?)?.trim() ?? '',
    );
  }
}

class _SurahTile extends StatelessWidget {
  const _SurahTile({
    required this.item,
    required this.onPlay,
    required this.onDownload,
    required this.isDownloaded,
    required this.isDownloading,
    required this.playLabel,
    required this.onOpen,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.showAudioActions,
  });

  final SurahItem item;
  final VoidCallback onPlay;
  final VoidCallback onDownload;
  final bool isDownloaded;
  final bool isDownloading;
  final String playLabel;
  final VoidCallback onOpen;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final bool showAudioActions;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final Widget downloadWidget;

    if (isDownloading) {
      downloadWidget = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.mint,
        ),
      );
    } else if (isDownloaded) {
      downloadWidget = const Icon(
        Icons.check_circle,
        color: AppColors.mint,
        size: 22,
      );
    } else {
      downloadWidget = IconButton(
        onPressed: onDownload,
        icon: Icon(Icons.download_rounded, color: AppColors.textPrimary),
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        padding: EdgeInsets.zero,
      );
    }

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.cardAlt,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                item.number.toString().padLeft(2, '0'),
                style: textTheme.labelLarge?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(item.name, style: textTheme.titleMedium),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.translation} • ${item.ayahs} ayahs',
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: onToggleFavorite,
                  icon: Icon(
                    isFavorite ? Icons.bookmark : Icons.bookmark_border,
                    color: isFavorite ? AppColors.coral : AppColors.textSecondary,
                  ),
                ),
                Text(
                  item.duration,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (showAudioActions) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      downloadWidget,
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: onPlay,
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.mint,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(
                            playLabel,
                            style: textTheme.labelLarge?.copyWith(
                              color: AppColors.backgroundTop,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SurahDetailScreen extends StatelessWidget {
  const SurahDetailScreen({
    super.key,
    required this.surah,
    required this.strings,
    this.topBanner,
  });

  final SurahItem surah;
  final AppStrings strings;
  final Widget? topBanner;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final revelation = strings.revelationLabel(surah.revelation);

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          const _BackgroundLayer(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon:  Icon(
                          Icons.arrow_back_rounded,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          surah.name,
                          style: textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                if (topBanner != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: topBanner!,
                  ),
                ],
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: AppColors.cardAlt,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    surah.number.toString().padLeft(2, '0'),
                                    style: textTheme.labelLarge?.copyWith(
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        surah.name,
                                        style: textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        surah.translation,
                                        style: textTheme.bodyMedium?.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _Badge(
                                  text: '${surah.ayahs} ${strings.ayahsTitle}',
                                  color: AppColors.cardAlt,
                                ),
                                if (revelation.isNotEmpty)
                                  _Badge(
                                    text: revelation,
                                    color: AppColors.cardAlt,
                                  ),
                                _Badge(
                                  text: surah.duration,
                                  color: AppColors.cardAlt,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(strings.ayahsTitle, style: textTheme.titleMedium),
                      const SizedBox(height: 12),
                      ...surah.ayahItems.map(
                        (ayah) => _AyahTile(ayah: ayah),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AyahTile extends StatelessWidget {
  const _AyahTile({required this.ayah});

  final AyahItem ayah;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.cardAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              ayah.number.toString(),
              style: textTheme.labelLarge?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ayah.text,
              style: textTheme.bodyLarge,
              textScaler: TextScaler.linear(appSettings.ayahFontScale),
            ),
          ),
        ],
      ),
    );
  }
}

class FullPlayerScreen extends StatefulWidget {
  const FullPlayerScreen({
    super.key,
    required this.player,
    required this.title,
    required this.currentSurah,
    required this.surahs,
    required this.onPlaySurah,
    required this.strings,
  });

  static const List<double> speedOptions = [0.75, 1.0, 1.25, 1.5];

  final AudioPlayer player;
  final String? title;
  final SurahItem? currentSurah;
  final List<SurahItem> surahs;
  final Future<void> Function(SurahItem) onPlaySurah;
  final AppStrings strings;

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen> {
  final Random _random = Random();
  StreamSubscription<PlayerState>? _playerSub;
  bool _shuffleEnabled = false;
  String? _currentTitle;
  SurahItem? _activeSurah;

  @override
  void initState() {
    super.initState();
    _currentTitle = widget.title ?? widget.strings.surahsTitle;
    _activeSurah = widget.currentSurah;
    _playerSub = widget.player.playerStateStream.listen((state) {
      if (!_shuffleEnabled) return;
      if (state.processingState == ProcessingState.completed) {
        _playRandom();
      }
    });
  }

  @override
  void dispose() {
    _playerSub?.cancel();
    super.dispose();
  }

  Future<void> _setSpeed(double speed) async {
    await widget.player.setSpeed(speed);
    await appSettings.setPlaybackSpeed(speed);
    if (mounted) setState(() {});
  }

  Future<void> _toggleRepeat() async {
    final current = widget.player.loopMode;
    final next = current == LoopMode.one ? LoopMode.off : LoopMode.one;
    await widget.player.setLoopMode(next);
    if (mounted) setState(() {});
  }

  Future<void> _toggleShuffle() async {
    setState(() {
      _shuffleEnabled = !_shuffleEnabled;
    });
  }

  List<SurahItem> _availableSurahs() {
    return widget.surahs;
  }

  Future<void> _playRandom() async {
    final available =
        _availableSurahs().where((s) => s.audioUrl.isNotEmpty).toList();
    if (available.isEmpty) {
      _showMessage(widget.strings.audioMissing);
      return;
    }
    final next = available[_random.nextInt(available.length)];
    await widget.onPlaySurah(next);
    if (mounted) {
      setState(() {
        _currentTitle = next.name;
        _activeSurah = next;
      });
    }
  }

  Future<void> _playNext() async {
    final available = _availableSurahs();
    if (available.isEmpty) return;
    final currentNumber = _activeSurah?.number ?? 1;
    final currentIndex =
        available.indexWhere((s) => s.number == currentNumber);
    final nextIndex = currentIndex == -1
        ? 0
        : (currentIndex + 1) % available.length;
    final next = available[nextIndex];
    await widget.onPlaySurah(next);
    if (mounted) {
      setState(() {
        _currentTitle = next.name;
        _activeSurah = next;
      });
    }
  }

  Future<void> _playPrevious() async {
    final available = _availableSurahs();
    if (available.isEmpty) return;
    final currentNumber = _activeSurah?.number ?? 1;
    final currentIndex =
        available.indexWhere((s) => s.number == currentNumber);
    final prevIndex = currentIndex == -1
        ? 0
        : (currentIndex - 1 + available.length) % available.length;
    final prev = available[prevIndex];
    await widget.onPlaySurah(prev);
    if (mounted) {
      setState(() {
        _currentTitle = prev.name;
        _activeSurah = prev;
      });
    }
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds % 60;
    final hours = value.inHours;
    if (hours > 0) {
      return '${hours.toString()}:${(minutes % 60).toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString()}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final title = _currentTitle ?? widget.strings.surahsTitle;
    final surah = _activeSurah;
    final hasAyahAudio = surah?.ayahItems.any((a) => a.audio.isNotEmpty) ?? false;
    final bubbleText = surah != null
        ? surah.number.toString().padLeft(2, '0')
        : 'QK';

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          const _BackgroundLayer(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () {},
                        icon:  Icon(
                          Icons.more_horiz,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(title, style: textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    widget.strings.currentLanguageLabel,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Center(
                    child: _HeroArtwork(label: bubbleText),
                  ),
                  const SizedBox(height: 26),
                  StreamBuilder<Duration>(
                    stream: widget.player.positionStream,
                    builder: (context, positionSnapshot) {
                      final position = positionSnapshot.data ?? Duration.zero;
                      final duration = widget.player.duration ??
                          positionSnapshot.data ??
                          Duration.zero;
                      final maxSeconds =
                          duration.inSeconds == 0 ? 1 : duration.inSeconds;
                      return Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12,
                              ),
                            ),
                            child: Slider(
                              value: position.inSeconds
                                  .clamp(0, maxSeconds)
                                  .toDouble(),
                              max: maxSeconds.toDouble(),
                              onChanged: (value) {
                                widget.player.seek(
                                  Duration(seconds: value.toInt()),
                                );
                              },
                              activeColor: AppColors.mint,
                              inactiveColor: AppColors.line,
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(position),
                                style: textTheme.bodyMedium?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              Text(
                                _formatDuration(duration),
                                style: textTheme.bodyMedium?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _SpeedPill(
                      label: widget.strings.speed,
                      value: '${widget.player.speed}x',
                      onTap: () async {
                        final selected =
                            await showModalBottomSheet<double>(
                          context: context,
                          backgroundColor: AppColors.card,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(24),
                            ),
                          ),
                          builder: (_) {
                            return SafeArea(
                              child: ListView(
                                shrinkWrap: true,
                                children: FullPlayerScreen.speedOptions
                                    .map(
                                      (speed) => ListTile(
                                        title: Text(
                                          '${speed}x',
                                          style: textTheme.bodyLarge,
                                        ),
                                        onTap: () => Navigator.of(context)
                                            .pop(speed),
                                      ),
                                    )
                                    .toList(),
                              ),
                            );
                          },
                        );
                        if (selected != null) {
                          await _setSpeed(selected);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _PlayerIcon(
                        icon: Icons.shuffle_rounded,
                        isActive: _shuffleEnabled,
                        onTap: _toggleShuffle,
                      ),
                      _PlayerIcon(
                        icon: Icons.skip_previous_rounded,
                        onTap: _playPrevious,
                        size: 34,
                      ),
                      StreamBuilder<PlayerState>(
                        stream: widget.player.playerStateStream,
                        builder: (context, snapshot) {
                          final state = snapshot.data;
                          final playing = state?.playing ?? false;
                          return _MainPlayButton(
                            isPlaying: playing,
                            onTap: () {
                              if (playing) {
                                widget.player.pause();
                              } else {
                                widget.player.play();
                              }
                            },
                          );
                        },
                      ),
                      _PlayerIcon(
                        icon: Icons.skip_next_rounded,
                        onTap: _playNext,
                        size: 34,
                      ),
                      _PlayerIcon(
                        icon: Icons.repeat_rounded,
                        isActive: widget.player.loopMode == LoopMode.one,
                        onTap: _toggleRepeat,
                      ),
                    ],
                  ),
                  if (surah != null) ...[
                    const SizedBox(height: 26),
                    Row(
                      children: [
                        Text(
                          widget.strings.ayahAudio,
                          style: textTheme.titleMedium,
                        ),
                        const Spacer(),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (!hasAyahAudio)
                      Text(
                        widget.strings.noAyahAudio,
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      )
                    else
                      ...surah.ayahItems.map(
                        (ayah) => _AyahAudioTile(
                          ayah: ayah,
                          labelPrefix: widget.strings.ayahLabel,
                          onPlay: ayah.audio.isEmpty
                              ? null
                                  : () async {
                                      await widget.player.setUrl(ayah.audio);
                                      await widget.player
                                          .setSpeed(appSettings.playbackSpeed);
                                      await widget.player.play();
                                      if (mounted) {
                                        setState(() {
                                          _currentTitle =
                                          '${surah.name} • ${widget.strings.ayahLabel} ${ayah.number}';
                                    });
                                  }
                                },
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _HeroArtwork extends StatelessWidget {
  const _HeroArtwork({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            AppColors.mint.withOpacity(0.25),
            AppColors.coral.withOpacity(0.35),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 170,
          height: 170,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [AppColors.cardAlt, AppColors.card],
            ),
            border: Border.all(color: AppColors.line),
          ),
          child: Center(
            child: Text(
              label,
              style: textTheme.titleLarge?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerIcon extends StatelessWidget {
  const _PlayerIcon({
    required this.icon,
    required this.onTap,
    this.isActive = false,
    this.size = 28,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isActive;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(
        icon,
        size: size,
        color: isActive ? AppColors.mint : AppColors.textSecondary,
      ),
    );
  }
}

class _MainPlayButton extends StatelessWidget {
  const _MainPlayButton({
    required this.isPlaying,
    required this.onTap,
  });

  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: AppColors.mint,
          shape: BoxShape.circle,
        ),
        child: Icon(
          isPlaying
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded,
          size: 36,
          color: AppColors.backgroundTop,
        ),
      ),
    );
  }
}

class _SpeedPill extends StatelessWidget {
  const _SpeedPill({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.cardAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: textTheme.labelLarge?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              value,
              style: textTheme.labelLarge?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: ListTile(
        title: Text(title, style: textTheme.bodyLarge),
        subtitle: Text(
          subtitle,
          style: textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: AppColors.textSecondary,
        ),
        onTap: onTap,
      ),
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: Text(title, style: textTheme.bodyLarge),
        subtitle: Text(
          subtitle,
          style: textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        activeColor: AppColors.mint,
      ),
    );
  }
}

class _SettingsSliderTile extends StatelessWidget {
  const _SettingsSliderTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.bodyLarge),
          const SizedBox(height: 8),
          Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
            activeColor: AppColors.mint,
            inactiveColor: AppColors.line,
          ),
        ],
      ),
    );
  }
}

class _AyahAudioTile extends StatelessWidget {
  const _AyahAudioTile({
    required this.ayah,
    required this.labelPrefix,
    required this.onPlay,
  });

  final AyahItem ayah;
  final String labelPrefix;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isEnabled = onPlay != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.cardAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              ayah.number.toString(),
              style: textTheme.labelLarge?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$labelPrefix ${ayah.number}',
                  style: textTheme.labelLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  ayah.text,
                  style: textTheme.bodyLarge,
                  textScaler: TextScaler.linear(appSettings.ayahFontScale),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onPlay,
            icon: Icon(
              isEnabled
                  ? Icons.play_circle_fill_rounded
                  : Icons.block_rounded,
              color: isEnabled ? AppColors.mint : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.strings,
    required this.currentIndex,
    required this.onTap,
  });

  final AppStrings strings;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.cardAlt,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavTap(
                onTap: () => onTap(0),
                child: _NavItem(
                  icon: Icons.home_rounded,
                  label: strings.home,
                  isActive: currentIndex == 0,
                ),
              ),
              _NavTap(
                onTap: () => onTap(1),
                child: _NavItem(
                  icon: Icons.headphones_rounded,
                  label: strings.audio,
                  isActive: currentIndex == 1,
                ),
              ),
              _NavTap(
                onTap: () => onTap(2),
                child: _NavItem(
                  icon: Icons.bookmark_rounded,
                  label: strings.saved,
                  isActive: currentIndex == 2,
                ),
              ),
              _NavTap(
                onTap: () => onTap(3),
                child: _NavItem(
                  icon: Icons.settings_rounded,
                  label: strings.settings,
                  isActive: currentIndex == 3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTap extends StatelessWidget {
  const _NavTap({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: child,
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    this.isActive = false,
  });

  final IconData icon;
  final String label;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: isActive ? AppColors.mint : AppColors.textSecondary,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: textTheme.labelLarge?.copyWith(
            color: isActive ? AppColors.mint : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, this.isSelected = false});

  final String label;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.mint : AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Text(
        label,
        style: textTheme.labelLarge?.copyWith(
          color: isSelected ? AppColors.backgroundTop : AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _AvatarBadge extends StatelessWidget {
  const _AvatarBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Icon(Icons.person_rounded, color: AppColors.textPrimary),
    );
  }
}

class _BackgroundLayer extends StatelessWidget {
  const _BackgroundLayer();

  @override
  Widget build(BuildContext context) {
    final isDark = appSettings.themeMode == ThemeMode.dark;
    final gradientColors = isDark
        ? [
            AppColors.backgroundTop,
            AppColors.backgroundMid,
            AppColors.backgroundBottom,
          ]
        : const [
            Color(0xFFF4F6FA),
            Color(0xFFE9EEF5),
            Color(0xFFDDE6F0),
          ];
    final orbOne = isDark
        ? AppColors.mint.withOpacity(0.18)
        : const Color(0xFFB7E6DA).withOpacity(0.35);
    final orbTwo = isDark
        ? AppColors.coral.withOpacity(0.16)
        : const Color(0xFFF7C2A6).withOpacity(0.35);
    final orbThree = isDark
        ? AppColors.lemon.withOpacity(0.18)
        : const Color(0xFFF6E2A3).withOpacity(0.35);

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
          ),
        ),
        Positioned(
          top: -120,
          left: -40,
          child: _SoftShape(
            color: orbOne,
            size: 220,
            angle: -0.2,
          ),
        ),
        Positioned(
          right: -60,
          top: 140,
          child: _SoftShape(
            color: orbTwo,
            size: 200,
            angle: 0.4,
          ),
        ),
        Positioned(
          left: -80,
          bottom: -120,
          child: _SoftShape(
            color: orbThree,
            size: 260,
            angle: 0.1,
          ),
        ),
      ],
    );
  }
}

class _SoftShape extends StatelessWidget {
  const _SoftShape({
    required this.color,
    required this.size,
    required this.angle,
  });

  final Color color;
  final double size;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(size * 0.35),
        ),
      ),
    );
  }
}

class AppStrings {
  AppStrings._(this._lang);

  final String _lang;

  static AppStrings forLanguage(String lang) {
    return AppStrings._(lang);
  }

  Map<String, String> get _dict {
    switch (_lang) {
      case 'tajik':
        return const {
          'subtitle': '114 сура • аудио ва тарҷумаҳо',
          'search': 'Ҷустуҷӯи сура, оят, қорӣ',
          'daily': 'Қироати рӯзона',
          'quick': 'Зуд амалҳо',
          'surahs': 'Сураҳо',
          'ayahs': 'Оятҳо',
          'favorites': 'Дӯстдоштаҳо',
          'no_favorites': 'Ҳанӯз дӯстдошта нест.',
          'settings_title': 'Танзимот',
          'audio_mode': 'Ҷараён + офлайн',
          'language': 'Забон',
          'reciter': 'Қорӣ (URL)',
          'theme': 'Мавзуъ',
          'dark': 'Торик',
          'light': 'Равшан',
          'font_size': 'Андозаи матн',
          'clear_downloads': 'Пок кардани боргириҳо',
          'clear_downloads_hint': 'Ҳамаи файлҳои аудиоии боргирифтаро нест мекунед.',
          'downloads_cleared': 'Боргириҳо пок карда шуданд.',
          'cancel': 'Бекор',
          'save': 'Нигоҳ доштан',
          'delete': 'Нест кардан',
          'view_all': 'Ҳама',
          'tag_all': 'Ҳама',
          'tag_meccan': 'Маккӣ',
          'tag_medinan': 'Мадинӣ',
          'no_surahs': 'Барои ин забон сураҳо ёфт нашуд.',
          'audio_missing': 'Суроғаи аудио нест.',
          'download_failed': 'Боргирӣ нашуд. Линкро санҷед.',
          'coming_soon': 'Ба зудӣ.',
          'open_player': 'Плеер',
          'speed': 'Суръат',
          'repeat': 'Такрор',
          'shuffle': 'Омехта',
          'ayah_audio': 'Аудиои оят',
          'no_ayah_audio': 'Аудиои оят дастрас нест.',
          'ayah_label': 'Оят',
          'play': 'Пахш',
          'home': 'Асосӣ',
          'audio': 'Аудио',
          'saved': 'Нигоҳдошташуда',
          'settings': 'Танзимот',
          'juz': 'Ҷузъ',
          'lang_label': 'тоҷикӣ',
          'hero_range': 'Оят 1–10',
          'badge_friday': 'Ҷумъа',
          'badge_minutes': '12 дақ',
        };
      case 'russian':
        return const {
          'subtitle': '114 сур • аудио и переводы',
          'search': 'Поиск: сура, аят, чтец',
          'daily': 'Ежедневное чтение',
          'quick': 'Быстрые действия',
          'surahs': 'Суры',
          'ayahs': 'Аяты',
          'favorites': 'Избранное',
          'no_favorites': 'Пока нет избранного.',
          'settings_title': 'Настройки',
          'audio_mode': 'Стриминг + офлайн',
          'language': 'Язык',
          'reciter': 'Чтец (URL)',
          'theme': 'Тема',
          'dark': 'Тёмная',
          'light': 'Светлая',
          'font_size': 'Размер текста',
          'clear_downloads': 'Очистить загрузки',
          'clear_downloads_hint': 'Удалить все загруженные аудиофайлы.',
          'downloads_cleared': 'Загрузки очищены.',
          'cancel': 'Отмена',
          'save': 'Сохранить',
          'delete': 'Удалить',
          'view_all': 'Все',
          'tag_all': 'Все',
          'tag_meccan': 'Мекканские',
          'tag_medinan': 'Мединские',
          'no_surahs': 'Для этого языка суры не найдены.',
          'audio_missing': 'Нет ссылки на аудио.',
          'download_failed': 'Скачать не удалось. Проверьте ссылку.',
          'coming_soon': 'Скоро будет.',
          'open_player': 'Плеер',
          'speed': 'Скорость',
          'repeat': 'Повтор',
          'shuffle': 'Случайно',
          'ayah_audio': 'Аудио аятов',
          'no_ayah_audio': 'Аудио по аятам недоступно.',
          'ayah_label': 'Аят',
          'play': 'Играть',
          'home': 'Главная',
          'audio': 'Аудио',
          'saved': 'Сохранённое',
          'settings': 'Настройки',
          'juz': 'Джуз',
          'lang_label': 'русский',
          'hero_range': 'Аяты 1–10',
          'badge_friday': 'Пятница',
          'badge_minutes': '12 мин',
        };
      default:
        return const {
          'subtitle': '114 sura • audio va tarjimalar',
          'search': 'Sura, oyat, qorini qidiring',
          'daily': 'Kundalik tilovat',
          'quick': 'Tezkor amallar',
          'surahs': 'Suralar',
          'ayahs': 'Oyatlar',
          'favorites': 'Sevimlilar',
          'no_favorites': 'Hozircha sevimlilar yo‘q.',
          'settings_title': 'Sozlamalar',
          'audio_mode': 'Onlayn + oflayn',
          'language': 'Til',
          'reciter': 'Qori (URL)',
          'theme': 'Mavzu',
          'dark': 'Tungi',
          'light': 'Yorug‘',
          'font_size': 'Matn o‘lchami',
          'clear_downloads': 'Yuklab olinganlarni tozalash',
          'clear_downloads_hint': 'Barcha yuklab olingan audio fayllar o‘chiriladi.',
          'downloads_cleared': 'Yuklab olinganlar tozalandi.',
          'cancel': 'Bekor',
          'save': 'Saqlash',
          'delete': 'O‘chirish',
          'view_all': 'Barchasi',
          'tag_all': 'Barchasi',
          'tag_meccan': 'Makkalik',
          'tag_medinan': 'Madinallik',
          'no_surahs': 'Bu til uchun suralar topilmadi.',
          'audio_missing': "Audio URL yo'q.",
          'download_failed': "Yuklab bo'lmadi. Havolani tekshiring.",
          'coming_soon': 'Tez orada.',
          'open_player': 'Pleyer',
          'speed': 'Tezlik',
          'repeat': 'Takror',
          'shuffle': 'Aralashtirish',
          'ayah_audio': 'Oyat audio',
          'no_ayah_audio': "Oyat audiosi mavjud emas.",
          'ayah_label': 'Oyat',
          'play': 'Ijro',
          'home': 'Bosh',
          'audio': 'Audio',
          'saved': 'Saqlangan',
          'settings': 'Sozlamalar',
          'juz': 'Juz',
          'lang_label': "o'zbek",
          'hero_range': 'Oyat 1–10',
          'badge_friday': 'Juma',
          'badge_minutes': '12 daq',
        };
    }
  }

  String get subtitle => _dict['subtitle']!;
  String get searchPlaceholder => _dict['search']!;
  String get dailyRecitation => _dict['daily']!;
  String get quickActions => _dict['quick']!;
  String get surahsTitle => _dict['surahs']!;
  String get ayahsTitle => _dict['ayahs']!;
  String get favoritesTitle => _dict['favorites']!;
  String get noFavorites => _dict['no_favorites']!;
  String get settingsTitle => _dict['settings_title']!;
  String get audioMode => _dict['audio_mode']!;
  String get languageLabel => _dict['language']!;
  String get reciter => _dict['reciter']!;
  String get theme => _dict['theme']!;
  String get darkLabel => _dict['dark']!;
  String get lightLabel => _dict['light']!;
  String get fontSize => _dict['font_size']!;
  String get clearDownloads => _dict['clear_downloads']!;
  String get clearDownloadsHint => _dict['clear_downloads_hint']!;
  String get downloadsCleared => _dict['downloads_cleared']!;
  String get cancel => _dict['cancel']!;
  String get save => _dict['save']!;
  String get delete => _dict['delete']!;
  String get viewAll => _dict['view_all']!;
  String get tagAll => _dict['tag_all']!;
  String get tagMeccan => _dict['tag_meccan']!;
  String get tagMedinan => _dict['tag_medinan']!;
  String get noSurahs => _dict['no_surahs']!;
  String get audioMissing => _dict['audio_missing']!;
  String get downloadFailed => _dict['download_failed']!;
  String get comingSoon => _dict['coming_soon']!;
  String get openPlayer => _dict['open_player']!;
  String get speed => _dict['speed']!;
  String get repeat => _dict['repeat']!;
  String get shuffle => _dict['shuffle']!;
  String get ayahAudio => _dict['ayah_audio']!;
  String get noAyahAudio => _dict['no_ayah_audio']!;
  String get ayahLabel => _dict['ayah_label']!;
  String get play => _dict['play']!;
  String get home => _dict['home']!;
  String get audio => _dict['audio']!;
  String get saved => _dict['saved']!;
  String get settings => _dict['settings']!;
  String get juz => _dict['juz']!;
  String get currentLanguageLabel => _dict['lang_label']!;
  String get heroRange => _dict['hero_range']!;
  String get badgeFriday => _dict['badge_friday']!;
  String get badgeMinutes => _dict['badge_minutes']!;

  List<String> get languageLabels {
    return const ['Тоҷикӣ', "O'zbek", 'Русский'];
  }

  String nowPlaying(String name) {
    switch (_lang) {
      case 'tajik':
        return 'Ҳоло пахш мешавад: $name';
      case 'russian':
        return 'Сейчас играет: $name';
      default:
        return 'Hozir ijro etilmoqda: $name';
    }
  }

  String downloaded(String name) {
    switch (_lang) {
      case 'tajik':
        return 'Боргирӣ шуд: $name';
      case 'russian':
        return 'Скачано: $name';
      default:
        return 'Yuklab olindi: $name';
    }
  }

  String revelationLabel(String value) {
    final normalized = value.toLowerCase();
    if (normalized == 'meccan') return tagMeccan;
    if (normalized == 'medinan') return tagMedinan;
    return value;
  }
}

class AppSettingsController extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.dark;
  double playbackSpeed = 1.0;
  double ayahFontScale = 1.0;
  String reciterBaseUrl =
      'https://cdn.equran.id/audio-full/Abdullah-Al-Juhany';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('theme_dark') ?? true;
    themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    playbackSpeed = prefs.getDouble('playback_speed') ?? 1.0;
    ayahFontScale = prefs.getDouble('ayah_font_scale') ?? 1.0;
    reciterBaseUrl =
        prefs.getString('reciter_base') ?? reciterBaseUrl;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('theme_dark', mode == ThemeMode.dark);
    notifyListeners();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    playbackSpeed = speed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('playback_speed', speed);
    notifyListeners();
  }

  Future<void> setAyahFontScale(double scale) async {
    ayahFontScale = scale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('ayah_font_scale', scale);
    notifyListeners();
  }

  Future<void> setReciterBaseUrl(String url) async {
    reciterBaseUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reciter_base', url);
    notifyListeners();
  }
}

class AppColors {
  static bool get _isDark => appSettings.themeMode == ThemeMode.dark;

  static Color get backgroundTop =>
      _isDark ? const Color(0xFF0B0E14) : const Color(0xFFF6F7FA);
  static Color get backgroundMid =>
      _isDark ? const Color(0xFF0F1522) : const Color(0xFFEFF2F7);
  static Color get backgroundBottom =>
      _isDark ? const Color(0xFF121A28) : const Color(0xFFE4E9F1);
  static Color get card =>
      _isDark ? const Color(0xFF151C29) : const Color(0xFFFFFFFF);
  static Color get cardAlt =>
      _isDark ? const Color(0xFF1B2433) : const Color(0xFFF1F4F9);
  static Color get line =>
      _isDark ? const Color(0xFF263247) : const Color(0xFFD6DEE8);
  static Color get textPrimary =>
      _isDark ? const Color(0xFFF5F7FB) : const Color(0xFF1B2430);
  static Color get textSecondary =>
      _isDark ? const Color(0xFFB9C2D3) : const Color(0xFF5C6A7A);
  static const mint = Color(0xFF4DE0C3);
  static const coral = Color(0xFFFF8A63);
  static const lemon = Color(0xFFF6D36B);
}
