import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

/// يهيئ مخرجات الصوت مرة واحدة وفق المنصة.
Future<void> initializeAudioPlatform() async {
  if (kIsWeb) return;

  if (defaultTargetPlatform == TargetPlatform.windows) {
    JustAudioMediaKit.ensureInitialized(windows: true, linux: false);
    return;
  }

  if (defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS) {
    return;
  }

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.hafiz.hafiz.quran_audio',
    androidNotificationChannelName: 'تلاوة القرآن',
    androidNotificationOngoing: true,
  );

  final session = await AudioSession.instance;
  await session.configure(AudioSessionConfiguration.speech());
}
