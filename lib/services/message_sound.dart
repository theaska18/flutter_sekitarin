import 'package:flutter/services.dart';

/// Short touch/click feedback for sending and receiving chat messages.
class MessageSound {
  static Future<void> play() async {
    await SystemSound.play(SystemSoundType.click);
    await HapticFeedback.selectionClick();
  }
}
