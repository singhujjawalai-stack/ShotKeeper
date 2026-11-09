import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'dart:io';

void main() => runApp(const ShotKeeperApp());

void _logPlatformError(String method, Object error) =>
    debugPrint('ShotKeeper platform call "$method" failed: $error');

// ---- Design tokens ----------------------------------------------------------
const double kRadiusCard = 18.0;   // cards & sheets
const double kRadiusSheet = 20.0;  // dialogs & bottom sheets
const double kRadiusField = 12.0;  // text fields, inner clips, banners
const double kRadiusTile = 14.0;   // grid tiles & stat chips
const int kTrashGraceMs = 7 * 24 * 60 * 60 * 1000;

/// Human-readable remaining time ("3d 5h", "42m", "8s").
String formatTimeRemaining(int targetEpochMs) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final remainingMs = targetEpochMs - now;
  if (remainingMs <= 0) return 'Deleting soon';

  final totalSeconds = remainingMs ~/ 1000;
  final totalMinutes = totalSeconds ~/ 60;
  final totalHours = totalMinutes ~/ 60;
  final totalDays = totalHours ~/ 24;
  final totalWeeks = totalDays ~/ 7;
  final totalMonths = totalDays ~/ 30;
  final totalYears = totalDays ~/ 365;

  if (totalYears >= 1) {
    final remMonths = (totalDays % 365) ~/ 30;
    return remMonths > 0 ? '${totalYears}y ${remMonths}mo' : '${totalYears}y';
  } else if (totalMonths >= 1) {
    final remDays = totalDays % 30;
    return remDays > 0 ? '${totalMonths}mo ${remDays}d' : '${totalMonths}mo';
  } else if (totalWeeks >= 1) {
    final remDays = totalDays % 7;
    return remDays > 0 ? '${totalWeeks}w ${remDays}d' : '${totalWeeks}w';
  } else if (totalDays >= 1) {
    final remHours = totalHours % 24;
    return remHours > 0 ? '${totalDays}d ${remHours}h' : '${totalDays}d';
  } else if (totalHours >= 1) {
    final remMinutes = totalMinutes % 60;
    return remMinutes > 0 ? '${totalHours}h ${remMinutes}m' : '${totalHours}h';
  } else if (totalMinutes >= 1) {
    final remSeconds = totalSeconds % 60;
    return remSeconds > 0 ? '${totalMinutes}m ${remSeconds}s' : '${totalMinutes}m';
  } else {
    return '${totalSeconds}s';
  }
}

/// Compact relative timestamp for tile captions ("2h ago", "Mar 3").
String formatRelativeDate(int? addedSeconds) {
  if (addedSeconds == null || addedSeconds <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(addedSeconds * 1000);
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[dt.month - 1]} ${dt.day}';
}

class ShotKeeperApp extends StatelessWidget {
  const ShotKeeperApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShotKeeper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ).copyWith(
          surface: const Color(0xFFFFFFFF),
          onSurface: const Color(0xFF1A1A2E),
          primary: const Color(0xFF4F46E5),
          secondary: const Color(0xFF818CF8),
          surfaceTint: const Color(0xFFE0E7FF),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F0FA),
        fontFamily: 'Inter',
        textTheme: const TextTheme(
          titleLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5, color: Color(0xFF1A1A2E)),
          titleMedium: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.3, color: Color(0xFF1A1A2E)),
          bodyLarge: TextStyle(fontWeight: FontWeight.w500, letterSpacing: 0.15, color: Color(0xFF374151)),
          bodyMedium: TextStyle(fontWeight: FontWeight.w400, letterSpacing: 0.15, color: Color(0xFF6B7280)),
        ),
        cardTheme: CardThemeData(
          elevation: 2.5,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          color: const Color(0xFFFFFFFF),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusCard)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF8F7FB),
          foregroundColor: Color(0xFF1A1A2E),
          elevation: 0,
          titleTextStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 20, letterSpacing: -0.3, color: Color(0xFF1A1A2E)),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ).copyWith(
          surface: const Color(0xFF000000),
          onSurface: const Color(0xFFEAEAEA),
          primary: const Color(0xFF6366F1),
          secondary: const Color(0xFF818CF8),
          surfaceTint: const Color(0xFF312E81),
          primaryContainer: const Color(0xFF312E81),
        ),
        scaffoldBackgroundColor: const Color(0xFF000000),
        fontFamily: 'Inter',
        textTheme: const TextTheme(
          titleLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5, color: Color(0xFFEAEAEA)),
          titleMedium: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.3, color: Color(0xFFEAEAEA)),
          bodyLarge: TextStyle(fontWeight: FontWeight.w500, letterSpacing: 0.15, color: Color(0xFFEAEAEA)),
          bodyMedium: TextStyle(fontWeight: FontWeight.w400, letterSpacing: 0.15, color: Color(0xFF9CA3AF)),
        ),
        cardTheme: CardThemeData(
          elevation: 4,
          shadowColor: Colors.black.withValues(alpha: 0.8),
          color: const Color(0xFF13131B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusCard)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF000000),
          foregroundColor: Color(0xFFEAEAEA),
          elevation: 0,
          titleTextStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 20, letterSpacing: -0.3, color: Color(0xFFEAEAEA)),
        ),
        dividerTheme: DividerThemeData(color: Colors.indigo.withValues(alpha: 0.08)),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? const Color(0xFF4F46E5) : const Color(0xFFE0E7FF)),
          trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? const Color(0xFFE0E7FF) : const Color(0xFFF8F7FB)),
        ),
      ),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}

enum RetentionPeriod {
  day('1 Day', 1), threeDays('3 Days', 3), week('1 Week', 7),
  twoWeeks('2 Weeks', 14), month('1 Month', 30), threeMonths('3 Months', 90),
  sixMonths('6 Months', 180), year('1 Year', 365), forever('Forever', null);
  const RetentionPeriod(this.label, this.days);
  final String label; final int? days;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _isEnabled = false;
  RetentionPeriod _selectedPeriod = RetentionPeriod.threeDays;
  List<dynamic> _detectedImages = [];
  final List<String> _selectedBatchPaths = [];
  Map<String, int> _scheduledDeletions = {};
  Timer? _liveTicker;
  bool _batteryExempt = true;
  bool _ticking = false;
  // Trash: original path -> {trash, name, expiry}
  final Map<String, Map<String, dynamic>> _trash = {};
  Set<String> _pinned = {};
  bool _showTrash = false;
  bool _loaded = false;
  // Auto-pilot rule
  bool _autoEnabled = false;
  final TextEditingController _autoValueController = TextEditingController(text: '24');
  String _autoUnit = 'hours';
  String _searchQuery = '';
  bool _filterScheduledOnly = false;
  bool _filterPinnedOnly = false;
  bool _newestFirst = true;
  final TextEditingController _searchController = TextEditingController();

  static const _keyEnabled = 'shot_keeper_enabled';
  static const _keyPeriod = 'shot_keeper_period';
  static const _keyAutoEnabled = 'shot_keeper_auto_enabled';
  static const _keyAutoSeconds = 'shot_keeper_auto_seconds';
  static const _platform = MethodChannel('shotkeeper/permission');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _loadCount();
    _loadDetectedImages();
    _loadScheduledDeletions();
    _loadTrash();
    _loadPinned();
    _loadAutoRule();
    _checkBatteryStatus();
    _initNotificationIntentListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _liveTicker?.cancel();
    _autoValueController.dispose();
    super.dispose();
  }

  /// Native code (detector service, dialogs, scheduled deletions) changes the
  /// gallery/trash/schedules in the background — reconcile everything whenever
  /// the user brings the app back to the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _loadDetectedImages();
      _loadScheduledDeletions();
      _loadTrash();
      _loadPinned();
    }
  }

  void _initNotificationIntentListener() {
    _platform.setMethodCallHandler((call) async {
      if (call.method == 'on_notification_intent') {
        final data = call.arguments;
        if (data is Map && data['path'] != null) {
          _handleNotificationScreenshot(data['path'].toString());
        }
      }
    });
    _checkPendingNotificationIntent();
  }

  Future<void> _checkPendingNotificationIntent() async {
    try {
      final result = await _platform.invokeMethod('get_notification_intent');
      if (result is Map && result['path'] != null) {
        _handleNotificationScreenshot(result['path'].toString());
      }
    } catch (e) {
      _logPlatformError('get_notification_intent', e);
    }
  }

  void _handleNotificationScreenshot(String path) {
    _loadDetectedImages();
    _loadScheduledDeletions();
    _loadTrash(); // native side may have moved things around before this
    if (path.isNotEmpty && File(path).existsSync()) {
      _openScheduleDialog(paths: [path]);
    }
  }

  /// Ticker runs only while there is something with a countdown (scheduled
  /// deletions or trash grace periods), and rebuilds only the gallery subtree.
  void _syncTicker() {
    final needed = _scheduledDeletions.isNotEmpty || _trash.isNotEmpty;
    if (needed && _liveTicker == null) {
      _liveTicker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    } else if (!needed && _liveTicker != null) {
      _liveTicker?.cancel();
      _liveTicker = null;
    }
  }

  Future<void> _onTick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      bool hasDue = false;
      for (final targetMs in _scheduledDeletions.values) {
        if (now >= targetMs) {
          hasDue = true;
          break;
        }
      }

      if (hasDue) {
        List<String> failed = const [];
        try {
          final result = await _platform.invokeMethod('check_due_deletions');
          if (result is Map) {
            final f = result['failed'];
            if (f is List) failed = f.map((e) => e.toString()).toList();
          }
        } catch (e) {
          _logPlatformError('check_due_deletions', e);
        }
        await _loadScheduledDeletions();
        await _loadDetectedImages();
        await _loadTrash(); // deleted shots land in trash — keep the counter live
        if (failed.isNotEmpty) {
          _showSnack('Could not delete ${failed.length} screenshot(s) — will retry', color: Colors.redAccent);
        }
      }
      if (mounted) setState(() {}); // Refresh countdown badges
    } finally {
      _ticking = false;
    }
  }

  /// Battery-optimization exemption keeps the detector alive through Doze and
  /// OEM task killers, so ask for it once and keep a banner while restricted.
  Future<void> _checkBatteryStatus() async {
    try {
      final exempt = await _platform.invokeMethod<bool>('get_battery_optimization');
      if (exempt == false && mounted) setState(() => _batteryExempt = false);
    } catch (e) {
      _logPlatformError('get_battery_optimization', e);
    }
  }

  Future<void> _requestBatteryExemption() async {
    try {
      await _platform.invokeMethod('request_ignore_battery_optimization');
      final exempt = await _platform.invokeMethod<bool>('get_battery_optimization');
      if (mounted) setState(() => _batteryExempt = exempt ?? true);
      _showSnack(exempt == true
          ? 'Background detection is now unrestricted'
          : 'Still restricted — choose "Unrestricted" for reliable detection');
    } catch (e) {
      _logPlatformError('request_ignore_battery_optimization', e);
    }
  }

  Future<void> _loadCount() async {
    try {
      await _platform.invokeMethod('get_count');
    } catch (e) {
      _logPlatformError('get_count', e);
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_keyEnabled) ?? false;
    if (mounted) {
      setState(() {
        _isEnabled = enabled;
        final savedIndex = prefs.getInt(_keyPeriod) ?? 2;
        if (savedIndex < RetentionPeriod.values.length) {
          _selectedPeriod = RetentionPeriod.values[savedIndex];
        }
      });
    }
    if (enabled && Platform.isAndroid) {
      final sdkInt = await _platform.invokeMethod<int>('get_sdk_int') ?? 0;
      final storageGranted = sdkInt >= 30
          ? (await Permission.manageExternalStorage.status).isGranted
          : (await Permission.storage.status).isGranted;
      if (storageGranted) {
        try {
          await _platform.invokeMethod('start_detector');
        } catch (e) {
          _logPlatformError('start_detector', e);
        }
      }
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, _isEnabled);
    await prefs.setInt(_keyPeriod, _selectedPeriod.index);
  }

  Future<void> _loadScheduledDeletions() async {
    try {
      final result = await _platform.invokeMethod('get_scheduled_deletions');
      if (result is Map) {
        final map = <String, int>{};
        result.forEach((key, value) {
          final epoch = int.tryParse(value.toString());
          if (epoch != null) {
            map[key.toString()] = epoch;
          }
        });
        if (mounted) {
          setState(() => _scheduledDeletions = map);
        }
        _syncTicker();
      }
    } catch (e) {
      _logPlatformError('get_scheduled_deletions', e);
    }
  }

  Future<void> _loadDetectedImages() async {
    try {
      final result = await _platform.invokeMethod('get_detected_screenshots');
      if (result is List && mounted) {
        final list = List<Map<dynamic, dynamic>>.from(result);
        // Native side already returns items sorted newest-first.

        setState(() {
          _detectedImages = list;
          _loaded = true;
          final existingPaths = list.map((e) => e['path']?.toString()).toSet();
          _selectedBatchPaths.removeWhere((p) => !existingPaths.contains(p));
        });
      }
    } catch (e) {
      _logPlatformError('get_detected_screenshots', e);
    }
    if (mounted) setState(() => _loaded = true);
    await _loadScheduledDeletions();
  }

  Future<bool> _checkStoragePermission() async {
    if (!Platform.isAndroid) return true;
    final sdkInt = await _platform.invokeMethod<int>('get_sdk_int') ?? 0;
    if (sdkInt >= 30) {
      final status = await Permission.manageExternalStorage.status;
      final hasAllFiles = status.isGranted ||
          (await Permission.manageExternalStorage.request()).isGranted;
      if (!hasAllFiles) return false;
      if (sdkInt >= 33) {
        final photosStatus = await Permission.photos.status;
        return photosStatus.isGranted || (await Permission.photos.request()).isGranted;
      }
      return true;
    }
    final status = await Permission.storage.status;
    if (status.isGranted) return true;
    return (await Permission.storage.request()).isGranted;
  }

  Future<void> _toggleEnabled(bool value) async {
    if (!value) {
      setState(() => _isEnabled = false);
      await _saveSettings();
      if (Platform.isAndroid) {
        try {
          await _platform.invokeMethod('stop_detector');
        } catch (e) {
          _logPlatformError('stop_detector', e);
        }
      }
      return;
    }
    final hasPermission = await _checkStoragePermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Storage permission is required')),
        );
      }
      return;
    }
    if (Platform.isAndroid) {
      final sdkInt = await _platform.invokeMethod<int>('get_sdk_int') ?? 0;
      if (sdkInt >= 33 && !(await Permission.notification.request()).isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Allow ShotKeeper notifications to see screenshot alerts')),
          );
        }
        return;
      }
    }
    setState(() => _isEnabled = value);
    HapticFeedback.mediumImpact();
    await _saveSettings();
    if (Platform.isAndroid && value) {
      try {
        await _platform.invokeMethod('start_detector');
      } catch (e) {
        _logPlatformError('start_detector', e);
        _showSnack('Detector could not start — see logs', color: Colors.redAccent);
      }
    }
  }

  void _toggleBatchSelection(String path) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_selectedBatchPaths.contains(path)) {
        _selectedBatchPaths.remove(path);
      } else {
        _selectedBatchPaths.add(path);
      }
    });
  }

  void _selectAllBatch() {
    HapticFeedback.lightImpact();
    setState(() {
      if (_showTrash) {
        for (final p in _trash.keys) {
          if (!_selectedBatchPaths.contains(p)) _selectedBatchPaths.add(p);
        }
      } else {
        for (final item in _detectedImages) {
          final p = item['path']?.toString();
          if (p != null && p.isNotEmpty && !_selectedBatchPaths.contains(p)) {
            _selectedBatchPaths.add(p);
          }
        }
      }
    });
  }

  void _clearBatch() => setState(() => _selectedBatchPaths.clear());

  /// Red destructive "Delete Now?" confirmation used by delete flows.
  Future<bool> _confirmDeleteNow({required String content}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSheet)),
        title: const Text('Delete Now?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(content),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF6B7280)),
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(dialogCtx, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(dialogCtx, true),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  void _showSnack(String message, {Color? color, String? actionLabel, VoidCallback? onAction}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: (actionLabel != null && onAction != null)
            ? SnackBarAction(label: actionLabel, textColor: Colors.amber, onPressed: onAction)
            : null,
      ),
    );
  }

  /// Deletes one or more screenshots (batch handled natively in a single call).
  /// Returns how many really moved, which failed, and which were already in
  /// trash (deleted from elsewhere earlier — no Undo needed for those).
  Future<({List<String> failed, List<String> moved, List<String> alreadyTrashed})>
      _deletePaths(List<String> paths) async {
    if (paths.isEmpty) {
      return (failed: <String>[], moved: <String>[], alreadyTrashed: <String>[]);
    }
    HapticFeedback.lightImpact();
    final failed = <String>[];
    final moved = <String>[];
    final alreadyTrashed = <String>[];
    try {
      if (paths.length > 1) {
        final result = await _platform.invokeMethod('delete_batch', {'paths': paths});
        if (result is Map) {
          final failures = result['failed'];
          if (failures is List) failed.addAll(failures.map((e) => e.toString()));
          final ok = result['deleted'];
          if (ok is int) moved.addAll(paths.where((p) => !failed.contains(p)).take(ok));
        } else {
          failed.addAll(paths);
        }
      } else {
        final result = await _platform.invokeMethod('delete_now', {'path': paths.first});
        if (result is Map) {
          if (result['moved'] == true) {
            moved.add(paths.first);
          } else if (result['already_trashed'] == true) {
            alreadyTrashed.add(paths.first);
          } else {
            failed.add(paths.first);
          }
        } else if (result == true) {
          // Legacy native handler (bool-only result)
          moved.add(paths.first);
        } else {
          failed.add(paths.first);
        }
      }
    } catch (e) {
      _logPlatformError('delete', e);
      failed.addAll(paths);
    }
    return (failed: failed, moved: moved, alreadyTrashed: alreadyTrashed);
  }

  // ---- Trash -----------------------------------------------------------------

  Future<void> _loadTrash() async {
    try {
      final result = await _platform.invokeMethod('get_trash');
      if (result is List && mounted) {
        final map = <String, Map<String, dynamic>>{};
        for (final item in result) {
          if (item is Map) {
            final path = item['path']?.toString() ?? '';
            if (path.isEmpty) continue;
            map[path] = {
              'trash': item['trash']?.toString() ?? '',
              'name': item['name']?.toString() ?? 'unknown',
              'expiry': int.tryParse(item['expiry']?.toString() ?? '') ?? 0,
            };
          }
        }
        setState(() => _trash..clear()..addAll(map));
        _syncTicker();
      }
    } catch (e) {
      _logPlatformError('get_trash', e);
    }
  }

  /// Undoes a trash move for every given original path. Used by the Undo
  /// snackbar action after a delete.
  Future<void> _undoDelete(List<String> originalPaths) async {
    var restored = 0;
    for (final path in originalPaths) {
      try {
        final ok = await _platform.invokeMethod('restore_from_trash', {'path': path});
        if (ok == true) restored++;
      } catch (e) {
        _logPlatformError('restore_from_trash', e);
      }
    }
    await _loadTrash();
    await _loadDetectedImages();
    await _loadScheduledDeletions();
    _showSnack(restored == originalPaths.length
        ? 'Restored to gallery'
        : 'Restored $restored of ${originalPaths.length}');
  }

  Future<void> _restoreFromTrash(String originalPath) async {
    var ok = false;
    try {
      ok = await _platform.invokeMethod('restore_from_trash', {'path': originalPath}) == true;
    } catch (e) {
      _logPlatformError('restore_from_trash', e);
    }
    if (ok) {
      await _loadTrash();
      await _loadDetectedImages();
      await _loadScheduledDeletions();
      _showSnack('Restored to gallery');
    } else {
      _showSnack('Could not restore', color: Colors.redAccent);
    }
  }

  Future<void> _permanentDelete(String originalPath, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSheet)),
        title: const Text('Delete permanently?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('"$name" will be permanently deleted immediately. This cannot be undone.'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(dialogCtx, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
            child: const Text('Delete forever', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(dialogCtx, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _platform.invokeMethod('permanent_delete', {'path': originalPath});
    } catch (e) {
      _logPlatformError('permanent_delete', e);
      _showSnack('Could not delete permanently', color: Colors.redAccent);
      return;
    }
    await _loadTrash();
    _showSnack('Permanently deleted');
  }

  Future<void> _emptyTrash() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSheet)),
        title: const Text('Empty trash?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('${_trash.length} screenshot(s) will be permanently deleted. This cannot be undone.'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(dialogCtx, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
            child: const Text('Empty trash', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(dialogCtx, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _platform.invokeMethod('empty_trash');
    } catch (e) {
      _logPlatformError('empty_trash', e);
      _showSnack('Could not empty trash', color: Colors.redAccent);
      return;
    }
    await _loadTrash();
    _showSnack('Trash emptied');
  }

  // ---- Pins (Keep Forever) ----------------------------------------------------

  Future<void> _loadPinned() async {
    try {
      final result = await _platform.invokeMethod('get_pinned');
      if (result is List && mounted) {
        setState(() => _pinned = result.map((e) => e.toString()).toSet());
      }
    } catch (e) {
      _logPlatformError('get_pinned', e);
    }
  }

  Future<void> _pinToggle(String path) async {
    final wasPinned = _pinned.contains(path);
    HapticFeedback.lightImpact();
    try {
      await _platform.invokeMethod('set_pinned', {'path': path, 'pinned': !wasPinned});
    } catch (e) {
      _logPlatformError('set_pinned', e);
      _showSnack('Could not update pin', color: Colors.redAccent);
      return;
    }
    await _loadPinned();
    await _loadScheduledDeletions();
    await _loadDetectedImages();
    _showSnack(!wasPinned ? 'Kept forever — deletion timers cancelled' : 'Pin removed');
  }

  // ---- Auto-pilot rule ---------------------------------------------------------

  Future<void> _loadAutoRule() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final enabled = prefs.getBool(_keyAutoEnabled) ?? false;
    final saved = prefs.getInt(_keyAutoSeconds);
    if (saved != null && saved > 0) {
      final preset = _secondsToAutoPreset(saved);
      _autoValueController.text = preset.$1.toString();
      _autoUnit = preset.$2;
    }
    setState(() => _autoEnabled = enabled);
  }

  /// Best-effort inverse mapping of stored seconds back to a value + unit pair.
  (int, String) _secondsToAutoPreset(int seconds) {
    const units = <(String, int)>[
      ('years', 31536000), ('months', 2592000), ('weeks', 604800),
      ('days', 86400), ('hours', 3600), ('minutes', 60),
    ];
    for (final (name, factor) in units) {
      if (seconds >= factor && seconds % factor == 0) {
        return (seconds ~/ factor, name);
      }
    }
    return ((seconds ~/ 60).clamp(1, 1000000).toInt(), 'minutes');
  }

  int _autoDelaySeconds() {
    final v = int.tryParse(_autoValueController.text) ?? 24;
    const factors = {
      'minutes': 60, 'hours': 3600, 'days': 86400,
      'weeks': 604800, 'months': 2592000, 'years': 31536000,
    };
    return v.clamp(1, 100000).toInt() * factors[_autoUnit]!;
  }

  Future<void> _toggleAutoRule(bool value) async {
    HapticFeedback.mediumImpact();
    setState(() => _autoEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoEnabled, value);
    await prefs.setInt(_keyAutoSeconds, _autoDelaySeconds());
    _showSnack(value
        ? 'Auto-pilot on — new screenshots are scheduled automatically'
        : 'Auto-pilot off');
  }

  Future<void> _saveAutoRule() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyAutoSeconds, _autoDelaySeconds());
  }

  String _formatDateTime(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final monthName = months[dt.month - 1];
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$monthName ${dt.day}, ${dt.year} at $hour:$minute $ampm';
  }

  /// Calendar-aware target computation: months/years respect real calendar
  /// lengths (Jan 31 + 1 month = Feb 28) instead of hard-coded 30/365-day
  /// shortcuts that drift from what the user sees in the preview.
  DateTime _computeTargetDate(String valueStr, String unit) {
    final value = int.tryParse(valueStr) ?? 4;
    final now = DateTime.now();
    switch (unit) {
      case 'minutes':
        return now.add(Duration(minutes: value.clamp(1, 525599).toInt()));
      case 'hours':
        return now.add(Duration(hours: value.clamp(1, 8759).toInt()));
      case 'days':
        return now.add(Duration(days: value.clamp(1, 3650).toInt()));
      case 'weeks':
        return now.add(Duration(days: value.clamp(1, 520).toInt() * 7));
      case 'months':
        return _addCalendarMonths(now, value.clamp(1, 120).toInt());
      case 'years':
        return _addCalendarMonths(now, value.clamp(1, 100).toInt() * 12);
      default:
        return now.add(Duration(hours: value.clamp(1, 8759).toInt()));
    }
  }

  DateTime _addCalendarMonths(DateTime from, int months) {
    final total = from.month - 1 + months;
    final year = from.year + total ~/ 12;
    final month = total % 12 + 1;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, from.day.clamp(1, daysInMonth).toInt(), from.hour, from.minute, from.second);
  }

  String _computeDeleteDateLive(String valueStr, String unit) =>
      _formatDateTime(_computeTargetDate(valueStr, unit));

  void _openScheduleDialog({required List<String> paths}) {
    final valueController = TextEditingController(text: '4');
    String unitValue = 'hours';
    final isBatch = paths.length > 1;

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (ctx2, setDialog) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final primaryColor = Theme.of(context).colorScheme.primary;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSheet)),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            title: Row(
              children: [
                Icon(Icons.schedule, color: primaryColor, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isBatch ? 'Batch Schedule Deletion' : 'Schedule Deletion',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isBatch && paths.isNotEmpty && File(paths.first).existsSync()) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(kRadiusField),
                      child: Container(
                        height: 140,
                        width: double.infinity,
                        color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFE5E7EB),
                        child: Image.file(
                          File(paths.first),
                          fit: BoxFit.contain,
                          cacheWidth: 720,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        paths.first.split(RegExp(r'[/\\]')).last,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    isBatch
                        ? 'Set retention duration for ${paths.length} screenshots:'
                        : 'Set retention duration:',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (label, pValue, pUnit) in const <(String, String, String)>[
                        ('1h', '1', 'hours'),
                        ('4h', '4', 'hours'),
                        ('1d', '1', 'days'),
                        ('3d', '3', 'days'),
                        ('1w', '1', 'weeks'),
                        ('1mo', '1', 'months'),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: valueController.text == pValue && unitValue == pUnit
                                ? primaryColor
                                : (isDark ? Colors.white70 : Colors.black54),
                          ),
                          selected: valueController.text == pValue && unitValue == pUnit,
                          selectedColor: primaryColor.withValues(alpha: 0.18),
                          checkmarkColor: primaryColor,
                          visualDensity: VisualDensity.compact,
                          showCheckmark: false,
                          onSelected: (_) =>
                              setDialog(() { valueController.text = pValue; unitValue = pUnit; }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: valueController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Value',
                            filled: true,
                            fillColor: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF3F4F6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(kRadiusField),
                            ),
                          ),
                          onChanged: (v) => setDialog(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: unitValue,
                          decoration: InputDecoration(
                            labelText: 'Unit',
                            filled: true,
                            fillColor: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF3F4F6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(kRadiusField),
                            ),
                          ),
                          items: ['minutes', 'hours', 'days', 'weeks', 'months', 'years']
                              .map((unit) => DropdownMenuItem(value: unit, child: Text(unit)))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setDialog(() => unitValue = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(kRadiusField),
                      border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.alarm, size: 20, color: primaryColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Will delete by:\n${_computeDeleteDateLive(valueController.text, unitValue)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: isDark ? const Color(0xFFC7D2FE) : const Color(0xFF3730A3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.pop(c),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                child: const Text('Delete Now'),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: c,
                    builder: (dialogCtx) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSheet)),
                      title: const Text('Delete Now?', style: TextStyle(fontWeight: FontWeight.bold)),
                      content: Text(
                        isBatch
                            ? 'These ${paths.length} screenshots will be moved to trash, then permanently deleted after 7 days. Continue?'
                            : 'This screenshot moves to trash, then is permanently deleted after 7 days. Continue?',
                      ),
                      actions: [
                        TextButton(
                          style: TextButton.styleFrom(foregroundColor: const Color(0xFF6B7280)),
                          child: const Text('Cancel'),
                          onPressed: () => Navigator.pop(dialogCtx, false),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
                          child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          onPressed: () => Navigator.pop(dialogCtx, true),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  if (c.mounted) Navigator.pop(c);
                  final result = await _deletePaths(paths);
                  await _loadDetectedImages();
                  await _loadScheduledDeletions();
                  await _loadTrash();
                  if (result.alreadyTrashed.isNotEmpty && result.moved.isEmpty) {
                    _showSnack('Already in trash — nothing changed');
                  } else if (result.failed.isEmpty) {
                    _showSnack(
                      isBatch ? 'Moved ${paths.length} screenshot(s) to trash' : 'Moved to trash',
                      actionLabel: 'Undo',
                      onAction: () => _undoDelete(paths),
                    );
                  } else {
                    _showSnack('Could not delete ${result.failed.length} screenshot(s)', color: Colors.redAccent);
                  }
                },
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Confirm Schedule'),
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  final targetDate = _computeTargetDate(valueController.text, unitValue);
                  final delaySec = targetDate.difference(DateTime.now()).inSeconds.clamp(1, 365 * 86400).toInt();
                  Navigator.pop(c);

                  if (isBatch) {
                    try {
                      await _platform.invokeMethod('schedule_batch_deletion', {
                        'paths': List<String>.from(paths),
                        'delay_seconds': delaySec,
                      });
                    } catch (e) {
                      _logPlatformError('schedule_batch_deletion', e);
                      _showSnack('Could not schedule deletion', color: Colors.redAccent);
                    }
                    setState(() => _selectedBatchPaths.clear());
                  } else {
                    try {
                      await _platform.invokeMethod('schedule_deletion', {
                        'path': paths.first,
                        'delay_seconds': delaySec,
                      });
                    } catch (e) {
                      _logPlatformError('schedule_deletion', e);
                      _showSnack('Could not schedule deletion', color: Colors.redAccent);
                    }
                  }

                  await _loadScheduledDeletions();
                  await _loadDetectedImages();

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(isBatch ? 'Batch scheduled for deletion' : 'Scheduled deletion set'),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  /// Shares one screenshot via the native share sheet (Intent.ACTION_SEND).
  Future<void> _shareScreenshot(String path) async {
    if (path.isEmpty || !File(path).existsSync()) {
      _showSnack('Screenshot file not found', color: Colors.redAccent);
      return;
    }
    HapticFeedback.lightImpact();
    try {
      await _platform.invokeMethod('share_screenshot', {'path': path});
    } catch (e) {
      _logPlatformError('share_screenshot', e);
      _showSnack('Could not share screenshot', color: Colors.redAccent);
    }
  }

  /// Opens the swipeable fullscreen viewer over the currently visible gallery
  /// (respects the active view filter, search query and sort order).
  void _openFullScreenViewer(String initialPath) {
    var items = List<Map<dynamic, dynamic>>.from(_detectedImages);
    if (_filterScheduledOnly) {
      items = items
          .where((e) => _scheduledDeletions.containsKey(e['path']?.toString() ?? ''))
          .toList();
    } else if (_filterPinnedOnly) {
      items = items
          .where((e) => _pinned.contains(e['path']?.toString() ?? ''))
          .toList();
    }
    if (_searchQuery.isNotEmpty) {
      items = items
          .where((e) => (e['name']?.toString() ?? '').toLowerCase().contains(_searchQuery))
          .toList();
    }
    if (!_newestFirst) items = items.reversed.toList();

    final shots = items
        .map((e) => (path: e['path']?.toString() ?? '', name: e['name']?.toString() ?? 'unknown'))
        .where((s) => s.path.isNotEmpty)
        .toList();
    if (shots.isEmpty) return;

    final startIdx = shots.indexWhere((s) => s.path == initialPath);
    _openShotsViewer(shots, startIdx < 0 ? 0 : startIdx);
  }

  /// Opens the swipeable fullscreen viewer over the trashed items, newest
  /// trash placement first (longest remaining grace period first).
  void _openTrashViewer(String originalPath) {
    final shots = _trash.entries
        .map((entry) => (
              path: entry.value['trash']?.toString() ?? '',
              name: entry.value['name']?.toString() ?? 'unknown',
              expiry: (entry.value['expiry'] as num?)?.toInt() ?? 0,
            ))
        .where((s) => s.path.isNotEmpty)
        .toList()
      ..sort((a, b) => b.expiry.compareTo(a.expiry));
    if (shots.isEmpty) return;

    final startIdx = shots.indexWhere((s) => s.path == originalPath);
    _openShotsViewer(
      shots.map((s) => (path: s.path, name: s.name)).toList(),
      startIdx < 0 ? 0 : startIdx,
    );
  }

  void _openShotsViewer(List<({String path, String name})> shots, int initialIndex) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, _, _) => _ScreenshotViewer(
          shots: shots,
          initialIndex: initialIndex.clamp(0, shots.length - 1),
          onShare: _shareScreenshot,
        ),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0)
                .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
      ),
    );
  }

  void _showImageOptions(String path, String name) {
    final isScheduled = _scheduledDeletions.containsKey(path);
    final isPinned = _pinned.contains(path);
    final targetMs = _scheduledDeletions[path];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusSheet)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: File(path).existsSync()
                            ? Image.file(File(path), width: 44, height: 44, fit: BoxFit.cover, cacheWidth: 128)
                            : const Icon(Icons.image, size: 44),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: Theme.of(context).textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            if (isScheduled && targetMs != null)
                              Row(
                                children: [
                                  const Icon(Icons.timer, size: 14, color: Colors.amber),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Scheduled: ${formatTimeRemaining(targetMs)} left',
                                    style: const TextStyle(
                                      color: Colors.amber,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              )
                            else
                              const Text(
                                'Not scheduled for deletion',
                                style: TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.fullscreen),
                  title: const Text('View Full Image'),
                  subtitle: _detectedImages.length > 1
                      ? const Text('Swipe left/right to browse screenshots')
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _openFullScreenViewer(path);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share, color: Color(0xFF4F46E5)),
                  title: const Text('Share'),
                  subtitle: const Text('Send this screenshot to other apps'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _shareScreenshot(path);
                  },
                ),
                ListTile(
                  leading: Icon(
                    isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    color: Colors.teal,
                  ),
                  title: Text(isPinned ? 'Unpin' : 'Keep Forever'),
                  subtitle: Text(isPinned
                      ? 'Remove protection — can be scheduled again'
                      : 'Protect from deletion and auto-scheduling'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pinToggle(path);
                  },
                ),
                if (!isScheduled)
                  ListTile(
                    leading: const Icon(Icons.schedule, color: Color(0xFF4F46E5)),
                    title: const Text('Schedule Deletion'),
                    subtitle: const Text('Set countdown timer to auto-delete'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _openScheduleDialog(paths: [path]);
                    },
                  )
                else ...[
                  ListTile(
                    leading: const Icon(Icons.edit_calendar, color: Color(0xFF4F46E5)),
                    title: const Text('Reschedule Deletion'),
                    subtitle: const Text('Change retention duration'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _openScheduleDialog(paths: [path]);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.cancel_outlined, color: Colors.orange),
                    title: const Text('Cancel Scheduled Deletion'),
                    subtitle: const Text('Keep this screenshot permanently'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      try {
                        await _platform.invokeMethod('cancel_schedule', {'path': path});
                      } catch (e) {
                        _logPlatformError('cancel_schedule', e);
                        _showSnack('Could not cancel schedule', color: Colors.redAccent);
                      }
                      await _loadScheduledDeletions();
                      if (mounted) {
                        setState(() {
                          if (_scheduledDeletions.isEmpty) _filterScheduledOnly = false;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Scheduled deletion cancelled')),
                        );
                      }
                    },
                  ),
                ],
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.checklist),
                  title: Text(_selectedBatchPaths.contains(path)
                      ? 'Deselect from Batch'
                      : 'Select for Batch Action'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _toggleBatchSelection(path);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                  title: const Text('Delete Now', style: TextStyle(color: Colors.redAccent)),
                  onTap: () async {
                    // Confirm before immediate deletion to prevent accidental loss
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogCtx) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSheet)),
                        title: const Text('Delete Now?', style: TextStyle(fontWeight: FontWeight.bold)),
                        content: const Text('This screenshot moves to trash, then is permanently deleted after 7 days. Continue?'),
                        actions: [
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF6B7280),
                            ),
                            child: const Text('Cancel'),
                            onPressed: () => Navigator.pop(dialogCtx, false),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEF4444),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            onPressed: () => Navigator.pop(dialogCtx, true),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    if (ctx.mounted) Navigator.pop(ctx);
                    final result = await _deletePaths([path]);
                    await _loadDetectedImages();
                    await _loadScheduledDeletions();
                    await _loadTrash();
                    if (result.alreadyTrashed.isNotEmpty) {
                      _showSnack('Already in trash — nothing changed');
                    } else if (result.failed.isEmpty) {
                      _showSnack(
                        'Moved to trash',
                        actionLabel: 'Undo',
                        onAction: () => _undoDelete([path]),
                      );
                    } else {
                      _showSnack('Could not delete screenshot', color: Colors.redAccent);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTrashSheet(String originalPath, String name, String trashPath, int expiryMs) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusSheet)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: trashPath.isNotEmpty && File(trashPath).existsSync()
                            ? Image.file(File(trashPath), width: 44, height: 44, fit: BoxFit.cover, cacheWidth: 128)
                            : const Icon(Icons.image, size: 44),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: Theme.of(context).textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.delete_sweep, size: 14, color: Colors.redAccent),
                                const SizedBox(width: 4),
                                Text(
                                  'Hard delete in ${formatTimeRemaining(expiryMs)}',
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.fullscreen),
                  title: const Text('View Full Image'),
                  subtitle: _trash.length > 1 ? const Text('Swipe to browse trashed shots') : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _openTrashViewer(originalPath);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.restore, color: Color(0xFF4F46E5)),
                  title: const Text('Restore to Gallery'),
                  subtitle: const Text('Back to your screenshot folder'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _restoreFromTrash(originalPath);
                  },
                ),
                if (trashPath.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.share, color: Color(0xFF4F46E5)),
                    title: const Text('Share'),
                    subtitle: const Text('Send this screenshot to other apps'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _shareScreenshot(trashPath);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                  title: const Text('Delete Permanently', style: TextStyle(color: Colors.redAccent)),
                  subtitle: const Text('Wipe it right now instead of waiting'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _permanentDelete(originalPath, name);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatChip({
    required int count,
    required String label,
    required IconData icon,
    required Color color,
    required bool active,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kRadiusTile),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? color.withValues(alpha: isDark ? 0.28 : 0.14)
                : (isDark ? const Color(0xFF13131B) : const Color(0xFFFFFFFF)),
            borderRadius: BorderRadius.circular(kRadiusTile),
            border: Border.all(
              color: active ? color.withValues(alpha: 0.65) : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05)),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0 : 0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: active ? color : (isDark ? Colors.white54 : const Color(0xFF9CA3AF))),
              const SizedBox(height: 4),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: active ? color : (isDark ? const Color(0xFFEAEAEA) : const Color(0xFF1A1A2E)),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: active ? color.withValues(alpha: 0.85) : (isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    // Back: unwinds state layers (batch selection → trash view → filter views →
    // search) before leaving the app.
    return PopScope(
      canPop: _selectedBatchPaths.isEmpty &&
          !_showTrash &&
          !_filterScheduledOnly &&
          !_filterPinnedOnly &&
          _searchQuery.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        HapticFeedback.selectionClick();
        setState(() {
          if (_selectedBatchPaths.isNotEmpty) {
            _selectedBatchPaths.clear();
          } else if (_showTrash) {
            _showTrash = false;
          } else if (_filterScheduledOnly || _filterPinnedOnly) {
            _filterScheduledOnly = false;
            _filterPinnedOnly = false;
          } else {
            _searchController.clear();
            _searchQuery = '';
          }
        });
      },
      child: Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF4F46E5), Color(0xFF818CF8)],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(Icons.screenshot_monitor_outlined, color: Colors.white, size: 19),
            ),
            const SizedBox(width: 10),
            const Text('ShotKeeper'),
          ],
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Screenshots',
            onPressed: () {
              _loadDetectedImages();
              _loadScheduledDeletions();
              _loadTrash();
              _loadPinned();
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.surface,
              isDark ? const Color(0xFF0A0A0F) : const Color(0xFFF0F0F5),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                // Top status and auto-detect toggle card
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusCard)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: (_isEnabled ? Colors.green : Colors.grey).withValues(alpha: isDark ? 0.25 : 0.12),
                                borderRadius: BorderRadius.circular(kRadiusTile),
                              ),
                              child: Icon(
                                _isEnabled ? Icons.radar : Icons.radar_outlined,
                                color: _isEnabled ? Colors.green : Colors.grey,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Auto-detect screenshots',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: _isEnabled ? Colors.green : Colors.grey,
                                          boxShadow: _isEnabled
                                              ? [BoxShadow(color: Colors.green.withValues(alpha: 0.5), blurRadius: 5)]
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _isEnabled ? 'Monitoring active • Alerts enabled' : 'Monitoring disabled',
                                        style: TextStyle(
                                          color: _isEnabled ? Colors.green : Colors.grey,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Switch(value: _isEnabled, onChanged: _toggleEnabled),
                          ],
                        ),
                        if (!_batteryExempt) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF3A2E00) : const Color(0xFFFFF7E0),
                              borderRadius: BorderRadius.circular(kRadiusField),
                              border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.battery_alert, size: 18, color: Colors.amber),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Restricted by battery optimization — screenshot detection may stop',
                                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _requestBatteryExemption,
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  child: const Text('Allow'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Stats strip — exactly one chip is active at a time (view or filter)
                Row(
                  children: [
                    _buildStatChip(
                      count: _detectedImages.length,
                      label: 'Gallery',
                      icon: Icons.photo_library_outlined,
                      color: const Color(0xFF4F46E5),
                      active: !_showTrash && !_filterScheduledOnly && !_filterPinnedOnly,
                      onTap: () {
                        setState(() {
                          _showTrash = false;
                          _filterScheduledOnly = false;
                          _filterPinnedOnly = false;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildStatChip(
                      count: _scheduledDeletions.length,
                      label: 'Scheduled',
                      icon: Icons.timer_outlined,
                      color: Colors.amber.shade700,
                      active: _filterScheduledOnly && !_showTrash,
                      onTap: () {
                        setState(() {
                          _showTrash = false;
                          _filterPinnedOnly = false;
                          _filterScheduledOnly = !_filterScheduledOnly;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildStatChip(
                      count: _pinned.length,
                      label: 'Pinned',
                      icon: Icons.push_pin_outlined,
                      color: Colors.teal,
                      active: _filterPinnedOnly && !_showTrash,
                      onTap: () {
                        setState(() {
                          _showTrash = false;
                          _filterScheduledOnly = false;
                          _filterPinnedOnly = !_filterPinnedOnly;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildStatChip(
                      count: _trash.length,
                      label: 'Trash',
                      icon: Icons.delete_outline,
                      color: Colors.redAccent,
                      active: _showTrash,
                      onTap: () {
                        setState(() => _showTrash = true);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Auto-pilot rules card
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusCard)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: (_autoEnabled ? const Color(0xFF10B981) : Colors.grey).withValues(alpha: isDark ? 0.25 : 0.12),
                                borderRadius: BorderRadius.circular(kRadiusTile),
                              ),
                              child: Icon(
                                Icons.bolt,
                                color: _autoEnabled ? const Color(0xFF10B981) : Colors.grey,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Auto-pilot',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _autoEnabled
                                        ? 'New screenshots are scheduled automatically'
                                        : 'Manual scheduling only',
                                    style: TextStyle(
                                      color: _autoEnabled ? const Color(0xFF10B981) : Colors.grey,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(value: _autoEnabled, onChanged: _toggleAutoRule),
                          ],
                        ),
                        if (_autoEnabled) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                flex: 1,
                                child: TextField(
                                  controller: _autoValueController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'Value',
                                    filled: true,
                                    fillColor: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF3F4F6),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(kRadiusField)),
                                  ),
                                  onChanged: (_) => _saveAutoRule(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<String>(
                                  initialValue: _autoUnit,
                                  decoration: InputDecoration(
                                    labelText: 'Unit',
                                    filled: true,
                                    fillColor: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF3F4F6),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(kRadiusField)),
                                  ),
                                  items: ['minutes', 'hours', 'days', 'weeks', 'months', 'years']
                                      .map((unit) => DropdownMenuItem(value: unit, child: Text(unit)))
                                      .toList(),
                                  onChanged: (v) {
                                    if (v != null) {
                                      setState(() => _autoUnit = v);
                                      _saveAutoRule();
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F2E1D) : const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(kRadiusField),
                              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.bolt, size: 20, color: Colors.green),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'New screenshots will delete by:\n${_formatDateTime(_computeTargetDate(_autoValueController.text, _autoUnit))}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF065F46),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Trash Batch Action Bar (Restore / Delete permanently)
                if (_showTrash && _selectedBatchPaths.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2B1117) : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(kRadiusTile),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${_selectedBatchPaths.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Selected',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              icon: const Icon(Icons.select_all, size: 18),
                              label: const Text('All'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                              ),
                              onPressed: _selectAllBatch,
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              tooltip: 'Cancel selection',
                              onPressed: _clearBatch,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.restore, size: 18),
                              label: const Text('Restore'),
                              style: TextButton.styleFrom(
                                foregroundColor: primaryColor,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              onPressed: () {
                                final selected = List<String>.from(_selectedBatchPaths);
                                _clearBatch();
                                _undoDelete(selected);
                              },
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.delete_forever, size: 18),
                              label: const Text('Delete Permanently'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              onPressed: () async {
                                final selected = List<String>.from(_selectedBatchPaths);
                                final confirmed = await _confirmDeleteNow(
                                  content:
                                      '${selected.length} trashed screenshot(s) will be permanently deleted immediately. This cannot be undone.',
                                );
                                if (!confirmed) return;
                                _clearBatch();
                                HapticFeedback.mediumImpact();
                                var wiped = 0;
                                for (final p in selected) {
                                  try {
                                    if (await _platform.invokeMethod('permanent_delete', {'path': p}) == true) {
                                      wiped++;
                                    }
                                  } catch (e) {
                                    _logPlatformError('permanent_delete', e);
                                  }
                                }
                                await _loadTrash();
                                _showSnack(wiped == selected.length
                                    ? 'Permanently deleted ${selected.length} screenshot(s)'
                                    : 'Permanently deleted $wiped of ${selected.length}');
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                // Batch Selection Action Bar
                if (!_showTrash && _selectedBatchPaths.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(kRadiusTile),
                      border: Border.all(color: primaryColor.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: primaryColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${_selectedBatchPaths.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Selected',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              icon: const Icon(Icons.select_all, size: 18),
                              label: const Text('All'),
                              style: TextButton.styleFrom(
                                foregroundColor: primaryColor,
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                              ),
                              onPressed: _selectAllBatch,
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              tooltip: 'Cancel selection',
                              onPressed: _clearBatch,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          children: [
                            Builder(
                              builder: (context) {
                                final allPinned = _selectedBatchPaths.every(_pinned.contains);
                                return TextButton.icon(
                                  icon: Icon(allPinned ? Icons.push_pin_outlined : Icons.push_pin, size: 18),
                                  label: Text(allPinned ? 'Unpin' : 'Pin'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.teal,
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                  ),
                                  onPressed: () async {
                                    final targets = List<String>.from(_selectedBatchPaths);
                                    for (final p in targets) {
                                      try {
                                        await _platform.invokeMethod('set_pinned', {'path': p, 'pinned': !allPinned});
                                      } catch (e) {
                                        _logPlatformError('set_pinned', e);
                                      }
                                    }
                                    _clearBatch();
                                    await _loadPinned();
                                    await _loadScheduledDeletions();
                                    await _loadDetectedImages();
                                    _showSnack(allPinned
                                        ? 'Removed pin from ${targets.length} screenshot(s)'
                                        : 'Kept ${targets.length} screenshot(s) forever');
                                  },
                                );
                              },
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.schedule, size: 18),
                              label: const Text('Schedule'),
                              style: TextButton.styleFrom(
                                foregroundColor: primaryColor,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              onPressed: () => _openScheduleDialog(paths: _selectedBatchPaths.toList()),
                            ),
                            if (_selectedBatchPaths.any((p) => _scheduledDeletions.containsKey(p)))
                              TextButton.icon(
                                icon: const Icon(Icons.timer_off, size: 18),
                                label: const Text('Unschedule'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.amber.shade800,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                onPressed: () async {
                                  final targets = _selectedBatchPaths
                                      .where((p) => _scheduledDeletions.containsKey(p))
                                      .toList();
                                  for (final p in targets) {
                                    try {
                                      await _platform.invokeMethod('cancel_schedule', {'path': p});
                                    } catch (e) {
                                      _logPlatformError('cancel_schedule', e);
                                    }
                                  }
                                  _clearBatch();
                                  await _loadScheduledDeletions();
                                  _showSnack('Cancelled ${targets.length} scheduled deletion(s)');
                                },
                              ),
                            TextButton.icon(
                              icon: const Icon(Icons.delete_forever, size: 18),
                              label: const Text('Delete'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              onPressed: () async {
                                final selected = List<String>.from(_selectedBatchPaths);
                                final confirmed = await _confirmDeleteNow(
                                  content:
                                      '${selected.length} screenshot(s) will be moved to trash, then permanently deleted after 7 days. Continue?',
                                );
                                if (!confirmed) return;
                                _clearBatch();
                                final result = await _deletePaths(selected);
                                await _loadDetectedImages();
                                await _loadScheduledDeletions();
                                await _loadTrash();
                                if (result.alreadyTrashed.isNotEmpty && result.moved.isEmpty) {
                                  _showSnack('Already in trash — nothing changed');
                                } else if (result.failed.isEmpty) {
                                  _showSnack(
                                    'Moved ${selected.length} screenshot(s) to trash',
                                    actionLabel: 'Undo',
                                    onAction: () => _undoDelete(selected),
                                  );
                                } else {
                                  _showSnack('Could not delete ${result.failed.length} screenshot(s)',
                                      color: Colors.redAccent);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                // Search Bar
                TextField(
                  controller: _searchController,
                  autofocus: false,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    hintText: 'Search screenshots by name...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF3F4F6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(kRadiusField), borderSide: BorderSide.none),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                ),
                const SizedBox(height: 10),

                // Gallery / Trash Header & Legend
                Row(
                  children: [
                    Text(
                      _showTrash ? 'Trash' : 'Gallery',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _showTrash
                            ? 'auto-clean after 7 days'
                            : _newestFirst ? 'newest on top' : 'oldest on top',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_showTrash && _trash.isNotEmpty)
                      TextButton.icon(
                        icon: const Icon(Icons.delete_sweep, size: 18),
                        label: const Text('Empty'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: _emptyTrash,
                      ),
                    if (!_showTrash)
                      IconButton(
                        icon: const Icon(Icons.swap_vert, size: 20),
                        tooltip: _newestFirst ? 'Sorting: newest first — tap to flip' : 'Sorting: oldest first — tap to flip',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _newestFirst = !_newestFirst),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                    ], // top section columns
                  ),
                ),
                ..._buildGallerySlivers(context),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  /// Slivers for the screenshot grid / loading skeleton / empty states.
  List<Widget> _buildGallerySlivers(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
                      final media = MediaQuery.of(context);
                      final crossAxisCount = (media.size.width / 110).floor().clamp(2, 6).toInt();
                      final cacheWidth = ((media.size.width / crossAxisCount) * media.devicePixelRatio).round();
                      List<dynamic> sourceImages;
                      if (_showTrash) {
                        sourceImages = _trash.entries
                            .map((entry) => {
                                  'path': entry.value['trash']?.toString() ?? '',
                                  'name': entry.value['name']?.toString() ?? 'unknown',
                                  'origPath': entry.key,
                                  'expiry': entry.value['expiry'],
                                })
                            .toList();
                      } else {
                        sourceImages = _detectedImages;
                        if (_filterScheduledOnly) {
                          sourceImages = sourceImages
                              .where((item) => _scheduledDeletions.containsKey(item['path']?.toString() ?? ''))
                              .toList();
                        } else if (_filterPinnedOnly) {
                          sourceImages = sourceImages
                              .where((item) => _pinned.contains(item['path']?.toString() ?? ''))
                              .toList();
                        }
                        if (!_newestFirst) {
                          sourceImages = sourceImages.reversed.toList();
                        }
                      }
                      final filtered = _searchQuery.isEmpty
                          ? sourceImages
                          : sourceImages.where((item) {
                              final name = item['name']?.toString() ?? '';
                              return name.toLowerCase().contains(_searchQuery);
                            }).toList();
                    // Loading skeleton (avoids flashing "No screenshots yet")
                    if (!_loaded) {
                      return [
                        SliverGrid(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 0.72,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (_, _) => Container(
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF13131B) : const Color(0xFFEDEDF3),
                                borderRadius: BorderRadius.circular(kRadiusTile),
                              ),
                            ),
                            childCount: crossAxisCount * 3,
                          ),
                        ),
                      ];
                    }
                    if (filtered.isEmpty) {
                      Widget centerChild;
                      if (_searchQuery.isNotEmpty) {
                        centerChild = Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 84,
                              height: 84,
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF13131B) : const Color(0xFFEFEFF5),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.search_off, size: 38, color: Colors.grey.withValues(alpha: 0.6)),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'No results for "$_searchQuery"',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Try a shorter or different name',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        );
                      } else if (!_showTrash && _filterScheduledOnly) {
                        centerChild = SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer_outlined, size: 56, color: Colors.amber),
                              const SizedBox(height: 14),
                              Text(
                                'No scheduled deletions',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Schedule a screenshot to see its countdown here',
                                style: Theme.of(context).textTheme.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        );
                      } else if (!_showTrash && _filterPinnedOnly) {
                        centerChild = SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.push_pin_outlined, size: 56, color: Colors.teal),
                              const SizedBox(height: 14),
                              Text(
                                'Nothing pinned yet',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Use "Keep Forever" to protect screenshots from deletion',
                                style: Theme.of(context).textTheme.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        );
                      } else {
                        centerChild = SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: _showTrash
                                ? [
                                    Container(
                                      width: 84,
                                      height: 84,
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF13131B) : const Color(0xFFFEF2F2),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.delete_sweep_outlined, size: 38, color: Colors.redAccent),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      'Trash is empty',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Deleted screenshots rest here for 7 days',
                                      style: Theme.of(context).textTheme.bodyMedium,
                                      textAlign: TextAlign.center,
                                    ),
                                  ]
                                : [
                                    Container(
                                      width: 84,
                                      height: 84,
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF13131B) : const Color(0xFFEEF2FF),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.screenshot_monitor_outlined,
                                        size: 38,
                                        color: Color(0xFF4F46E5),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      'No screenshots yet',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _isEnabled
                                          ? 'Take one — ShotKeeper will catch it'
                                          : 'Turn on auto-detect to start capturing',
                                      style: Theme.of(context).textTheme.bodyMedium,
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                          ),
                        );
                      }
                      return [
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: centerChild),
                        ),
                      ];
                    }
                    return [
                      SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 0.72,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final item = filtered[index];
                        final name = item['name']?.toString() ?? 'unknown';
                            final path = item['path']?.toString() ?? '';
                            final origPath = item['origPath']?.toString() ?? path;
                            final expiryMs = int.tryParse(item['expiry']?.toString() ?? '');
                            final isSelected = _selectedBatchPaths.contains(path);
                            final isScheduled = !_showTrash && _scheduledDeletions.containsKey(origPath);
                            final isPinned = !_showTrash && _pinned.contains(origPath);
                            final targetMs = _scheduledDeletions[origPath];

                            return _ScreenshotTile(
                              path: path,
                              name: name,
                              cacheWidth: cacheWidth,
                              dateSeconds: int.tryParse(item['date']?.toString() ?? ''),
                              isDark: isDark,
                              primaryColor: primaryColor,
                              isSelected: isSelected,
                              isScheduled: isScheduled,
                              targetMs: targetMs,
                              isPinned: isPinned,
                              isTrash: _showTrash,
                              expiryMs: expiryMs,
                              onTap: () {
                                if (_selectedBatchPaths.isNotEmpty) {
                                  _toggleBatchSelection(path);
                                } else if (_showTrash) {
                                  _showTrashSheet(origPath, name, path, expiryMs ?? 0);
                                } else {
                                  _showImageOptions(path, name);
                                }
                              },
                              onLongPress: () => _toggleBatchSelection(path),
                            );
                          },
                          childCount: filtered.length,
                        ),
                      ),
                    ];
                  }
}

// ---- Grid tile widgets ------------------------------------------------------

class _ScreenshotTile extends StatefulWidget {
  const _ScreenshotTile({
    required this.path,
    required this.name,
    required this.cacheWidth,
    required this.dateSeconds,
    required this.isDark,
    required this.primaryColor,
    required this.isScheduled,
    required this.isTrash,
    required this.onTap,
    required this.onLongPress,
    this.isSelected = false,
    this.targetMs,
    this.isPinned = false,
    this.expiryMs,
  });

  final String path;
  final String name;
  final int cacheWidth;
  final int? dateSeconds;
  final bool isDark;
  final Color primaryColor;
  final bool isSelected;
  final bool isScheduled;
  final int? targetMs;
  final bool isPinned;
  final bool isTrash;
  final int? expiryMs;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  State<_ScreenshotTile> createState() => _ScreenshotTileState();
}

class _ScreenshotTileState extends State<_ScreenshotTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheduledPill = widget.isScheduled && widget.targetMs != null;
    final trashPill = widget.isTrash && widget.expiryMs != null;
    final placeholderColor = widget.isDark ? const Color(0xFF1A1A2E) : const Color(0xFFE5E7EB);

    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _pressed ? 0.93 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kRadiusTile),
              border: Border.all(
                color: widget.isSelected
                    ? widget.primaryColor
                    : (widget.isScheduled ? Colors.amber.shade700 : Colors.transparent),
                width: widget.isSelected || widget.isScheduled ? 2.5 : 0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kRadiusTile - 2),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Image preview (downsampled to tile size, gentle fade-in)
                  widget.path.isNotEmpty
                      ? Hero(
                          tag: 'shot-hero-${widget.path}',
                          child: Image.file(
                            File(widget.path),
                            fit: BoxFit.cover,
                            cacheWidth: widget.cacheWidth,
                            frameBuilder: (_, child, frame, wasSync) {
                              if (wasSync || frame == null) return child;
                              return AnimatedOpacity(
                                opacity: 1,
                                duration: const Duration(milliseconds: 200),
                                child: child,
                              );
                            },
                            errorBuilder: (_, _, _) => Container(
                              color: placeholderColor,
                              child: const Icon(Icons.broken_image),
                            ),
                          ),
                        )
                      : Container(
                          color: placeholderColor,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Text(
                                widget.name,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(context).colorScheme.secondary,
                                ),
                              ),
                            ),
                          ),
                        ),

                  // Scheduled countdown pill (floating)
                  if (scheduledPill)
                    Positioned(
                      top: 6,
                      left: widget.isSelected ? 34 : 6,
                      child: _BadgePill(
                        icon: Icons.timer_outlined,
                        text: formatTimeRemaining(widget.targetMs!),
                        color: Colors.amber.shade900,
                      ),
                    ),

                  // Trash pill with countdown ring
                  if (trashPill)
                    Positioned(
                      top: 6,
                      left: widget.isSelected ? 34 : 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.shade700.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _CountdownRing(
                              progress: (1 -
                                      ((widget.expiryMs! - DateTime.now().millisecondsSinceEpoch) /
                                          kTrashGraceMs))
                                  .clamp(0.0, 1.0),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${formatTimeRemaining(widget.expiryMs!)} left',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Pin badge (Keep Forever)
                  if (widget.isPinned)
                    Positioned(
                      top: scheduledPill || trashPill ? 34 : 6,
                      left: 6,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.teal,
                          shape: BoxShape.circle,
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
                        ),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(Icons.push_pin, color: Colors.white, size: 11),
                      ),
                    ),

                  // Selection marker (animated in)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: AnimatedScale(
                      scale: widget.isSelected ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOutBack,
                      child: Container(
                        decoration: BoxDecoration(
                          color: widget.primaryColor,
                          shape: BoxShape.circle,
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                        ),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(Icons.check, color: Colors.white, size: 14),
                      ),
                    ),
                  ),

                  // Bottom footer: relative date + filename
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                      color: Colors.black.withValues(alpha: 0.65),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.dateSeconds != null && !widget.isTrash)
                            Text(
                              formatRelativeDate(widget.dateSeconds),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 8,
                                fontWeight: FontWeight.w400,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          Text(
                            widget.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BadgePill extends StatelessWidget {
  const _BadgePill({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 11),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountdownRing extends StatelessWidget {
  const _CountdownRing({required this.progress});

  /// Fraction of the 7-day grace period that has elapsed (0 = fresh, 1 = expiring).
  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: 12,
      child: CustomPaint(painter: _RingPainter(progress: progress)),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 1.6;
    final radius = (size.shortestSide - stroke) / 2;
    final center = Offset(size.width / 2, size.height / 2);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Colors.white24,
    );

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -90 * 3.141592653589793 / 180,
        2 * 3.141592653589793 * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.progress != progress;
}

// ---- Fullscreen screenshot viewer (swipeable) -------------------------------

class _ScreenshotViewer extends StatefulWidget {
  const _ScreenshotViewer({
    required this.shots,
    required this.onShare,
    this.initialIndex = 0,
  });

  /// Visible screenshots in their current view order.
  final List<({String path, String name})> shots;
  final void Function(String path) onShare;
  final int initialIndex;

  @override
  State<_ScreenshotViewer> createState() => _ScreenshotViewerState();
}

class _ScreenshotViewerState extends State<_ScreenshotViewer> {
  late final PageController _pageController = PageController(initialPage: widget.initialIndex);
  final TransformationController _transform = TransformationController();
  late int _index = widget.initialIndex.clamp(0, widget.shots.length - 1);
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransformChanged);
    _transform.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.02;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  @override
  Widget build(BuildContext context) {
    final shot = widget.shots[_index];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Material(
        color: Colors.black,
        child: Stack(
          children: [
            // Swipeable, zoomable pages
            PageView.builder(
              controller: _pageController,
              itemCount: widget.shots.length,
              onPageChanged: (i) {
                _transform.value = Matrix4.identity();
                setState(() => _index = i);
              },
              itemBuilder: (context, i) {
                final page = widget.shots[i];
                final file = File(page.path);
                return InteractiveViewer(
                  transformationController: _transform,
                  panEnabled: _zoomed,
                  maxScale: 4.0,
                  child: Center(
                    child: Hero(
                      tag: 'shot-hero-${page.path}',
                      child: file.existsSync()
                          ? Image.file(
                              file,
                              fit: BoxFit.contain,
                              cacheWidth: 2048,
                              errorBuilder: (_, _, _) => const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.broken_image, color: Colors.white30, size: 56),
                                  SizedBox(height: 12),
                                  Text('Image file not found', style: TextStyle(color: Colors.white38)),
                                ],
                              ),
                            )
                          : const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.broken_image, color: Colors.white30, size: 56),
                                SizedBox(height: 12),
                                Text('Image file not found', style: TextStyle(color: Colors.white38)),
                              ],
                            ),
                    ),
                  ),
                );
              },
            ),

            // Top bar (close / filename / share)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x8A000000), Colors.transparent],
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        tooltip: 'Close viewer',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          child: Text(
                            shot.name,
                            key: ValueKey(shot.path),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.share, color: Colors.white),
                        tooltip: 'Share screenshot',
                        onPressed: () => widget.onShare(shot.path),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Page counter
            if (widget.shots.length > 1)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  top: false,
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${_index + 1} / ${widget.shots.length}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}