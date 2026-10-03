import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'dart:io';

void main() => runApp(const ShotKeeperApp());

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
          shadowColor: Colors.black.withOpacity(0.08),
          color: const Color(0xFFFFFFFF),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
          shadowColor: Colors.black.withOpacity(0.8),
          color: const Color(0xFF0A0A0F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF000000),
          foregroundColor: Color(0xFFEAEAEA),
          elevation: 0,
          titleTextStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 20, letterSpacing: -0.3, color: Color(0xFFEAEAEA)),
        ),
        dividerTheme: DividerThemeData(color: Colors.indigo.withOpacity(0.08)),
        switchTheme: SwitchThemeData(
          thumbColor: MaterialStateProperty.resolveWith((states) => states.contains(MaterialState.selected) ? const Color(0xFF4F46E5) : const Color(0xFFE0E7FF)),
          trackColor: MaterialStateProperty.resolveWith((states) => states.contains(MaterialState.selected) ? const Color(0xFFE0E7FF) : const Color(0xFFF8F7FB)),
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

class _HomeScreenState extends State<HomeScreen> {
  bool _isEnabled = false;
  RetentionPeriod _selectedPeriod = RetentionPeriod.threeDays;
  int _screenshotCount = 0;
  List<dynamic> _detectedImages = [];
  final List<String> _selectedBatchPaths = [];
  Map<String, int> _scheduledDeletions = {};
  Timer? _liveTicker;
  String _searchQuery = '';
  bool _filterScheduledOnly = false;
  final TextEditingController _searchController = TextEditingController();

  static const _keyEnabled = 'shot_keeper_enabled';
  static const _keyPeriod = 'shot_keeper_period';
  static const _keyCount = 'shot_keeper_screenshot_count';
  static const _platform = MethodChannel('shotkeeper/permission');
  static const _countChannel = MethodChannel('shotkeeper/count');

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadCount();
    _loadDetectedImages();
    _loadScheduledDeletions();
    _startLiveTicker();
    _initNotificationIntentListener();
  }

  @override
  void dispose() {
    _liveTicker?.cancel();
    super.dispose();
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
    } catch (_) {}
  }

  void _handleNotificationScreenshot(String path) {
    _loadDetectedImages();
    _loadScheduledDeletions();
    if (path.isNotEmpty && File(path).existsSync()) {
      _openScheduleDialog(paths: [path]);
    }
  }

  void _startLiveTicker() {
    _liveTicker?.cancel();
    _liveTicker = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      bool hasDue = false;
      for (final targetMs in _scheduledDeletions.values) {
        if (now >= targetMs) {
          hasDue = true;
          break;
        }
      }

      if (hasDue) {
        try {
          await _platform.invokeMethod('check_due_deletions');
        } catch (_) {}
        await _loadScheduledDeletions();
        await _loadDetectedImages();
      } else {
        setState(() {}); // Dynamic countdown badge refresh
      }
    });
  }

  Future<void> _loadCount() async {
    try {
      await _countChannel.invokeMethod('get_count');
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _screenshotCount = prefs.getInt(_keyCount) ?? 0);
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
        try { await _platform.invokeMethod('start_detector'); } catch (_) {}
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
      }
    } catch (_) {}
  }

  Future<void> _loadDetectedImages() async {
    try {
      final result = await _platform.invokeMethod('get_detected_screenshots');
      if (result is List && mounted) {
        final list = List<Map<dynamic, dynamic>>.from(result);
        // Guarantee newest screenshots on top via file lastModified timestamp
        list.sort((a, b) {
          try {
            final fileA = File(a['path']?.toString() ?? '');
            final fileB = File(b['path']?.toString() ?? '');
            if (fileA.existsSync() && fileB.existsSync()) {
              return fileB.lastModifiedSync().compareTo(fileA.lastModifiedSync());
            }
          } catch (_) {}
          return 0;
        });

        setState(() {
          _detectedImages = list;
          final existingPaths = list.map((e) => e['path']?.toString()).toSet();
          _selectedBatchPaths.removeWhere((p) => !existingPaths.contains(p));
        });
      }
    } catch (_) {}
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
        try { await _platform.invokeMethod('stop_detector'); } catch (_) {}
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
    await _saveSettings();
    if (Platform.isAndroid && value) {
      try {
        await _platform.invokeMethod('start_detector');
      } catch (_) {}
    }
  }

  void _toggleBatchSelection(String path) {
    setState(() {
      if (_selectedBatchPaths.contains(path)) {
        _selectedBatchPaths.remove(path);
      } else {
        _selectedBatchPaths.add(path);
      }
    });
  }

  void _clearBatch() => setState(() => _selectedBatchPaths.clear());

  String _formatDateTime(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final monthName = months[dt.month - 1];
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$monthName ${dt.day}, ${dt.year} at $hour:$minute $ampm';
  }

  int _computeDelaySeconds(String valueStr, String unit) {
    final value = int.tryParse(valueStr) ?? 4;
    switch (unit) {
      case 'minutes': return value * 60;
      case 'hours': return value * 3600;
      case 'days': return value * 86400;
      case 'weeks': return value * 7 * 86400;
      case 'months': return value * 30 * 86400;
      case 'years': return value * 365 * 86400;
      default: return value * 3600;
    }
  }

  String _computeDeleteDateLive(String valueStr, String unit) {
    final value = int.tryParse(valueStr) ?? 4;
    DateTime target;
    switch (unit) {
      case 'minutes': target = DateTime.now().add(Duration(minutes: value)); break;
      case 'hours': target = DateTime.now().add(Duration(hours: value)); break;
      case 'days': target = DateTime.now().add(Duration(days: value)); break;
      case 'weeks': target = DateTime.now().add(Duration(days: value * 7)); break;
      case 'months': target = DateTime.now().add(Duration(days: value * 30)); break;
      case 'years': target = DateTime.now().add(Duration(days: value * 365)); break;
      default: target = DateTime.now().add(Duration(hours: value));
    }
    return _formatDateTime(target);
  }

  String _formatTimeRemaining(int targetEpochMs) {
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 140,
                        width: double.infinity,
                        color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFE5E7EB),
                        child: Image.file(
                          File(paths.first),
                          fit: BoxFit.contain,
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
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onChanged: (v) => setDialog(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          value: unitValue,
                          decoration: InputDecoration(
                            labelText: 'Unit',
                            filled: true,
                            fillColor: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF3F4F6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
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
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: primaryColor.withOpacity(0.3)),
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
              if (!isBatch)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                  child: const Text('Delete Now'),
                  onPressed: () async {
                    // Confirm before immediate deletion to prevent accidental loss
                    final confirmed = await showDialog<bool>(
                      context: c,
                      builder: (dialogCtx) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        title: const Text('Delete Now?', style: TextStyle(fontWeight: FontWeight.bold)),
                        content: const Text('This screenshot will be permanently deleted immediately. Continue?'),
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
                    Navigator.pop(c);
                    try {
                      await _platform.invokeMethod('delete_now', {'path': paths.first});
                    } catch (_) {}
                    await _loadDetectedImages();
                    await _loadScheduledDeletions();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Screenshot deleted')),
                      );
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
                  final delaySec = _computeDelaySeconds(valueController.text, unitValue);
                  final targetDate = DateTime.now().add(Duration(seconds: delaySec));
                  Navigator.pop(c);

                  if (isBatch) {
                    try {
                      await _platform.invokeMethod('schedule_batch_deletion', {
                        'paths': List<String>.from(paths),
                        'delay_seconds': delaySec,
                      });
                    } catch (_) {}
                    setState(() => _selectedBatchPaths.clear());
                  } else {
                    try {
                      await _platform.invokeMethod('schedule_deletion', {
                        'path': paths.first,
                        'delay_seconds': delaySec,
                      });
                    } catch (_) {}
                  }

                  await _loadScheduledDeletions();
                  await _loadDetectedImages();

                  if (mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ScheduleDetailsScreen(
                          imagePaths: paths,
                          deleteDate: _formatDateTime(targetDate),
                          onDeleted: () {
                            _loadDetectedImages();
                            _loadScheduledDeletions();
                          },
                        ),
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

  void _showImageOptions(String path, String name) {
    final isScheduled = _scheduledDeletions.containsKey(path);
    final targetMs = _scheduledDeletions[path];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                    color: Colors.grey.withOpacity(0.4),
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
                            ? Image.file(File(path), width: 44, height: 44, fit: BoxFit.cover)
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
                                    'Scheduled: ${_formatTimeRemaining(targetMs)} left',
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
                  onTap: () {
                    Navigator.pop(ctx);
                    showDialog(
                      context: context,
                      builder: (c) => Dialog(
                        insetPadding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppBar(
                              title: Text(name, style: const TextStyle(fontSize: 16)),
                              leading: IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.pop(c),
                              ),
                              elevation: 0,
                            ),
                            Flexible(
                              child: InteractiveViewer(
                                child: File(path).existsSync()
                                    ? Image.file(File(path), fit: BoxFit.contain)
                                    : const Center(child: Text('Image file not found')),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
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
                      } catch (_) {}
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        title: const Text('Delete Now?', style: TextStyle(fontWeight: FontWeight.bold)),
                        content: const Text('This screenshot will be permanently deleted immediately. Continue?'),
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
                    Navigator.pop(ctx);
                    try {
                      await _platform.invokeMethod('delete_now', {'path': path});
                    } catch (_) {}
                    await _loadDetectedImages();
                    await _loadScheduledDeletions();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Screenshot deleted')),
                      );
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ShotKeeper'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Screenshots',
            onPressed: () {
              _loadDetectedImages();
              _loadScheduledDeletions();
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top status and auto-detect toggle card
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
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
                                  Text(
                                    _isEnabled
                                        ? 'Monitoring active • Alerts enabled'
                                        : 'Monitoring disabled',
                                    style: TextStyle(
                                      color: _isEnabled ? Colors.green : Colors.grey,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(value: _isEnabled, onChanged: _toggleEnabled),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Batch Selection Action Bar
                if (_selectedBatchPaths.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: primaryColor.withOpacity(0.5)),
                    ),
                    child: Row(
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
                          icon: const Icon(Icons.schedule, size: 18),
                          label: const Text('Schedule'),
                          style: TextButton.styleFrom(
                            foregroundColor: primaryColor,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () => _openScheduleDialog(paths: _selectedBatchPaths),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          tooltip: 'Clear selection',
                          onPressed: _clearBatch,
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
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
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

                // Gallery Header & Legend
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Detected Screenshots (${_detectedImages.length})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    if (_scheduledDeletions.isNotEmpty)
                      InkWell(
                        onTap: () => setState(() => _filterScheduledOnly = !_filterScheduledOnly),
                        borderRadius: BorderRadius.circular(20),
                        highlightColor: Colors.amber.withOpacity(0.2),
                        splashColor: Colors.amber.withOpacity(0.35),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _filterScheduledOnly
                                ? Colors.amber.shade700.withOpacity(0.25)
                                : Colors.amber.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _filterScheduledOnly
                                  ? Colors.amber.shade700.withOpacity(0.6)
                                  : Colors.amber.withOpacity(0.4),
                              width: _filterScheduledOnly ? 1.2 : 0.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.amber.withOpacity(_filterScheduledOnly ? 0.25 : 0.05),
                                blurRadius: _filterScheduledOnly ? 6 : 2,
                                offset: Offset(0, _filterScheduledOnly ? 2 : 1),
                              ),
                            ],
                          ),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            opacity: 1.0,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedRotation(
                                  duration: const Duration(milliseconds: 300),
                                  turns: _filterScheduledOnly ? 0.02 : 0,
                                  child: const Icon(Icons.timer, size: 13, color: Colors.amber),
                                ),
                                const SizedBox(width: 4),
                                AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 200),
                                  style: TextStyle(
                                    color: Colors.amber,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.3,
                                  ),
                                  child: Text(
                                    '${_scheduledDeletions.length} scheduled',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                // Gallery Grid (Newest on Top)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final sourceImages = _filterScheduledOnly
                          ? _detectedImages.where((item) => _scheduledDeletions.containsKey(item['path']?.toString() ?? '')).toList()
                          : _detectedImages;
                      final filtered = _searchQuery.isEmpty
                          ? sourceImages
                          : sourceImages.where((item) {
                              final name = item['name']?.toString() ?? '';
                              return name.toLowerCase().contains(_searchQuery);
                            }).toList();
                    if (filtered.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off, size: 56, color: Colors.grey.withOpacity(0.5)),
                            const SizedBox(height: 12),
                            Text(
                              'No results for "$_searchQuery"',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey),
                            ),
                          ],
                        ),
                      );
                    }
                    return GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 0.72,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final name = item['name']?.toString() ?? 'unknown';
                            final path = item['path']?.toString() ?? '';
                            final isSelected = _selectedBatchPaths.contains(path);
                            final isScheduled = _scheduledDeletions.containsKey(path);
                            final targetMs = _scheduledDeletions[path];

                            return InkWell(
                              onTap: () {
                                if (_selectedBatchPaths.isNotEmpty) {
                                  _toggleBatchSelection(path);
                                } else {
                                  _showImageOptions(path, name);
                                }
                              },
                              onLongPress: () => _toggleBatchSelection(path),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected
                                        ? primaryColor
                                        : (isScheduled
                                            ? Colors.amber.shade700
                                            : Colors.transparent),
                                    width: isSelected || isScheduled ? 2.5 : 0,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.08),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      // Image preview
                                      path.isNotEmpty && File(path).existsSync()
                                          ? Image.file(
                                              File(path),
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Container(
                                                color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFE5E7EB),
                                                child: const Icon(Icons.broken_image),
                                              ),
                                            )
                                          : Container(
                                              color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFE5E7EB),
                                              child: Center(
                                                child: Padding(
                                                  padding: const EdgeInsets.all(4),
                                                  child: Text(
                                                    name,
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Theme.of(context).colorScheme.secondary,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),

                                      // Top Status Overlay (Scheduled Badge or Selection)
                                      if (isScheduled && targetMs != null)
                                        Positioned(
                                          top: 0,
                                          left: 0,
                                          right: 0,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  Colors.amber.shade900.withOpacity(0.95),
                                                  Colors.orange.shade800.withOpacity(0.95),
                                                ],
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                const Icon(Icons.timer_outlined, color: Colors.white, size: 12),
                                                const SizedBox(width: 3),
                                                Flexible(
                                                  child: Text(
                                                    _formatTimeRemaining(targetMs),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),

                                      // Batch Selection Checkbox / Marker
                                      if (isSelected)
                                        Positioned(
                                          top: 6,
                                          right: 6,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: primaryColor,
                                              shape: BoxShape.circle,
                                              boxShadow: const [
                                                BoxShadow(color: Colors.black26, blurRadius: 4),
                                              ],
                                            ),
                                            padding: const EdgeInsets.all(4),
                                            child: const Icon(Icons.check, color: Colors.white, size: 14),
                                          ),
                                        ),

                                      // Bottom Filename Label
                                      Positioned(
                                        bottom: 0,
                                        left: 0,
                                        right: 0,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                                          color: Colors.black.withOpacity(0.65),
                                          child: Text(
                                            name,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ScheduleDetailsScreen extends StatelessWidget {
  final List<String> imagePaths;
  final String deleteDate;
  final VoidCallback? onDeleted;

  const ScheduleDetailsScreen({
    super.key,
    required this.imagePaths,
    required this.deleteDate,
    this.onDeleted,
  });

  static const _platform = MethodChannel('shotkeeper/permission');

  Future<void> _deleteNow(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete Now?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          imagePaths.length > 1
              ? 'These ${imagePaths.length} screenshots will be permanently deleted. Continue?'
              : 'This screenshot will be permanently deleted immediately. Continue?',
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(dialogCtx, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(dialogCtx, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    for (final path in imagePaths) {
      try {
        await _platform.invokeMethod('delete_now', {'path': path});
      } catch (_) {}
    }
    onDeleted?.call();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(imagePaths.length > 1
              ? '${imagePaths.length} screenshots deleted'
              : 'Screenshot deleted'),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scheduled Deletion'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (imagePaths.isEmpty) ...[
                          Text(
                            'No screenshots selected',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey),
                          ),
                        ] else if (imagePaths.length == 1) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              height: 320,
                              color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFE5E7EB),
                              child: File(imagePaths.first).existsSync()
                                  ? Image.file(
                                      File(imagePaths.first),
                                      fit: BoxFit.contain,
                                    )
                                  : Center(
                                      child: Text(
                                        'Screenshot Preview',
                                        style: Theme.of(context).textTheme.bodyMedium,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: Text(
                              imagePaths.first.split(RegExp(r'[/\\]')).last,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ] else ...[
                          Text(
                            '${imagePaths.length} Screenshots Selected',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 120,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              itemCount: imagePaths.length,
                              itemBuilder: (ctx, idx) {
                                final p = imagePaths[idx];
                                return Container(
                                  width: 100,
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        File(p).existsSync()
                                            ? Image.file(File(p), fit: BoxFit.cover)
                                            : Container(
                                                color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFE5E7EB),
                                                child: const Icon(Icons.image),
                                              ),
                                        Positioned(
                                          bottom: 0,
                                          left: 0,
                                          right: 0,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                                            color: Colors.black.withOpacity(0.6),
                                            child: Text(
                                              p.split(RegExp(r'[/\\]')).last,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.alarm_on, color: Colors.amber, size: 26),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Auto-Deletion Scheduled',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Deletion Date & Time:',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  deleteDate,
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: primaryColor,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  imagePaths.length > 1
                                      ? 'These ${imagePaths.length} screenshots will be permanently deleted from your device automatically when the timer expires.'
                                      : 'This screenshot will be permanently deleted from your device automatically when the timer expires.',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: isDark ? Colors.white70 : Colors.black54,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.delete_forever),
                        label: const Text('Delete Now'),
                        onPressed: () => _deleteNow(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.check),
                        label: const Text('Done'),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
