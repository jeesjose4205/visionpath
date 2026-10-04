import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/models/detected_object.dart';
import 'package:visionpath/models/navigation_decision.dart';
import 'package:visionpath/models/object_position.dart';
import 'package:visionpath/models/path_analysis.dart';
import 'package:visionpath/models/proximity_level.dart';
import 'package:visionpath/services/navigation_service.dart';
import 'package:visionpath/services/speech_queue.dart';
import 'package:visionpath/services/voice_service.dart';

DetectedObject _obj(
  String className,
  ObjectPosition position, {
  double? meters,
  double confidence = 0.9,
}) {
  final double centerX = switch (position) {
    ObjectPosition.left => 0.15,
    ObjectPosition.center => 0.5,
    ObjectPosition.right => 0.85,
  };
  return DetectedObject(
    className: className,
    confidence: confidence,
    boundingBox: Rect.fromLTWH(centerX - 0.1, 0.3, 0.2, 0.4),
    position: position,
    proximity: ProximityLevel.far,
    distanceMeters: meters,
    distanceConfidence: meters == null ? null : 0.9,
  );
}

PathAnalysisResult _clearPath() => const PathAnalysisResult(
      analysis: PathAnalysis.clear,
      leftMargin: 1.0,
      rightMargin: 1.0,
    );

/// Feed one frame and take the sentences the screen would have queued.
List<String> _announce(
  NavigationService nav,
  List<DetectedObject> objects,
) {
  nav.decide(_clearPath(), objects);
  final List<String> sentences = nav.pendingSentences;
  // The screen always commits what it decided to speak.
  nav.commitAnnouncement();
  return sentences;
}

/// The press-and-hold assistant must own the floor: the camera keeps running,
/// but nothing it sees is spoken while the user is talking.
void main() {
  group('detected-object voice suppression', () {
    late NavigationService nav;

    setUp(() => nav = NavigationService());

    test('announcements work normally while unmuted', () {
      expect(nav.sceneVoiceMuted, isFalse);
      final List<String> spoken = _announce(nav, <DetectedObject>[
        _obj('chair', ObjectPosition.center, meters: 3.4),
      ]);
      expect(spoken, isNotEmpty);
    });

    test('a muted hold withholds detected-object sentences', () {
      // "Person detected, 2.5 meters ahead." before the hold.
      expect(
        _announce(nav, <DetectedObject>[
          _obj('person', ObjectPosition.center, meters: 2.5),
        ]),
        isNotEmpty,
      );

      nav.sceneVoiceMuted = true;

      // Detection keeps running; the object sentences are simply never handed
      // out, so nothing reaches the TTS queue.
      expect(
        _announce(nav, <DetectedObject>[
          _obj('person', ObjectPosition.center, meters: 2.5),
          _obj('chair', ObjectPosition.left, meters: 4),
          _obj('bottle', ObjectPosition.right, meters: 3),
        ]),
        isEmpty,
      );
      expect(nav.pendingSentences, isEmpty);
    });

    test('safety decisions are not scene sentences and still speak', () {
      final DetectedObject danger = _obj('person', ObjectPosition.center,
              meters: 0.7)
          .copyWith(proximity: ProximityLevel.veryNear);

      nav.sceneVoiceMuted = true;
      nav.decide(
        PathAnalysisResult(
          analysis: PathAnalysis.obstacleCenter,
          primaryBlocker: danger,
          leftMargin: 0.1,
          rightMargin: 0.1,
        ),
        <DetectedObject>[danger],
      );

      // A blind user must still be told to stop. Only the "Chair detected."
      // style narration is withheld.
      expect(nav.lastDecision, NavigationDecision.stop);
      expect(nav.lastSpokenMessage, isNotEmpty);
      // ...and nothing was queued for it, because the screen speaks safety
      // decisions through its own interrupting path.
      expect(nav.pendingSentences, isEmpty);
    });

    test('nothing from the listening period is replayed afterwards', () {
      nav.sceneVoiceMuted = true;
      // Four different objects appear while the user is talking. Each is
      // consumed silently so the scene state moves on.
      for (final String label in <String>['person', 'chair', 'table', 'bottle']) {
        _announce(nav, <DetectedObject>[
          _obj(label, ObjectPosition.center, meters: 3),
        ]);
      }

      // Normal navigation resumes: the backlog must not come flooding back.
      nav.sceneVoiceMuted = false;
      expect(nav.pendingSentences, isEmpty);

      // An unchanged scene stays silent.
      final List<String> unchanged = _announce(nav, <DetectedObject>[
        _obj('bottle', ObjectPosition.center, meters: 3),
      ]);
      expect(unchanged, isEmpty);
    });

    test('a genuinely new detection after the hold is announced', () {
      nav.sceneVoiceMuted = true;
      _announce(nav, <DetectedObject>[
        _obj('person', ObjectPosition.center, meters: 3),
      ]);
      nav.sceneVoiceMuted = false;
      expect(nav.pendingSentences, isEmpty);

      // A chair the user has not been told about yet is worth speaking.
      final List<String> fresh = _announce(nav, <DetectedObject>[
        _obj('person', ObjectPosition.center, meters: 3),
        _obj('chair', ObjectPosition.left, meters: 4),
      ]);
      expect(fresh.join(' ').toLowerCase(), contains('chair'));
    });

    test('a stopped run does not inherit the mute', () {
      nav.sceneVoiceMuted = true;
      nav.reset();
      expect(nav.sceneVoiceMuted, isFalse);
      expect(
        _announce(nav, <DetectedObject>[
          _obj('chair', ObjectPosition.center, meters: 3),
        ]),
        isNotEmpty,
      );
    });
  });

  group('queued announcements when the hold starts', () {
    test('pending sentences are dropped, the live one keeps speaking', () {
      // Requirement: nothing new may start, but the sentence already coming out
      // of the speaker finishes instead of being cut mid-word.
      final SpeechQueue queue = SpeechQueue();
      queue.add('Person detected, 2.5 meters ahead.');
      queue.add('Chair detected.');
      queue.add('Table detected.');
      expect(queue.takeNext(), 'Person detected, 2.5 meters ahead.');

      queue.clearPending();

      expect(queue.pending, isEmpty);
      expect(queue.hasPending, isFalse);
      expect(queue.state, SpeechState.speaking);
      expect(queue.activeSentence, 'Person detected, 2.5 meters ahead.');
    });

    test('the speaker is still reported as busy until it finishes', () {
      // A waiting microphone uses this to know when it is really safe to open,
      // so clearing the queue must not fake silence.
      final VoiceService service = VoiceService();
      addTearDown(service.dispose);
      service.setEnabled(true);
      service.enqueueSpeech('Person detected, 2.5 meters ahead.');
      expect(service.isSpeaking, isTrue);

      service.enqueueSpeech('Chair detected.');
      service.clearSpeechQueue();

      expect(service.pendingSpeech, isEmpty);
      // Still speaking: the sentence in flight has not finished yet.
      expect(service.isSpeaking, isTrue);
      expect(service.activeSpeech, 'Person detected, 2.5 meters ahead.');
    });

    test('stop still silences everything immediately', () {
      final SpeechQueue queue = SpeechQueue();
      queue.add('Person detected.');
      queue.takeNext();
      queue.clear();
      expect(queue.state, SpeechState.idle);
      expect(queue.isSpeaking, isFalse);
    });
  });
}