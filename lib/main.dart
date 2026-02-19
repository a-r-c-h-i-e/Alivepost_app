import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'login_page.dart';
import 'prescription_model.dart';
import 'notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Timezone init + locale set happens inside NotificationService().init()
  await NotificationService().init();
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
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MaterialApp(
      theme: ThemeData(
        fontFamily: 'Roboto',
        primaryColor: const Color(0xFF6C63FF),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C63FF)),
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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _mobileNumber = prefs.getString('mobileNumber');
    final userDataString = prefs.getString('user_data');

    if (userDataString != null) {
      try {
        final List<dynamic> jsonList = json.decode(userDataString);
        final prescriptions = jsonList.map((e) => Prescription.fromJson(e)).toList();
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
      // If no local data, try to fetch
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
          'http://13.127.160.202/api/prescriptions/patient/$_mobileNumber');
      // Using dummy for now if server not running, but respecting request to use localhost
      // For testing, if localhost fails, we might want to fallback or show error.
      // But keeping strict to request.
      
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_data', response.body);
        
        final List<dynamic> jsonList = json.decode(response.body);
        final prescriptions = jsonList.map((e) => Prescription.fromJson(e)).toList();
        setState(() {
          _prescriptions = prescriptions;
        });
        _autoScheduleReminders(prescriptions);
      } else {
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to refresh. Status: ${response.statusCode}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error refreshing data. Check connection.')),
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
  /// Only fires an immediate alarm for medicines due NOW (within ±5 min).
  /// Others are silently scheduled for the future.
  Future<void> _autoScheduleReminders(List<Prescription> prescriptions) async {
    // Cancel all existing notifications first to avoid duplicates
    await NotificationService().cancelAll();
    print('[Alarm] Scheduling alarms for ${prescriptions.length} prescriptions...');

    int scheduledCount = 0;
    int immediateCount = 0;
    const dueSoonWindow = Duration(minutes: 5);

    for (final prescription in prescriptions) {
      for (final timing in prescription.timings) {
        final time = _getTimeForTiming(timing);
        if (time == null) continue;

        final now = DateTime.now();
        var scheduledDate = DateTime(
          now.year, now.month, now.day, time.hour, time.minute,
        );

        // Use a stable unique ID from prescription + timing
        final notifId = '${prescription.id}_${timing.id}'.hashCode;

        final label = timing.customTime != null && timing.customTime!.isNotEmpty
            ? '${timing.timingType} (${timing.customTime})'
            : timing.timingType;

        final diff = scheduledDate.difference(now);

        // Check if this medicine is due NOW (within ±5 min window)
        if (diff.abs() <= dueSoonWindow) {
          // Fire immediately with alarm sound
          print('[Alarm]  ${prescription.medicine.name} is DUE NOW ($label)');
          await NotificationService().showAlarmNow(
            id: notifId,
            title: ' Time to take medicine!',
            body: '${prescription.medicine.name} ${prescription.medicine.dosage} — $label',
            payload: prescription.medicine.name,
          );
          immediateCount++;
        } else {
          // Schedule for future
          if (scheduledDate.isBefore(now)) {
            scheduledDate = scheduledDate.add(const Duration(days: 1));
          }

          print('[Alarm] ${prescription.medicine.name} → $label → scheduled at $scheduledDate (id=$notifId)');

          try {
            await NotificationService().scheduleNotification(
              id: notifId,
              title: ' Medicine Reminder',
              body:
                  'Time to take ${prescription.medicine.name} ${prescription.medicine.dosage} ($label)',
              scheduledTime: scheduledDate,
              payload: prescription.medicine.name,
            );
            scheduledCount++;
          } catch (e) {
            print('[Alarm ERROR] Failed to schedule ${prescription.medicine.name} ($label): $e');
          }
        }
      }
    }
    print('[Alarm] Done. $immediateCount due now, $scheduledCount scheduled for later.');
  }

  /// Parse timing into hour + minute. Supports customTime (e.g. "14:30") and
  /// standard timing types (MORNING, AFTERNOON, EVENING, NIGHT).
  ({int hour, int minute})? _getTimeForTiming(Timing timing) {
    // If a custom time is provided (e.g. "14:30"), parse hour AND minute
    if (timing.customTime != null && timing.customTime!.isNotEmpty) {
      try {
        final parts = timing.customTime!.split(':');
        return (hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      } catch (_) {
        print('[Alarm] Failed to parse customTime: ${timing.customTime}');
      }
    }

    // Map standard timing types to default hours
    switch (timing.timingType.toUpperCase()) {
      case 'MORNING':
        return (hour: 8, minute: 0);   // 8:00 AM
      case 'AFTERNOON':
        return (hour: 13, minute: 0);  // 1:00 PM
      case 'EVENING':
        return (hour: 18, minute: 0);  // 6:00 PM
      case 'NIGHT':
        return (hour: 21, minute: 0);  // 9:00 PM
      default:
        return (hour: 9, minute: 0);   // Fallback: 9:00 AM
    }
  }

  void _showReminderDialog(Prescription prescription) async {
    final TimeOfDay? selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (selectedTime != null && mounted) {
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

      // Use a unique ID that won't collide with auto-scheduled ones
      final notifId = 'manual_${prescription.id}_${selectedTime.hour}_${selectedTime.minute}'.hashCode;

      try {
        final diff = scheduledDate.difference(now);

        if (diff.inMinutes <= 1) {
          // If within 1 minute, fire immediately
          await NotificationService().showAlarmNow(
            id: notifId,
            title: '💊 Medicine Reminder',
            body: 'Take ${prescription.medicine.name} ${prescription.medicine.dosage} now!',
            payload: prescription.medicine.name,
          );
        } else {
          // Schedule for later
          await NotificationService().scheduleNotification(
            id: notifId,
            title: '💊 Medicine Reminder',
            body: 'Take ${prescription.medicine.name} ${prescription.medicine.dosage} now!',
            scheduledTime: scheduledDate,
            payload: prescription.medicine.name,
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Reminder set for ${selectedTime.format(context)}',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        print('[Alarm ERROR] Manual scheduling failed: $e');
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Text(
          'My Medications',
          style: TextStyle(
            color: Theme.of(context).primaryColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.grey),
            onPressed: _refreshData,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.grey),
            onPressed: _logout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _prescriptions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.asset(
                        'assets/empty.svg',
                        height: 150,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'No prescriptions found',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refreshData,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _prescriptions.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final prescription = _prescriptions[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withValues(alpha: 0.1),
                              spreadRadius: 1,
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  SvgPicture.asset(
                                    'assets/medicine.svg',
                                    height: 40,
                                    width: 40,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          prescription.medicine.name,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        Text(
                                          '${prescription.medicine.dosage} • ${prescription.medicine.type}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () =>
                                        _showReminderDialog(prescription),
                                    icon: const Icon(
                                      Icons.alarm_add_rounded,
                                      color: Color(0xFF6C63FF),
                                      size: 28,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                children: prescription.timings
                                    .map(
                                      (t) => Chip(
                                        label: Text(
                                          t.timingType,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                        ),
                                        backgroundColor: const Color(0xFF6C63FF)
                                            .withValues(alpha: 0.8),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 0,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          side: BorderSide.none,
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
