import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/services/speech_queue.dart';
import 'package:visionpath/services/voice_service.dart';

/// The app builds one [VoiceService] per screen. These tests pin the guarantee
/// that makes overlapping speech impossible: every instance talks through the
/// same queue, so a sentence queued by one screen waits behind a sentence
/// queued by another instead of speaking on top of it.
///
/// Assertions are made synchronously after `enqueueSpeech`, because the pump
/// claims the next sentence before its first await; no microtask can run in
/// between two statements of a test body.
void main() {
  group('single speech channel across services', () {
    late VoiceService navigation;
    late VoiceService assistant;

    setUp(() {
      navigation = VoiceService();
      assistant = VoiceService();
      navigation.setEnabled(true);
      assistant.setEnabled(true);
    });

    tearDown(() async {
      await navigation.dispose();
      await assistant.dispose();
    });

    test('the first sentence is claimed for speaking, not left pending', () {
      expect(navigation.enqueueSpeech('Person detected, 2 meters ahead.'),
          isTrue);
      // Both services see the same single active sentence.
      expect(navigation.speechState, SpeechState.speaking);
      expect(navigation.activeSpeech, 'Person detected, 2 meters ahead.');
      expect(assistant.speechState, SpeechState.speaking);
      expect(assistant.activeSpeech, 'Person detected, 2 meters ahead.');
    });

    test('a second sentence queues behind the one being spoken', () {
      navigation.enqueueSpeech('Person detected, 2 meters ahead.');
      expect(assistant.enqueueSpeech('Chair detected, 3 meters ahead.'),
          isTrue);

      // One engine, one order: the assistant's line waits its turn.
      expect(navigation.pendingSpeech, ['Chair detected, 3 meters ahead.']);
      expect(assistant.pendingSpeech, ['Chair detected, 3 meters ahead.']);
      expect(navigation.activeSpeech, 'Person detected, 2 meters ahead.');
    });

    test('the sentence being spoken is never queued again', () {
      navigation.enqueueSpeech('Person detected, 2 meters ahead.');
      // 50 camera frames of the same person must not become 50 sentences.
      for (int i = 0; i < 50; i++) {
        expect(
          assistant.enqueueSpeech('Person detected, 2 meters ahead.'),
          isFalse,
        );
      }
      expect(navigation.pendingSpeech, isEmpty);
    });

    test('an already queued sentence is not queued twice', () {
      navigation.enqueueSpeech('Person detected, 2 meters ahead.');
      assistant.enqueueSpeech('Chair detected, 3 meters ahead.');

      expect(navigation.enqueueSpeech('Chair detected, 3 meters ahead.'),
          isFalse);
      expect(
        navigation.pendingSpeech
            .where((String s) => s == 'Chair detected, 3 meters ahead.')
            .length,
        1,
      );
    });

    test('one service silencing the queue silences both', () {
      navigation.enqueueSpeech('Person detected, 2 meters ahead.');
      assistant.enqueueSpeech('Chair detected, 3 meters ahead.');
      expect(assistant.hasPendingSpeech, isTrue);

      // Press-and-hold drops pending speech so the microphone can hear the
      // user; that has to clear the shared queue, not a local copy.
      navigation.clearSpeechQueue();
      expect(assistant.pendingSpeech, isEmpty);
      expect(assistant.hasPendingSpeech, isFalse);
    });

    test('the two services never disagree about the queue', () {
      navigation.enqueueSpeech('Person detected, 2 meters ahead.');
      assistant.enqueueSpeech('Chair detected, 3 meters ahead.');
      navigation.enqueueSpeech('Table detected, 4 meters ahead.');

      expect(navigation.pendingSpeech, assistant.pendingSpeech);
      expect(navigation.speechState, assistant.speechState);
      expect(navigation.activeSpeech, assistant.activeSpeech);
      expect(navigation.pendingSpeech, hasLength(2));
    });

    test('a muted service never reaches the shared queue', () {
      final VoiceService muted = VoiceService();
      addTearDown(muted.dispose);

      expect(muted.enqueueSpeech('Chair detected, 3 meters ahead.'), isFalse);
      expect(navigation.hasPendingSpeech, isFalse);
      expect(navigation.isSpeaking, isFalse);
    });

    test('stopping one service stops speech for both', () {
      navigation.enqueueSpeech('Person detected, 2 meters ahead.');
      assistant.enqueueSpeech('Chair detected, 3 meters ahead.');

      navigation.stop();
      expect(assistant.hasPendingSpeech, isFalse);
      expect(assistant.isSpeaking, isFalse);
    });
  });
}