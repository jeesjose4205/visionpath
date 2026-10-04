import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/models/detected_object.dart';
import 'package:visionpath/models/navigation_decision.dart';
import 'package:visionpath/models/object_position.dart';
import 'package:visionpath/models/path_analysis.dart';
import 'package:visionpath/models/proximity_level.dart';
import 'package:visionpath/services/navigation_service.dart';
import 'package:visionpath/services/scene_announcer.dart';

/// A detection with a real class, a real box and only the values the pipeline
/// actually produced. Boxes are chosen so their centerX falls in the intended
/// third of the frame (LEFT < 0.33, CENTER 0.33-0.66, RIGHT > 0.66).
DetectedObject _obj(
  String className,
  ObjectPosition position, {
  double? meters,
  ProximityLevel? proximity,
  double confidence = 0.9,
  double width = 0.2,
  double height = 0.4,
}) {
  final double centerX = switch (position) {
    ObjectPosition.left => 0.15,
    ObjectPosition.center => 0.5,
    ObjectPosition.right => 0.85,
  };
  final double left = centerX - (width / 2);
  return DetectedObject(
    className: className,
    confidence: confidence,
    boundingBox: Rect.fromLTWH(left, 0.3, width, height),
    position: position,
    proximity: proximity ?? ProximityLevel.far,
    distanceMeters: meters,
    distanceConfidence: meters == null ? null : 0.9,
  );
}

PathAnalysisResult _clearPath() => const PathAnalysisResult(
      analysis: PathAnalysis.clear,
      leftMargin: 1.0,
      rightMargin: 1.0,
    );

/// Announce the scene once and let each object's smoothed distance converge,
/// then return the sentences produced on the FIRST frame.
///
/// Several frames are needed because each object's spoken distance is an
/// exponential moving average before it is compared against the threshold.
List<String> _settle(
  SceneAnnouncer announcer,
  List<DetectedObject> scene, {
  int frames = 6,
}) {
  final List<String> initial =
      announcer.compose(detections: scene)?.sentences ?? const <String>[];
  for (int frame = 1; frame < frames; frame++) {
    announcer.compose(detections: scene);
    announcer.commit();
  }
  return initial;
}

/// Mirror what the navigation screen does every camera frame: compose, and
/// commit only when the sentences were actually queued.
///
/// The commit is what moves the "already told" baseline, so a frame that
/// produced nothing must not commit — otherwise each smoothed step would be
/// compared against the previous step and real movement would never add up.
List<String> _pump(
  SceneAnnouncer announcer,
  List<DetectedObject> scene, {
  int maxFrames = 10,
}) {
  for (int frame = 0; frame < maxFrames; frame++) {
    final List<String> sentences =
        announcer.compose(detections: scene)?.sentences ?? const <String>[];
    if (sentences.isNotEmpty) {
      announcer.commit();
      return sentences;
    }
  }
  return const <String>[];
}

/// Pull the meter value out of a spoken sentence
/// ("Person detected, 2.4 meters ahead.").
double _metersOf(String text) {
  final RegExpMatch? match =
      RegExp(r'([0-9]+(?:\.[0-9]+)?) meters?').firstMatch(text);
  return double.parse(match!.group(1)!);
}

void main() {
  group('scene announcer: one complete sentence per object', () {
    test('names the object, its side and its own distance', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      final List<String> sentences = _settle(
        announcer,
        [_obj('chair', ObjectPosition.center, meters: 2.4)],
      );
      expect(sentences, ['Chair detected, 2.4 meters ahead.']);
    });

    test('omits the distance when depth has no valid reading', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      final List<String> sentences =
          _settle(announcer, [_obj('chair', ObjectPosition.center)]);
      expect(sentences, ['Chair detected ahead.']);
    });

    test('never invents a distance for an unreadable object', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      final List<String> sentences = _settle(announcer, [
        _obj('chair', ObjectPosition.center),
        _obj('person', ObjectPosition.left, meters: 1.8),
      ]);
      expect(sentences.any((String s) => s.contains('Chair')), isTrue);
      expect(
        sentences.firstWhere((String s) => s.contains('Chair')),
        'Chair detected ahead.',
      );
    });

    test('says nothing at all when nothing is detected', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      expect(announcer.compose(detections: []), isNull);
      expect(announcer.hasChange, isFalse);
      expect(announcer.pending, isNull);
    });

    test('physical sides are never mirrored', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      final List<String> sentences = _settle(announcer, [
        _obj('chair', ObjectPosition.left, meters: 1.0),
        _obj('person', ObjectPosition.center, meters: 1.0),
        _obj('table', ObjectPosition.right, meters: 1.0),
      ]);
      expect(sentences, [
        'Person detected, 1 meter ahead.',
        'Chair detected, 1 meter to your left.',
        'Table detected, 1 meter to your right.',
      ]);
    });

    test('whole meters are spoken without a pointless decimal', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      final List<String> sentences = _settle(
        announcer,
        [_obj('table', ObjectPosition.right, meters: 3.0)],
      );
      expect(sentences.single, 'Table detected, 3 meters to your right.');
    });

    test('a very close object keeps its small distance', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      final List<String> sentences = _settle(
        announcer,
        [_obj('bottle', ObjectPosition.center, meters: 0.4)],
      );
      expect(sentences.single, 'Bottle detected, 0.4 meters ahead.');
    });
  });

  group('scene announcer: multiple objects', () {
    test('each object becomes its own sentence, nearest first', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      final List<String> sentences = _settle(announcer, [
        _obj('chair', ObjectPosition.left, meters: 2.4),
        _obj('person', ObjectPosition.center, meters: 1.8),
        _obj('table', ObjectPosition.right, meters: 3.2),
      ]);
      expect(sentences, [
        'Person detected, 1.8 meters ahead.',
        'Chair detected, 2.4 meters to your left.',
        'Table detected, 3.2 meters to your right.',
      ]);
    });

    test('every object keeps its own distance', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      final List<String> sentences = _settle(announcer, [
        _obj('chair', ObjectPosition.left, meters: 2.4),
        _obj('person', ObjectPosition.center, meters: 1.8),
        _obj('table', ObjectPosition.right, meters: 3.2),
      ]);
      expect(sentences[0], contains('1.8 meters'));
      expect(sentences[1], contains('2.4 meters'));
      expect(sentences[2], contains('3.2 meters'));
    });

    test('directly ahead outranks the sides at the same distance', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      final List<String> sentences = _settle(announcer, [
        _obj('bench', ObjectPosition.left, meters: 2.0),
        _obj('person', ObjectPosition.center, meters: 2.0),
        _obj('bottle', ObjectPosition.right, meters: 2.0),
      ]);
      expect(sentences[0], startsWith('Person detected'));
      expect(sentences[1], startsWith('Bench detected'));
      expect(sentences[2], startsWith('Bottle detected'));
    });

    test('a crowded frame is trimmed to the most relevant objects', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      final List<String> sentences = _settle(announcer, [
        _obj('person', ObjectPosition.center, meters: 0.9),
        _obj('chair', ObjectPosition.left, meters: 1.4),
        _obj('car', ObjectPosition.right, meters: 2.0),
        _obj('bus', ObjectPosition.left, meters: 2.6),
        _obj('bench', ObjectPosition.right, meters: 3.4),
        _obj('bottle', ObjectPosition.center, meters: 4.1),
      ]);
      expect(sentences.length, SceneAnnouncer.maxAnnouncedObjects);
      expect(sentences.any((String s) => s.contains('Bench')), isFalse);
      expect(sentences.any((String s) => s.contains('Bottle')), isFalse);
      expect(sentences.first, startsWith('Person detected'));
    });

    test('the path blocker is spoken first', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      final DetectedObject table =
          _obj('table', ObjectPosition.right, meters: 5.0);
      final DetectedObject person =
          _obj('person', ObjectPosition.left, meters: 4.0);
      final List<String> sentences = announcer
          .compose(detections: [table, person], primaryBlocker: person)!
          .sentences;
      expect(sentences.first, startsWith('Person detected'));
    });

    test('duplicate detections of the same object produce one sentence', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      final List<String> sentences = _settle(announcer, [
        _obj('chair', ObjectPosition.left, meters: 2.4),
        _obj('chair', ObjectPosition.left, meters: 2.4),
      ]);
      expect(sentences.length, 1);
      expect(sentences.single, 'Chair detected, 2.4 meters to your left.');
    });

    test('an unknown obstacle is named only when nothing else is', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      expect(
        announcer.compose(detections: [_obj('obstacle', ObjectPosition.center)])!
            .sentences,
        ['Obstacle detected ahead.'],
      );
      expect(
        announcer
            .compose(
              detections: [
                _obj('obstacle', ObjectPosition.center),
                _obj('chair', ObjectPosition.left, meters: 2.4),
              ],
            )!
            .sentences,
        ['Chair detected, 2.4 meters to your left.'],
      );
    });

    test('background structures are never spoken', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      final List<String> sentences = _settle(announcer, [
        _obj('wall', ObjectPosition.center, meters: 4.0),
        _obj('floor', ObjectPosition.left, meters: 1.0),
        _obj('ceiling', ObjectPosition.right, meters: 3.0),
      ]);
      expect(sentences, isEmpty);
      expect(announcer.hasChange, isFalse);
    });

    test('the relevance filter keeps filtered objects out', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      final List<String> sentences = announcer
          .compose(
            detections: [
              _obj('chair', ObjectPosition.left, meters: 2.4),
              _obj('person', ObjectPosition.center, meters: 1.8),
            ],
            include: (DetectedObject o) => o.className != 'person',
          )!
          .sentences;
      expect(sentences, ['Chair detected, 2.4 meters to your left.']);
    });
  });

  group('scene announcer: the same scene is announced only once', () {
    test('100 unchanged frames produce nothing after the first time', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      final List<DetectedObject> scene = [
        _obj('person', ObjectPosition.center, meters: 2.1),
        _obj('chair', ObjectPosition.left, meters: 3.0),
        _obj('table', ObjectPosition.right, meters: 3.5),
      ];

      final List<String> first = announcer.compose(detections: scene)!.sentences;
      expect(first.length, 3);
      announcer.commit();

      for (int frame = 0; frame < 100; frame++) {
        final SceneAnnouncement? next =
            announcer.compose(detections: scene);
        expect(next!.sentences, isEmpty, reason: 'frame $frame');
        expect(announcer.hasChange, isFalse, reason: 'frame $frame');
        announcer.commit();
      }
    });

    test('committing remembers the whole scene, not just what changed', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      final List<DetectedObject> scene = [
        _obj('person', ObjectPosition.center, meters: 2.1),
        _obj('chair', ObjectPosition.left, meters: 3.0),
        _obj('table', ObjectPosition.right, meters: 3.5),
      ];
      // Announce everything.
      expect(announcer.compose(detections: scene)!.sentences.length, 3);
      announcer.commit();

      // An unchanged scene must stay silent forever, even though only the
      // changed objects were announced last time.
      for (int frame = 0; frame < 5; frame++) {
        expect(announcer.compose(detections: scene)!.sentences, isEmpty);
        announcer.commit();
      }
    });

    test('depth jitter under the threshold stays silent', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      _settle(announcer, [_obj('person', ObjectPosition.center, meters: 2.10)]);

      for (final double meters in [2.08, 2.05, 2.12, 2.09, 2.11]) {
        final SceneAnnouncement? scene = announcer.compose(detections: [
          _obj('person', ObjectPosition.center, meters: meters),
        ]);
        expect(scene!.sentences, isEmpty, reason: 'at $meters m');
        announcer.commit();
      }
    });

    test('the threshold is the documented 0.3 m', () {
      expect(SceneAnnouncer.DISTANCE_CHANGE_THRESHOLD, 0.3);
    });
  });

  group('scene announcer: detecting a meaningful change', () {
    test('a meaningful approach is announced, once', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      _settle(announcer, [_obj('person', ObjectPosition.center, meters: 2.1)]);

      final List<String> sentences = _pump(announcer, [
        _obj('person', ObjectPosition.center, meters: 1.6),
      ]);
      expect(sentences.length, 1);
      expect(sentences.single, startsWith('Person detected, '));
      expect(sentences.single, endsWith('meters ahead.'));
      expect(_metersOf(sentences.single), lessThan(2.1));

      // And it does not repeat itself on the frames after that.
      for (int frame = 0; frame < 20; frame++) {
        final SceneAnnouncement? next = announcer.compose(detections: [
          _obj('person', ObjectPosition.center, meters: 1.6),
        ]);
        expect(next!.sentences, isEmpty, reason: 'frame $frame');
        announcer.commit();
      }
    });

    test('an object that changes side is announced', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      _settle(announcer, [_obj('person', ObjectPosition.left, meters: 3.0)]);

      final List<String> sentences = announcer.compose(detections: [
        _obj('person', ObjectPosition.center, meters: 3.0),
      ])!.sentences;
      expect(sentences, ['Person detected, 3 meters ahead.']);
    });

    test('a new object is announced by itself', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      _settle(announcer, [
        _obj('person', ObjectPosition.center, meters: 2.0),
        _obj('chair', ObjectPosition.left, meters: 3.0),
      ]);

      final List<String> sentences = announcer.compose(detections: [
        _obj('person', ObjectPosition.center, meters: 2.0),
        _obj('chair', ObjectPosition.left, meters: 3.0),
        _obj('table', ObjectPosition.center, meters: 2.2),
      ])!.sentences;
      expect(sentences, ['Table detected, 2.2 meters ahead.']);
    });

    test('only the object that moved is re-announced', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      _settle(announcer, [
        _obj('person', ObjectPosition.center, meters: 2.0),
        _obj('chair', ObjectPosition.left, meters: 3.0),
      ]);

      final List<String> sentences = _pump(announcer, [
        _obj('person', ObjectPosition.center, meters: 2.0),
        _obj('chair', ObjectPosition.left, meters: 1.2),
      ]);
      expect(sentences.length, 1);
      expect(sentences.single, contains('Chair detected'));
    });

    test('an object that returns after being gone is announced again', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      _settle(announcer, [
        _obj('person', ObjectPosition.center, meters: 2.0),
        _obj('chair', ObjectPosition.left, meters: 3.0),
      ]);

      // The chair disappears for a while.
      for (int frame = 0; frame < 8; frame++) {
        announcer.compose(detections: [
          _obj('person', ObjectPosition.center, meters: 2.0),
        ]);
        announcer.commit();
      }

      final List<String> back = announcer.compose(detections: [
        _obj('person', ObjectPosition.center, meters: 2.0),
        _obj('chair', ObjectPosition.left, meters: 3.0),
      ])!.sentences;
      expect(back.length, 1);
      expect(back.single, contains('Chair detected'));
    });

    test('unannounced sentences stay pending until they are committed', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      final List<DetectedObject> scene = [
        _obj('chair', ObjectPosition.left, meters: 2.4),
      ];
      for (int frame = 0; frame < 5; frame++) {
        final SceneAnnouncement? next = announcer.compose(detections: scene);
        expect(next!.sentences.length, 1, reason: 'frame $frame');
        expect(announcer.hasChange, isTrue, reason: 'frame $frame');
        // No commit: the caller could not queue it (muted / disabled).
      }
      announcer.commit();
      expect(announcer.hasChange, isFalse);
    });

    test('a safety warning drops the pending line but keeps the history', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      final List<DetectedObject> scene = [
        _obj('person', ObjectPosition.center, meters: 2.0),
        _obj('chair', ObjectPosition.left, meters: 3.0),
      ];
      _settle(announcer, scene);

      // The person suddenly walks close, but a hazard warning interrupts.
      final SceneAnnouncement? alarm = announcer.compose(detections: [
        _obj('person', ObjectPosition.center, meters: 0.8),
        _obj('chair', ObjectPosition.left, meters: 3.0),
      ]);
      expect(alarm!.sentences.length, 1);
      expect(alarm.sentences.single, contains('Person detected'));
      announcer.suppressPending();
      expect(announcer.hasChange, isFalse);
      expect(announcer.pendingSentences, isEmpty);

      // Back to the scene as it was: the chair was already announced, so it
      // must stay silent even though the warning interrupted the flow.
      final List<DetectedObject> unchanged = [
        _obj('person', ObjectPosition.center, meters: 2.0),
        _obj('chair', ObjectPosition.left, meters: 3.0),
      ];
      final SceneAnnouncement? after = announcer.compose(detections: unchanged);
      expect(
        after!.sentences.any((String s) => s.contains('Chair')),
        isFalse,
        reason: 'the chair was already announced before the warning',
      );
    });

    test('a reset forgets the previous run entirely', () {
      final SceneAnnouncer announcer = SceneAnnouncer();
      final List<DetectedObject> scene = [
        _obj('chair', ObjectPosition.left, meters: 2.4),
      ];
      _settle(announcer, scene);
      expect(announcer.compose(detections: scene)!.sentences, isEmpty);

      announcer.reset();
      expect(announcer.compose(detections: scene)!.sentences.length, 1);
    });
  });

  group('navigation service: queueing sentences', () {
    late NavigationService nav;

    setUp(() => nav = NavigationService());

    test('each object is offered as its own sentence', () {
      nav.decide(_clearPath(), [
        _obj('person', ObjectPosition.center, meters: 1.8),
        _obj('chair', ObjectPosition.left, meters: 2.4),
        _obj('table', ObjectPosition.right, meters: 3.2),
      ]);
      expect(nav.pendingSentences, [
        'Person detected, 1.8 meters ahead.',
        'Chair detected, 2.4 meters to your left.',
        'Table detected, 3.2 meters to your right.',
      ]);
      expect(nav.announcedObjects.length, 3);
    });

    test('a single object stays a single short sentence', () {
      nav.decide(_clearPath(), [
        _obj('chair', ObjectPosition.center, meters: 2.4),
      ]);
      expect(nav.pendingSentences, ['Chair detected, 2.4 meters ahead.']);
    });

    test('an empty frame reports the clear path, not an object', () {
      nav.decide(_clearPath(), []);
      expect(nav.lastSpokenMessage, 'Path appears clear. Move forward.');
      expect(nav.pendingSentences, isEmpty);
      expect(nav.announcementChanged, isFalse);
    });

    test('a very close obstacle replaces the whole scene list', () {
      final DetectedObject person = _obj(
        'person',
        ObjectPosition.center,
        meters: 0.6,
        proximity: ProximityLevel.veryNear,
        height: 0.7,
        width: 0.25,
      );
      nav.decide(
        PathAnalysisResult(
          analysis: PathAnalysis.obstacleCenter,
          leftMargin: 0.1,
          rightMargin: 0.1,
          primaryBlocker: person,
        ),
        [
          _obj('chair', ObjectPosition.left, meters: 3.5),
          person,
          _obj('table', ObjectPosition.right, meters: 2.8),
        ],
      );
      expect(nav.lastDecision, NavigationDecision.stop);
      expect(nav.lastSpokenMessage, 'Stop. Person very close.');
      expect(nav.pendingSentences, isEmpty);
      expect(nav.announcementChanged, isFalse);
    });

    test('after the danger passes only real changes are announced', () {
      final DetectedObject person = _obj(
        'person',
        ObjectPosition.center,
        proximity: ProximityLevel.veryNear,
      );
      nav.decide(
        PathAnalysisResult(
          analysis: PathAnalysis.obstacleCenter,
          leftMargin: 0.1,
          rightMargin: 0.1,
          primaryBlocker: person,
        ),
        [person],
      );
      expect(nav.lastSpokenMessage, 'Stop. Person very close.');

      nav.decide(_clearPath(), [_obj('chair', ObjectPosition.left, meters: 2.4)]);
      expect(nav.pendingSentences, ['Chair detected, 2.4 meters to your left.']);
      nav.commitAnnouncement();
      expect(nav.announcementChanged, isFalse);
    });

    test('an unchanged scene is not offered again', () {
      final List<DetectedObject> scene = [
        _obj('person', ObjectPosition.center, meters: 1.8),
        _obj('chair', ObjectPosition.left, meters: 2.4),
      ];
      nav.decide(_clearPath(), scene);
      expect(nav.announcementChanged, isTrue);
      nav.commitAnnouncement();

      for (int frame = 0; frame < 20; frame++) {
        nav.decide(_clearPath(), scene);
        expect(nav.announcementChanged, isFalse, reason: 'frame $frame');
        expect(nav.pendingSentences, isEmpty, reason: 'frame $frame');
      }
    });

    test('a meaningful move is offered, tiny wobble is not', () {
      nav.decide(_clearPath(), [_obj('person', ObjectPosition.left, meters: 3.0)]);
      nav.commitAnnouncement();

      nav.decide(_clearPath(), [_obj('person', ObjectPosition.left, meters: 2.9)]);
      expect(nav.announcementChanged, isFalse);

      nav.decide(_clearPath(), [_obj('person', ObjectPosition.center, meters: 1.5)]);
      expect(nav.announcementChanged, isTrue);
      expect(nav.pendingSentences, ['Person detected, 1.5 meters ahead.']);
    });

    test('the category filter applies to every announced object', () {
      nav.decide(
        _clearPath(),
        [
          _obj('chair', ObjectPosition.left, meters: 2.4),
          _obj('person', ObjectPosition.center, meters: 1.8),
        ],
        includeObject: (DetectedObject o) => o.className != 'person',
      );
      expect(nav.pendingSentences, ['Chair detected, 2.4 meters to your left.']);
    });

    test('reset drops the pending sentences so STOP can never speak them', () {
      nav.decide(_clearPath(), [_obj('chair', ObjectPosition.left, meters: 2.4)]);
      expect(nav.pendingSentences.length, 1);

      nav.reset();
      expect(nav.pendingSentences, isEmpty);
      expect(nav.announcementChanged, isFalse);
      expect(nav.lastSpokenMessage, isEmpty);
    });
  });
}