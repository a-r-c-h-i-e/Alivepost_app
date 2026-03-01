import 'dart:async';
import 'dart:convert';
import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_animate/flutter_animate.dart';
import 'alarm_ring_screen.dart';
import 'login_page.dart';
import 'prescription_model.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Alarm.init();
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  bool? _isLoggedIn;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoggedIn == null) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp(
      navigatorKey: navigatorKey,
      theme: ThemeData(
        fontFamily: 'Roboto',
        primaryColor: const Color(0xFF10B981),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF10B981)),
        useMaterial3: true,
      ),
      home: _isLoggedIn! ? const HomePage() : const LoginPage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Prescription> _prescriptions = [];
  bool _isLoading = true;
  String? _mobileNumber;
  StreamSubscription<AlarmSet>? _ringSub;
  final Set<int> _shownAlarmIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    _listenToAlarms();
  }

  @override
  void dispose() {
    _ringSub?.cancel();
    super.dispose();
  }

  /// Listen to alarm ringing events and show the ring screen.
  void _listenToAlarms() {
    _ringSub = Alarm.ringing.listen((AlarmSet alarmSet) {
      for (final alarm in alarmSet.alarms) {
        // Only navigate for alarms we haven't already shown a screen for
        if (_shownAlarmIds.contains(alarm.id)) continue;
        _shownAlarmIds.add(alarm.id);

        final nav = navigatorKey.currentState;
        if (nav != null) {
          nav.push(
            MaterialPageRoute(
              builder: (_) => AlarmRingScreen(alarmSettings: alarm),
            ),
          ).then((_) {
            // Allow this alarm ID to trigger again in the future
            _shownAlarmIds.remove(alarm.id);
          });
        }
      }
    });
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _mobileNumber = prefs.getString('mobileNumber');
    final userDataString = prefs.getString('user_data');

    if (userDataString != null) {
      try {
        final List<dynamic> jsonList = json.decode(userDataString);
        final prescriptions =
            jsonList.map((e) => Prescription.fromJson(e)).toList();
        setState(() {
          _prescriptions = prescriptions;
          _isLoading = false;
        });
        _autoScheduleReminders(prescriptions);
      } catch (e) {
        print('Error parsing local data: $e');
        setState(() {
          _isLoading = false;
        });
      }
    } else {
      _refreshData();
    }
  }

  Future<void> _refreshData() async {
    if (_mobileNumber == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final url = Uri.parse(
        'https://api.alivepost.com/api/prescriptions/patient/$_mobileNumber',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_data', response.body);

        final List<dynamic> jsonList = json.decode(response.body);
        final prescriptions =
            jsonList.map((e) => Prescription.fromJson(e)).toList();
        setState(() {
          _prescriptions = prescriptions;
        });
        _autoScheduleReminders(prescriptions);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh. Status: ${response.statusCode}'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error refreshing data. Check connection.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  /// Automatically schedule daily reminders based on prescription timings.
  Future<void> _autoScheduleReminders(
    List<Prescription> prescriptions,
  ) async {
    print(
      '[AlarmPkg] Scheduling alarms for ${prescriptions.length} prescriptions...',
    );

    int scheduledCount = 0;
    int immediateCount = 0;
    const dueSoonWindow = Duration(minutes: 5);
    final now = DateTime.now();

    for (final prescription in prescriptions) {
      for (final timing in prescription.timings) {
        final time = _getTimeForTiming(timing);
        if (time == null) continue;

        var scheduledDate = DateTime(
          now.year,
          now.month,
          now.day,
          time.hour,
          time.minute,
        );

        final alarmId =
            '${prescription.id}_${timing.id}'.hashCode & 0x7fffffff;

        final label =
            timing.customTime != null && timing.customTime!.isNotEmpty
                ? '${timing.timingType} (${timing.customTime})'
                : timing.timingType;

        final diff = scheduledDate.difference(now);

        if (diff.abs() <= dueSoonWindow) {
          // Due now
          print(
            '[AlarmPkg] ${prescription.medicine.name} is DUE NOW ($label)',
          );

          final alarmSettings = AlarmSettings(
            id: alarmId,
            dateTime: DateTime.now().add(const Duration(seconds: 2)),
            assetAudioPath: 'assets/ringtone/ringtone.mp3',
            loopAudio: true,
            vibrate: true,
            androidFullScreenIntent: true,
            volumeSettings: VolumeSettings.fade(
              fadeDuration: Duration(seconds: 3),
              volume: 1,
              volumeEnforced: true,
            ),
            notificationSettings: NotificationSettings(
              title: 'Time to take medicine!',
              body:
                  '${prescription.medicine.name} ${prescription.medicine.dosage} — $label',
              keepNotificationAfterAlarmEnds: true,
              stopButton: 'Stop',
            ),
          );

          await Alarm.set(alarmSettings: alarmSettings);
          immediateCount++;
        } else {
          // Future
          if (scheduledDate.isBefore(now)) {
            scheduledDate = scheduledDate.add(const Duration(days: 1));
          }

          print(
            '[AlarmPkg] ${prescription.medicine.name} → $label → $scheduledDate',
          );

          final alarmSettings = AlarmSettings(
            id: alarmId,
            dateTime: scheduledDate,
            assetAudioPath: 'assets/ringtone/ringtone.mp3',
            loopAudio: true,
            vibrate: true,
            androidFullScreenIntent: true,
            volumeSettings: VolumeSettings.fade(
              fadeDuration: Duration(seconds: 3),
              volume: 1,
              volumeEnforced: true,
            ),
            notificationSettings: NotificationSettings(
              title: 'Medicine Reminder',
              body:
                  'Time to take ${prescription.medicine.name} ${prescription.medicine.dosage} ($label)',
              keepNotificationAfterAlarmEnds: true,
              stopButton: 'Stop',
            ),
          );

          try {
            await Alarm.set(alarmSettings: alarmSettings);
            scheduledCount++;
          } catch (e) {
            print(
              '[AlarmPkg ERROR] Failed for ${prescription.medicine.name}: $e',
            );
          }
        }
      }
    }

    print(
      '[AlarmPkg] Done. $immediateCount due now, $scheduledCount scheduled.',
    );
  }

  /// Parse timing into hour + minute.
  ({int hour, int minute})? _getTimeForTiming(Timing timing) {
    if (timing.customTime != null && timing.customTime!.isNotEmpty) {
      try {
        final parts = timing.customTime!.split(':');
        return (hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      } catch (_) {
        print('[Alarm] Failed to parse customTime: ${timing.customTime}');
      }
    }

    switch (timing.timingType.toUpperCase()) {
      case 'MORNING':
        return (hour: 8, minute: 0);
      case 'AFTERNOON':
        return (hour: 13, minute: 0);
      case 'EVENING':
        return (hour: 18, minute: 0);
      case 'NIGHT':
        return (hour: 21, minute: 0);
      default:
        return (hour: 9, minute: 0);
    }
  }

  /// Manual reminder via time picker
  void _showReminderDialog(Prescription prescription) async {
    final TimeOfDay? selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (selectedTime == null || !mounted) return;

    final now = DateTime.now();

    var scheduledDate = DateTime(
      now.year,
      now.month,
      now.day,
      selectedTime.hour,
      selectedTime.minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    final alarmId =
        'manual_${prescription.id}_${selectedTime.hour}_${selectedTime.minute}'
            .hashCode &
        0x7fffffff;

    try {
      final diff = scheduledDate.difference(now);

      final DateTime fireTime =
          diff.inMinutes <= 1
              ? now.add(const Duration(seconds: 2))
              : scheduledDate;

      final alarmSettings = AlarmSettings(
        id: alarmId,
        dateTime: fireTime,
        assetAudioPath: 'assets/ringtone/ringtone.mp3',
        loopAudio: true,
        vibrate: true,
        androidFullScreenIntent: true,
        volumeSettings: VolumeSettings.fade(
          fadeDuration: Duration(seconds: 3),
          volume: 1,
          volumeEnforced: true,
        ),
        notificationSettings: NotificationSettings(
          title: 'Medicine Reminder',
          body:
              'Take ${prescription.medicine.name} ${prescription.medicine.dosage}',
          keepNotificationAfterAlarmEnds: true,
          stopButton: 'Stop',
        ),
      );

      await Alarm.set(alarmSettings: alarmSettings);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              diff.inMinutes <= 1
                  ? 'Alarm will ring in a moment!'
                  : 'Reminder set for ${selectedTime.format(context)}',
            ),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      print('[AlarmPkg ERROR] Manual scheduling failed: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to set reminder: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getTimingIcon(String type) {
    switch (type.toUpperCase()) {
      case 'MORNING':
        return '🌅';
      case 'AFTERNOON':
        return '☀️';
      case 'EVENING':
        return '🌇';
      case 'NIGHT':
        return '🌙';
      default:
        return '⏰';
    }
  }

  String _getTimingLabel(Timing timing) {
    final time = _getTimeForTiming(timing);
    if (time == null) return timing.timingType;

    final hour = time.hour;
    final minute = time.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    final displayMin = minute.toString().padLeft(2, '0');

    return '$displayHour:$displayMin $period';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDFBF7), // Beige background
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // Custom App Bar
          SliverAppBar(
            expandedHeight: 140.0,
            floating: false,
            pinned: true,
            elevation: 0,
            backgroundColor: const Color(0xFFFDFBF7),
            surfaceTintColor: Colors.transparent,
            actions: [
              IconButton(
                icon: const Icon(Icons.logout_rounded, color: Color(0xFF94A3B8)),
                tooltip: 'Logout',
                onPressed: _logout,
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16, right: 20),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.medical_services_rounded,
                      color: Color(0xFF10B981),
                      size: 20,
                    ).animate(onPlay: (controller) => controller.repeat(reverse: true))
                     .scaleXY(end: 1.1, duration: 1.5.seconds, curve: Curves.easeInOut),
                  ).animate().fadeIn(delay: 100.ms, duration: 600.ms).slideX(begin: -0.2, end: 0, curve: Curves.easeOutQuad),
                  const SizedBox(width: 12),
                  const Text(
                    'My Profile',
                    style: TextStyle(
                      color: Color(0xFF1E293B),
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      letterSpacing: -0.5,
                    ),
                  ).animate().fadeIn(delay: 200.ms, duration: 600.ms).slideX(begin: -0.1, end: 0, curve: Curves.easeOutQuad),
                ],
              ),
              background: Stack(
                children: [
                   Positioned(
                    top: -40,
                    right: -40,
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF10B981).withValues(alpha: 0.08),
                      ),
                    ).animate(onPlay: (controller) => controller.repeat(reverse: true))
                     .scaleXY(end: 1.2, duration: 4.seconds, curve: Curves.easeInOut),
                  ),
                ],
              ),
            ),
          ),

          // Body Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Your Medications',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF334155),
                    ),
                  ).animate().fadeIn(delay: 300.ms, duration: 600.ms).slideY(begin: 0.2, curve: Curves.easeOutQuad),
                  
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: Color(0xFF10B981), size: 22),
                      tooltip: 'Refresh prescriptions',
                      onPressed: _refreshData,
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                    ),
                  ).animate().fadeIn(delay: 400.ms, duration: 600.ms).scale(curve: Curves.easeOutBack),
                ],
              ),
            ),
          ),

          if (_isLoading)
            const SliverFillRemaining(
              child: Center(
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    color: Color(0xFF10B981),
                    strokeWidth: 3,
                  ),
                ),
              ),
            )
          else if (_prescriptions.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgPicture.asset('assets/login.svg', height: 160)
                        .animate(onPlay: (controller) => controller.repeat(reverse: true))
                        .moveY(begin: -5, end: 5, duration: 2.seconds),
                    const SizedBox(height: 24),
                    Text(
                      'No prescriptions found',
                      style: TextStyle(
                        color: const Color(0xFF64748B),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pull down to refresh',
                      style: TextStyle(
                        color: const Color(0xFF94A3B8),
                        fontSize: 15,
                      ),
                    ),
                  ],
                ).animate().fadeIn(duration: 800.ms).slideY(begin: 0.1, curve: Curves.easeOut),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final prescription = _prescriptions[index];
                    return _buildPrescriptionCard(prescription, index);
                  },
                  childCount: _prescriptions.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPrescriptionCard(Prescription prescription, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.04),
            spreadRadius: 0,
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {}, // Add potential details view later
            splashColor: const Color(0xFF10B981).withValues(alpha: 0.1),
            highlightColor: const Color(0xFF10B981).withValues(alpha: 0.05),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row: icon + medicine name + alarm button
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF10B981).withValues(alpha: 0.2),
                              const Color(0xFF10B981).withValues(alpha: 0.05),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Center(
                          child: const Icon(
                            Icons.medication_liquid_rounded,
                            color: Color(0xFF10B981),
                            size: 28,
                          ).animate(onPlay: (c) => c.repeat(reverse: true))
                           .scaleXY(begin: 0.95, end: 1.05, duration: 2.seconds),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              prescription.medicine.name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1E293B),
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9), // Slate 100
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${prescription.medicine.dosage} • ${prescription.medicine.type}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Material(
                        color: const Color(0xFF10B981).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          onTap: () => _showReminderDialog(prescription),
                          borderRadius: BorderRadius.circular(16),
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Icon(
                              Icons.alarm_add_rounded,
                              color: Color(0xFF10B981),
                              size: 24,
                            ),
                          ),
                        ),
                      ).animate().scale(curve: Curves.easeOutBack, delay: ((index * 100) + 300).ms),
                    ],
                  ),

                  // Notes / exercise
                  if (prescription.notes != null && prescription.notes!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7).withValues(alpha: 0.5), // Amber 100
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDE68A).withValues(alpha: 0.5)), // Amber 200
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.notes_rounded, size: 18, color: Color(0xFFD97706)), // Amber 600
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              prescription.notes!,
                              style: const TextStyle(fontSize: 14, color: Color(0xFF92400E), height: 1.4), // Amber 800
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (prescription.exercise != null && prescription.exercise!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7).withValues(alpha: 0.5), // Green 100
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBBF7D0).withValues(alpha: 0.5)), // Green 200
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.fitness_center_rounded, size: 18, color: Color(0xFF059669)), // Green 600
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              prescription.exercise!,
                              style: const TextStyle(fontSize: 14, color: Color(0xFF065F46), height: 1.4), // Green 800
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  
                  // Divider
                  Container(
                    height: 1,
                    width: double.infinity,
                    color: const Color(0xFFF1F5F9),
                  ),
                  
                  const SizedBox(height: 16),

                  // Timing chips with time labels
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: prescription.timings.map((t) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF10B981),
                              const Color(0xFF059669), // Slightly darker green
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _getTimingIcon(t.timingType),
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${t.timingType} • ${_getTimingLabel(t)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).animate()
     .fadeIn(duration: 500.ms, delay: (index * 100).ms)
     .slideY(begin: 0.1, end: 0, duration: 500.ms, curve: Curves.easeOutQuint);
  }
}
