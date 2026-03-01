import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';

/// Full-screen alarm UI shown when a medicine alarm fires.
class AlarmRingScreen extends StatefulWidget {
  final AlarmSettings alarmSettings;

  const AlarmRingScreen({super.key, required this.alarmSettings});

  @override
  State<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends State<AlarmRingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _stopAlarm() async {
    await Alarm.stop(widget.alarmSettings.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _snoozeAlarm() async {
    await Alarm.stop(widget.alarmSettings.id);

    final snoozeSettings = widget.alarmSettings.copyWith(
      dateTime: DateTime.now().add(const Duration(minutes: 5)),
    );
    await Alarm.set(alarmSettings: snoozeSettings);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Snoozed for 5 minutes'),
          backgroundColor: Color(0xFF6C63FF),
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final notif = widget.alarmSettings.notificationSettings;
    final title = notif.title;
    final body = notif.body;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),

            // Pulsing alarm icon
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF6C63FF).withValues(alpha: 0.3),
                      const Color(0xFF6C63FF).withValues(alpha: 0.05),
                    ],
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.alarm_on_rounded,
                    size: 72,
                    color: Color(0xFF6C63FF),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 40),

            // Title
            Text(
              title,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 16),

            // Body
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                body,
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white.withValues(alpha: 0.8),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const Spacer(flex: 3),

            // Action buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                children: [
                  // Snooze button
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _snoozeAlarm,
                      icon: const Icon(Icons.snooze_rounded, size: 22),
                      label: const Text(
                        'Snooze\n5 min',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, height: 1.3),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 20),

                  // Stop button
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _stopAlarm,
                      icon: const Icon(Icons.check_circle_outline, size: 24),
                      label: const Text(
                        'Taken / Stop',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 8,
                        shadowColor:
                            const Color(0xFF6C63FF).withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}
