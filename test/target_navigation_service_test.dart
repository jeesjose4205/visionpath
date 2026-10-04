import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/models/detected_object.dart';
import 'package:visionpath/models/navigation_decision.dart';
import 'package:visionpath/models/object_position.dart';
import 'package:visionpath/models/proximity_level.dart';
import 'package:visionpath/models/target_search.dart';
import 'package:visionpath/services/object_vocabulary.dart';
import 'package:visionpath/services/target_navigation_service.dart';

DetectedObject _obj(
  String className, {
  ObjectPosition? position,
  double? meters,
  ProximityLevel? proximity,
  double area = 0.05,
}) {
  final double side = area <= 0 ? 0.01 : area;
  return DetectedObject(
    className: className,
    confidence: 0.9,
    boundingBox: Rect.fromLTWH(0.4, 0.4, side, side),
    position: position,
    proximity: proximity,
    distanceMeters: meters,
    distanceConfidence: meters == null ? null : 0.9,
  );
}

void main() {
  group('target command parsing', () {
    test('"find a chair" starts a chair search', () {
      final TargetCommand c = TargetNavigationService.parseCommand('Find a chair');
      expect(c.kind, TargetCommandKind.start);
      expect(c.className, 'chair');
      expect(c.classes, contains('chair'));
    });

    test('normalizes articles, plurals and case', () {
      for (final String phrase in [
        'find the chairs',
        'FIND A CHAIR!',
        'can you please find me a chair',
        'where is the chair?',
      ]) {
        final TargetCommand c = TargetNavigationService.parseCommand(phrase);
        expect(c.kind, TargetCommandKind.start, reason: phrase);
        expect(c.className, 'chair', reason: phrase);
      }
    });

    test('resolves everyday words onto the YOLO class', () {
      expect(
        TargetNavigationService.parseCommand('find the sofa').className,
        'couch',
      );
      expect(
        TargetNavigationService.parseCommand('where is the fridge?').className,
        'refrigerator',
      );
      expect(
        TargetNavigationService.parseCommand('find my phone').className,
        'cell phone',
      );
      expect(
        TargetNavigationService.parseCommand('go to the table').className,
        'dining table',
      );
      expect(
        TargetNavigationService.parseCommand('find a television').className,
        'tv',
      );
    });

    test('multi-word classes never collapse to their first word', () {
      final TargetCommand hotdog =
          TargetNavigationService.parseCommand('find a hot dog');
      expect(hotdog.className, 'hot dog');
      expect(hotdog.classes, isNot(contains('dog')));

      final TargetCommand plant =
          TargetNavigationService.parseCommand('find the potted plant');
      expect(plant.className, 'potted plant');
    });

    test('an object the model cannot see is reported as unsupported', () {
      for (final String phrase in [
        'find the door',
        'find an elevator',
        'locate the stairs',
        'where is the window?',
      ]) {
        final TargetCommand c = TargetNavigationService.parseCommand(phrase);
        expect(c.kind, TargetCommandKind.unsupported, reason: phrase);
        expect(c.classes, isEmpty, reason: phrase);
      }
    });

    test('a general question is left to the assistant', () {
      for (final String phrase in [
        'What can you do?',
        'Explain machine learning',
        'where is it',
        '',
      ]) {
        expect(
          TargetNavigationService.parseCommand(phrase).kind,
          TargetCommandKind.none,
          reason: phrase,
        );
      }
    });

    test('stop utterances end the search', () {
      for (final String phrase in [
        'stop searching',
        'Stop looking for the chair',
        'cancel the search',
        'never mind',
        'forget it',
        // Bare and near-bare cancels, which the assistant also treats as
        // interruption words.
        'stop',
        'Stop.',
        'cancel',
        'Cancel.',
        'stop finding',
        'Stop finding.',
        'cancel navigation to the chair',
      ]) {
        expect(
          TargetNavigationService.parseCommand(phrase).kind,
          TargetCommandKind.stop,
          reason: phrase,
        );
      }
    });

    test('a bare stop word never reads as an object request', () {
      // "Stop" must cancel, not be mined for a target noun.
      expect(
        TargetNavigationService.parseCommand('stop').phrase,
        isEmpty,
      );
      // A longer sentence that merely contains a stop word is left alone, so
      // an ordinary request is not swallowed by the cancel patterns.
      for (final String phrase in [
        'what is around me',
        'repeat that',
        'what is that',
      ]) {
        expect(
          TargetNavigationService.parseCommand(phrase).kind,
          TargetCommandKind.none,
          reason: phrase,
        );
      }
    });
  });

  group('vocabulary', () {
    test('the class list is the app COCO set: complete and duplicate free', () {
      // 76 is the subset of the COCO 80 the app talks about; a change here
      // means the model, the assistant and the target navigator disagree.
      expect(ObjectVocabulary.supportedClasses.length, 76);
      expect(
        ObjectVocabulary.supportedClasses.toSet().length,
        ObjectVocabulary.supportedClasses.length,
      );
      expect(ObjectVocabulary.isSupported('dining table'), isTrue);
      expect(ObjectVocabulary.isSupported('door'), isFalse);
    });

    test('a qualifier is dropped but the real object is kept', () {
      // "the nearest empty chair" still has to resolve to the chair the model
      // can actually see; the modifier is not a class of its own.
      expect(
        TargetNavigationService.parseCommand('Find the nearest empty chair')
            .className,
        'chair',
      );
      expect(
        TargetNavigationService.parseCommand('find a dining table').className,
        'dining table',
      );
    });

    test('arbitrary model classes work, not just the examples', () {
      for (final String phrase in [
        'find a person',
        'find a bottle',
        'find a car',
        'find a backpack',
        'find a bench',
        'find a laptop',
        'navigate to the chair',
        'where is a chair',
        'search for a chair',
        'take me to a chair',
      ]) {
        expect(
          TargetNavigationService.parseCommand(phrase).isStart,
          isTrue,
          reason: phrase,
        );
      }
    });
  });

  group('target navigation service', () {
    late DateTime now;
    late TargetNavigationService service;

    setUp(() {
      now = DateTime(2026, 1, 1);
      service = TargetNavigationService(clock: () => now);
      service.setPipelineActive(true, runId: 7);
    });

    void frame(
      List<DetectedObject> detections, {
      NavigationDecision decision = NavigationDecision.forward,
      int? runId,
    }) {
      service.updateFrame(
        detections: detections,
        decision: decision,
        runId: runId,
      );
    }

    test('asks for navigation to be started when it is not running', () {
      final TargetNavigationService idle = TargetNavigationService();
      expect(idle.handleCommand('find a chair'), isTrue);
      expect(idle.isActive, isFalse);
      expect(
        idle.drainMessages().single,
        startsWith('Start navigation first'),
      );
    });

    test('a request starts a session and acknowledges it', () {
      expect(service.handleCommand('find a chair'), isTrue);
      expect(service.isActive, isTrue);
      expect(service.phase, TargetSearchPhase.searching);
      expect(service.targetName, 'Chair');
      expect(service.targetClasses, {'chair'});
      expect(service.sessionId, 1);
      expect(
        service.drainMessages().single,
        'Searching for a Chair.',
      );
      expect(service.drainMessages(), isEmpty);
    });

    test('a non-target request is not consumed', () {
      expect(service.handleCommand('tell me a joke'), isFalse);
    });

    test('confirms the target only after two frames', () {
      service.handleCommand('find a chair');
      service.drainMessages();

      frame([_obj('chair', position: ObjectPosition.center, meters: 2.4)]);
      expect(service.state.confirmed, isFalse);
      expect(service.drainMessages(), isEmpty);

      frame([_obj('chair', position: ObjectPosition.center, meters: 2.4)]);
      expect(service.state.confirmed, isTrue);
      expect(service.phase, TargetSearchPhase.tracking);
      expect(
        service.drainMessages().single,
        'Chair detected, 2.4 meters ahead.',
      );
    });

    test('flicker on a single frame never confirms a target', () {
      service.handleCommand('find a chair');
      service.drainMessages();

      frame([_obj('chair', meters: 2.4)]);
      frame([_obj('person', meters: 1.0)]);
      frame([_obj('chair', meters: 2.4)]);
      expect(service.state.confirmed, isFalse);
      expect(service.drainMessages(), isEmpty);
    });

    test('a target without a metric distance is still guided', () {
      service.handleCommand('find a chair');
      service.drainMessages();
      frame([_obj('chair', position: ObjectPosition.left)]);
      frame([_obj('chair', position: ObjectPosition.left)]);
      expect(
        service.drainMessages().single,
        'Chair detected, to your left.',
      );
    });

    test('follows the nearest target when several are visible', () {
      service.handleCommand('find a chair');
      service.drainMessages();
      frame([
        _obj('chair', position: ObjectPosition.left, meters: 4.0),
        _obj('chair', position: ObjectPosition.center, meters: 1.8),
      ]);
      frame([
        _obj('chair', position: ObjectPosition.left, meters: 4.0),
        _obj('chair', position: ObjectPosition.center, meters: 1.8),
      ]);
      expect(
        service.drainMessages().single,
        'Chair detected, 1.8 meters ahead.',
      );
    });

    test('without depth the largest box is the target', () {
      service.handleCommand('find a chair');
      service.drainMessages();
      frame([
        _obj('chair', position: ObjectPosition.right, area: 0.01),
        _obj('chair', position: ObjectPosition.center, area: 0.20),
      ]);
      frame([
        _obj('chair', position: ObjectPosition.right, area: 0.01),
        _obj('chair', position: ObjectPosition.center, area: 0.20),
      ]);
      expect(service.state.position, ObjectPosition.center);
    });

    test('announces a position change, then respects the cooldown', () {
      service.handleCommand('find a chair');
      service.drainMessages();
      frame([_obj('chair', position: ObjectPosition.center, meters: 2.0)]);
      frame([_obj('chair', position: ObjectPosition.center, meters: 2.0)]);
      service.drainMessages();

      // New side: the first guidance after "Found" is news, not a repeat.
      frame([_obj('chair', position: ObjectPosition.right, meters: 2.0)]);
      expect(
        service.drainMessages().single,
        'Move slightly right. Chair is 2.0 meters to your right.',
      );

      // Unchanged: nothing to say.
      frame([_obj('chair', position: ObjectPosition.right, meters: 2.0)]);
      expect(service.drainMessages(), isEmpty);

      // Jittering sides inside the cooldown is held back, not spoken twice.
      frame([_obj('chair', position: ObjectPosition.left, meters: 2.0)]);
      expect(service.drainMessages(), isEmpty);

      // Once the cooldown has passed the next change is announced, and the
      // "close" band gets its own wording.
      now = now.add(const Duration(milliseconds: 4000));
      frame([_obj('chair', position: ObjectPosition.left, meters: 1.2)]);
      expect(
        service.drainMessages().single,
        'Chair is 1.2 meters to your left. Slow down.',
      );
    });

    test('arrival needs 0.8 m or closer, not merely "under a metre"', () {
      service.handleCommand('find a chair');
      service.drainMessages();
      frame([_obj('chair', position: ObjectPosition.center, meters: 2.0)]);
      frame([_obj('chair', position: ObjectPosition.center, meters: 2.0)]);
      service.drainMessages();

      // 0.9 m is inside the old one-metre rule but is not arrived yet.
      now = now.add(const Duration(milliseconds: 4000));
      frame([_obj('chair', position: ObjectPosition.center, meters: 0.9)]);
      expect(service.phase, TargetSearchPhase.tracking);
      expect(service.drainMessages(), isNotEmpty);

      // 0.8 m is the threshold and does count.
      now = now.add(const Duration(milliseconds: 4000));
      frame([_obj('chair', position: ObjectPosition.center, meters: 0.8)]);
      expect(service.drainMessages().single, 'You have reached the Chair.');
      expect(service.phase, TargetSearchPhase.reached);
      expect(
        TargetNavigationService.reachedDistanceMeters,
        0.8,
      );
    });

    test('a distance is only re-spoken once it moved 0.3 m', () {
      service.handleCommand('find a chair');
      service.drainMessages();
      frame([_obj('chair', position: ObjectPosition.center, meters: 3.0)]);
      frame([_obj('chair', position: ObjectPosition.center, meters: 3.0)]);
      service.drainMessages();

      // Establish the spoken baseline.
      frame([_obj('chair', position: ObjectPosition.center, meters: 3.0)]);
      expect(service.drainMessages().single, 'Continue straight. Chair is 3.0 meters ahead.');

      // 0.2 m of drift, past the cooldown, is still not worth a sentence.
      now = now.add(const Duration(milliseconds: 4000));
      frame([_obj('chair', position: ObjectPosition.center, meters: 3.2)]);
      expect(service.drainMessages(), isEmpty);

      // 0.3 m is.
      now = now.add(const Duration(milliseconds: 4000));
      frame([_obj('chair', position: ObjectPosition.center, meters: 3.3)]);
      expect(
        service.drainMessages().single,
        'Continue straight. Chair is 3.3 meters ahead.',
      );
      expect(
        TargetNavigationService.distanceChangeThresholdMeters,
        0.3,
      );
    });

    test('crossing a distance band alone does not re-speak the target', () {
      service.handleCommand('find a chair');
      service.drainMessages();
      frame([_obj('chair', position: ObjectPosition.center, meters: 3.0)]);
      frame([_obj('chair', position: ObjectPosition.center, meters: 3.0)]);
      service.drainMessages();
      frame([_obj('chair', position: ObjectPosition.center, meters: 3.0)]);
      service.drainMessages();

      // 3.0 -> 3.2 leaves the "medium" band, but it is under the 0.3 m rule,
      // so the band change alone must not produce a sentence.
      now = now.add(const Duration(milliseconds: 4000));
      frame([_obj('chair', position: ObjectPosition.center, meters: 3.2)]);
      expect(service.drainMessages(), isEmpty);
    });

    test('without depth the proximity band still guides the user', () {
      service.handleCommand('find a chair');
      service.drainMessages();
      frame([
        _obj('chair',
            position: ObjectPosition.center, proximity: ProximityLevel.far),
      ]);
      frame([
        _obj('chair',
            position: ObjectPosition.center, proximity: ProximityLevel.far),
      ]);
      service.drainMessages();
      frame([
        _obj('chair',
            position: ObjectPosition.center, proximity: ProximityLevel.far),
      ]);
      expect(service.drainMessages().single, 'Continue straight. Chair is ahead.');

      // Far -> near crosses a band, and there is no metric distance to
      // compare, so the change is worth announcing. Only "very near" earns the
      // slow-down warning, so the wording here stays a plain approach line.
      now = now.add(const Duration(milliseconds: 4000));
      frame([
        _obj('chair',
            position: ObjectPosition.center, proximity: ProximityLevel.near),
      ]);
      expect(service.drainMessages(), hasLength(1));

      // "Very near" is arrival, not a warning: the session ends instead.
      now = now.add(const Duration(milliseconds: 4000));
      frame([
        _obj('chair',
            position: ObjectPosition.center,
            proximity: ProximityLevel.veryNear),
      ]);
      expect(
        service.drainMessages().single,
        'You have reached the Chair.',
      );

      // Same band again is not news.
      now = now.add(const Duration(milliseconds: 4000));
      frame([
        _obj('chair',
            position: ObjectPosition.center, proximity: ProximityLevel.near),
      ]);
      expect(service.drainMessages(), isEmpty);
    });

    test('the lost-target grace sits inside the one to two second window', () {
      // Six sampled frames at the 5 FPS pipeline rate is about 1.2 s, which is
      // the shortest grace a user still reads as "hold on" rather than "gone".
      expect(
        TargetNavigationService.lostGracePeriod,
        greaterThanOrEqualTo(const Duration(seconds: 1)),
      );
      expect(
        TargetNavigationService.lostGracePeriod,
        lessThanOrEqualTo(const Duration(seconds: 2)),
      );
      expect(TargetNavigationService.lostGraceFrames, 6);
    });

    test('announces arrival by distance and by proximity', () {
      service.handleCommand('find a chair');
      service.drainMessages();
      frame([_obj('chair', position: ObjectPosition.center, meters: 2.0)]);
      frame([_obj('chair', position: ObjectPosition.center, meters: 2.0)]);
      service.drainMessages();

      frame([_obj('chair', position: ObjectPosition.center, meters: 0.8)]);
      expect(service.drainMessages().single, 'You have reached the Chair.');
      expect(service.phase, TargetSearchPhase.reached);

      // The session ends itself: normal navigation takes over again.
      frame([_obj('chair', position: ObjectPosition.center, meters: 0.8)]);
      expect(service.phase, TargetSearchPhase.idle);
      expect(service.isActive, isFalse);
      expect(service.drainMessages(), isEmpty);
    });

    test('a very close box counts as arrival when depth is unavailable', () {
      service.handleCommand('find a chair');
      service.drainMessages();
      frame([
        _obj('chair', position: ObjectPosition.center, proximity: ProximityLevel.far),
      ]);
      frame([
        _obj('chair', position: ObjectPosition.center, proximity: ProximityLevel.far),
      ]);
      service.drainMessages();

      frame([
        _obj('chair', position: ObjectPosition.center, proximity: ProximityLevel.veryNear),
      ]);
      expect(service.drainMessages().single, 'You have reached the Chair.');
    });

    test('keeps the target through a short gap, then reports losing it', () {
      service.handleCommand('find a chair');
      service.drainMessages();
      frame([_obj('chair', position: ObjectPosition.center, meters: 2.0)]);
      frame([_obj('chair', position: ObjectPosition.center, meters: 2.0)]);
      service.drainMessages();

      for (int i = 0; i < TargetNavigationService.lostGraceFrames; i++) {
        frame([]);
        expect(service.isActive, isTrue, reason: 'grace frame $i');
      }
      expect(service.drainMessages(), isEmpty);
      expect(service.state.confirmed, isTrue);

      frame([]);
      expect(
        service.drainMessages().single,
        "I can't see the Chair right now. Please turn slowly.",
      );
      expect(service.phase, TargetSearchPhase.searching);
      expect(service.state.confirmed, isFalse);
    });

    test('an obstacle takes the floor and the target message waits', () {
      service.handleCommand('find a chair');
      service.drainMessages();

      frame(
        [_obj('chair', position: ObjectPosition.center, meters: 2.4)],
        decision: NavigationDecision.stop,
      );
      frame(
        [_obj('chair', position: ObjectPosition.center, meters: 2.4)],
        decision: NavigationDecision.slow,
      );
      expect(service.state.confirmed, isTrue);
      expect(service.drainMessages(), isEmpty);

      frame([_obj('chair', position: ObjectPosition.center, meters: 2.4)]);
      expect(
        service.drainMessages().single,
        'Chair detected, 2.4 meters ahead.',
      );
    });

    test('stop searching ends the session and confirms it', () {
      service.handleCommand('find a chair');
      service.drainMessages();
      expect(service.handleCommand('stop searching'), isTrue);
      expect(service.isActive, isFalse);
      expect(service.targetName, isEmpty);
      expect(service.drainMessages().single, 'Stopped looking for the Chair.');

      // Frames after the stop can never speak for the old target.
      frame([_obj('chair', position: ObjectPosition.center, meters: 2.0)]);
      frame([_obj('chair', position: ObjectPosition.center, meters: 2.0)]);
      expect(service.drainMessages(), isEmpty);
    });

    test('stopping when nothing is running says so', () {
      expect(service.handleCommand('stop searching'), isTrue);
      expect(
        service.drainMessages().single,
        'There is no target search running.',
      );
    });

    test('an unsupported request never disturbs a running search', () {
      service.handleCommand('find a chair');
      service.drainMessages();

      expect(service.handleCommand('find the door'), isTrue);
      expect(
        service.drainMessages().single,
        "I can't identify that object with the current camera.",
      );
      expect(service.targetName, 'Chair');
      expect(service.isActive, isTrue);
    });

    test('frames from an older run are ignored', () {
      service.handleCommand('find a chair');
      service.drainMessages();
      frame(
        [_obj('chair', meters: 2.0)],
        runId: 3,
      );
      expect(service.state.confirmed, isFalse);
      expect(service.drainMessages(), isEmpty);
    });

    test('stopping navigation ends the search silently', () {
      service.handleCommand('find a chair');
      service.drainMessages();
      service.setPipelineActive(false);
      expect(service.isActive, isFalse);
      expect(service.targetName, isEmpty);
      expect(service.drainMessages(), isEmpty);
    });

    test('notifies listeners when the session changes', () {
      int notifications = 0;
      service.addListener(() => notifications++);
      service.handleCommand('find a chair');
      service.drainMessages();
      frame([_obj('chair', meters: 2.0)]);
      frame([_obj('chair', meters: 2.0)]);
      expect(notifications, greaterThanOrEqualTo(3));
    });

    test('the live session reports the mode of its current phase', () {
      service.handleCommand('find a chair');
      expect(service.state.mode, NavigationMode.targetSearch);

      frame([_obj('chair', meters: 2.0)]);
      frame([_obj('chair', meters: 2.0)]);
      expect(service.state.mode, NavigationMode.targetApproach);

      frame([_obj('chair', meters: 0.8)]);
      expect(service.state.mode, NavigationMode.targetReached);

      // Reached is reported once, then normal navigation owns the run again.
      frame([_obj('chair', meters: 0.8)]);
      expect(service.state.mode, NavigationMode.normal);
    });

    test('a bare "cancel" ends an active search and normal navigation resumes',
        () {
      service.handleCommand('find a chair');
      frame([_obj('chair', meters: 2.0)]);
      frame([_obj('chair', meters: 2.0)]);
      expect(service.isActive, isTrue);
      service.drainMessages();

      expect(service.handleCommand('cancel'), isTrue);
      expect(service.isActive, isFalse);
      expect(service.targetName, isEmpty);
      expect(service.targetClasses, isEmpty);
      expect(service.state.mode, NavigationMode.normal);
      expect(
        service.drainMessages().single,
        'Stopped looking for the Chair.',
      );

      // The next frame is ordinary navigation again: no target lines at all.
      frame([_obj('chair', meters: 2.0)]);
      frame([_obj('chair', meters: 2.0)]);
      expect(service.drainMessages(), isEmpty);
    });

    test('cancelling when nothing is being tracked stays polite', () {
      expect(service.handleCommand('cancel'), isTrue);
      expect(
        service.drainMessages().single,
        'There is no target search running.',
      );
    });

    test('a new command replaces the running target without a restart', () {
      service.handleCommand('find a chair');
      frame([_obj('chair', meters: 2.0)]);
      frame([_obj('chair', meters: 2.0)]);
      service.drainMessages();
      expect(service.targetName, 'Chair');

      // No pipeline restart, no screen change: just a different target.
      expect(service.handleCommand('find a bottle'), isTrue);
      expect(service.targetName, 'Bottle');
      expect(service.targetClasses, {'bottle'});
      expect(service.phase, TargetSearchPhase.searching);
      expect(service.state.confirmed, isFalse);
      expect(
        service.drainMessages().single,
        'Searching for a Bottle.',
      );

      // The old target must never speak again.
      frame([_obj('chair', meters: 2.0)]);
      frame([_obj('chair', meters: 2.0)]);
      expect(service.drainMessages(), isEmpty);

      // The new one takes over from the very next frames.
      frame([_obj('bottle', meters: 2.5)]);
      frame([_obj('bottle', meters: 2.5)]);
      expect(service.drainMessages(), isNotEmpty);
    });
  });

  group('target search state', () {
    test('each phase maps onto the matching navigation mode', () {
      // Normal navigation is the default and is only left behind once a target
      // is actually requested.
      expect(TargetSearchPhase.idle.mode, NavigationMode.normal);
      expect(TargetSearchPhase.searching.mode, NavigationMode.targetSearch);
      expect(TargetSearchPhase.tracking.mode, NavigationMode.targetApproach);
      expect(TargetSearchPhase.reached.mode, NavigationMode.targetReached);

      const TargetSearchState idle = TargetSearchState(
        phase: TargetSearchPhase.idle,
        targetName: '',
      );
      expect(idle.mode, NavigationMode.normal);
    });

    test('status text reflects the phase', () {
      const TargetSearchState searching = TargetSearchState(
        phase: TargetSearchPhase.searching,
        targetName: 'Chair',
      );
      expect(searching.statusText, 'Searching…');
      expect(searching.isActive, isTrue);

      const TargetSearchState tracking = TargetSearchState(
        phase: TargetSearchPhase.tracking,
        targetName: 'Chair',
        confirmed: true,
        distanceMeters: 2.4,
        position: ObjectPosition.center,
      );
      expect(tracking.statusText, '2.4 m • Ahead');

      const TargetSearchState noMetrics = TargetSearchState(
        phase: TargetSearchPhase.tracking,
        targetName: 'Chair',
        confirmed: true,
        position: ObjectPosition.right,
      );
      expect(noMetrics.statusText, 'On your right');
    });

    test('idle state is inactive and silent', () {
      const TargetSearchState idle =
          TargetSearchState(phase: TargetSearchPhase.idle, targetName: '');
      expect(idle.isActive, isFalse);
      expect(idle.statusText, isEmpty);
    });
  });
}
