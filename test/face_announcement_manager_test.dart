import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/models/face_detection.dart';
import 'package:visionpath/models/object_position.dart';
import 'package:visionpath/services/face_announcement_manager.dart';

FaceOccurrence _occ(
  String id,
  String? name, {
  ObjectPosition position = ObjectPosition.center,
  double cx = 0.5,
  double cy = 0.4,
  double similarity = 0.95,
  bool unknown = false,
}) {
  return FaceOccurrence(
    identityKey: id,
    name: name,
    position: position,
    similarity: similarity,
    isUnknown: unknown,
    cx: cx,
    cy: cy,
  );
}

DateTime _now = DateTime(2026, 1, 1);

/// Advances 200ms and returns the current clock, simulating frame cadence.
DateTime _frame() {
  _now = _now.add(const Duration(milliseconds: 200));
  return _now;
}

void main() {
  setUp(() => _now = DateTime(2026, 1, 1));

  test('a single frame alone is never announced (needs temporal confirmation)',
      () {
    final mgr = FaceAnnouncementManager(confirmFrames: 3);
    final lines = mgr.update([_occ('1', 'Mother')], _now);
    expect(lines, isEmpty);
    mgr.reset();
    expect(mgr.update([_occ('1', 'Mother')], _frame()), isEmpty);
  });

  test('announces once after consistent frames, never repeats unchanged', () {
    final mgr = FaceAnnouncementManager(confirmFrames: 3);
    final spoken = <String>[];
    for (var i = 0; i < 12; i++) {
      spoken.addAll(mgr.update([_occ('1', 'Mother')], _frame()));
    }
    expect(spoken.length, 1);
    expect(spoken.first, 'Mother is directly ahead.');
  });

  test('identity change triggers a fresh announcement', () {
    final mgr = FaceAnnouncementManager(confirmFrames: 3);
    final spoken = <String>[];
    for (var i = 0; i < 3; i++) {
      spoken.addAll(mgr.update([_occ('1', 'Mother')], _frame()));
    }
    for (var i = 0; i < 3; i++) {
      spoken.addAll(mgr.update([_occ('2', 'Father')], _frame()));
    }
    expect(spoken.where((l) => l.contains('Mother')).length, 1);
    expect(spoken.where((l) => l.contains('Father')).length, 1);
  });

  test('position change re-announces', () {
    final mgr = FaceAnnouncementManager(confirmFrames: 3);
    final spoken = <String>[];
    for (var i = 0; i < 3; i++) {
      spoken.addAll(mgr.update([_occ('1', 'Mother')], _frame()));
    }
    expect(spoken.last, 'Mother is directly ahead.');
    for (var i = 0; i < 3; i++) {
      spoken.addAll(
        mgr.update(
          [_occ('1', 'Mother', position: ObjectPosition.left, cx: 0.12)],
          _frame(),
        ),
      );
    }
    expect(spoken.last, 'Mother is on your left.');
  });

  test('re-appearance after disappearance re-announces', () {
    final mgr = FaceAnnouncementManager(
      confirmFrames: 3,
      trackExpiry: const Duration(milliseconds: 1500),
    );
    final spoken = <String>[];
    for (var i = 0; i < 3; i++) {
      spoken.addAll(mgr.update([_occ('1', 'Mother')], _frame()));
    }
    // Disappear long enough for the track to expire.
    for (var i = 0; i < 10; i++) {
      spoken.addAll(mgr.update([], _frame()));
    }
    // Reappear.
    for (var i = 0; i < 3; i++) {
      spoken.addAll(mgr.update([_occ('1', 'Mother')], _frame()));
    }
    expect(spoken.where((l) => l.contains('Mother')).length,
        greaterThanOrEqualTo(2));
  });

  test('unknown announcements are gated', () {
    final off = FaceAnnouncementManager(
      confirmFrames: 2,
      unknownAnnouncements: false,
    );
    final silent = <String>[];
    for (var i = 0; i < 6; i++) {
      silent.addAll(
        off.update([_occ('UNKNOWN', null, unknown: true)], _frame()),
      );
    }
    expect(silent, isEmpty);

    final on = FaceAnnouncementManager(
      confirmFrames: 2,
      unknownAnnouncements: true,
    );
    final spoken = <String>[];
    for (var i = 0; i < 3; i++) {
      spoken.addAll(
        on.update([_occ('UNKNOWN', null, unknown: true)], _frame()),
      );
    }
    expect(spoken, isNotEmpty);
    expect(spoken.first, 'Unknown person is directly ahead.');
  });

  test('multiple known people respect the per-frame announcement budget', () {
    final mgr = FaceAnnouncementManager(
      confirmFrames: 2,
      maxAnnouncementsPerFrame: 2,
    );
    var perFrameMax = 0;
    final spoken = <String>[];
    for (var i = 0; i < 3; i++) {
      final lines = mgr.update(
        [
          _occ('1', 'Mother'),
          _occ('2', 'Father', cx: 0.8, position: ObjectPosition.right),
          _occ('3', 'Friend', cx: 0.2, position: ObjectPosition.left),
        ],
        _frame(),
      );
      if (lines.length > perFrameMax) perFrameMax = lines.length;
      spoken.addAll(lines);
    }
    expect(perFrameMax, lessThanOrEqualTo(2));
    expect(spoken, isNotEmpty);
  });
}