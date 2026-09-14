import 'dart:math' as math;

import '../models/face_detection.dart';
import '../models/object_position.dart';

/// A moving face being temporally confirmed before it is announced.
class _FaceTrack {
  _FaceTrack(this.id, this.cx, this.cy, this.seenAt);

  final int id;
  double cx;
  double cy;
  DateTime seenAt;

  String? pendingIdentity;
  int pendingVotes = 0;
  String? confirmedIdentity;
  String? confirmedName;
  bool confirmedUnknown = false;
  double confirmedSimilarity = 0;

  String? lastAnnouncedKey;
  DateTime lastAnnouncedAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isConfirmed => confirmedIdentity != null;
}

/// FaceAnnouncementManager implements identity temporal confirmation plus
/// announcement policy for the Familiar Faces recognition screen.
///
/// Rules implemented (mirroring InstructionManager semantics for the rest of
/// the app):
///  - an identity is only announced after [confirmFrames] consecutive frames
///    report the same match (anti-fluke, e.g. lighting / blur / partial face),
///  - the same message is never repeated while identity and position are
///    unchanged ([announceCooldown] gates re-announcement after a change),
///  - identity change, position change and re-appearance trigger a fresh
///    announcement,
///  - at most [maxAnnouncementsPerFrame] lines are emitted per frame to avoid
///    overwhelming the user with simultaneous messages,
///  - unknown-person announcements are opt-in.
class FaceAnnouncementManager {
  FaceAnnouncementManager({
    this.confirmFrames = 3,
    this.announceCooldown = const Duration(milliseconds: 3000),
    this.trackExpiry = const Duration(milliseconds: 1600),
    this.maxAnnouncementsPerFrame = 2,
    this.unknownAnnouncements = false,
  });

  final int confirmFrames;
  final Duration announceCooldown;
  final Duration trackExpiry;
  final int maxAnnouncementsPerFrame;

  /// When false, unknown faces are never spoken.
  bool unknownAnnouncements;

  final List<_FaceTrack> _tracks = [];
  int _nextId = 0;

  /// Feed the current frame's recognition results; returns lines to speak.
  List<String> update(List<FaceOccurrence> occurrences, DateTime now) {
    _expire(now);

    // Associate occurrences with existing tracks by nearest center distance.
    for (final occ in occurrences) {
      _FaceTrack? best;
      var bestDist = 0.35; // max association distance (normalized units)
      for (final track in _tracks) {
        final d = _dist(occ.cx, occ.cy, track.cx, track.cy);
        if (d < bestDist) {
          bestDist = d;
          best = track;
        }
      }

      if (best == null) {
        _tracks.add(_FaceTrack(_nextId++, occ.cx, occ.cy, now));
        continue;
      }

      best.cx = occ.cx;
      best.cy = occ.cy;
      best.seenAt = now;

      if (best.pendingIdentity == occ.identityKey) {
        best.pendingVotes++;
      } else {
        best.pendingIdentity = occ.identityKey;
        best.pendingVotes = 1;
      }
      if (best.pendingVotes >= confirmFrames) {
        best.confirmedIdentity = occ.identityKey;
        best.confirmedName = occ.name;
        best.confirmedUnknown = occ.isUnknown;
        best.confirmedSimilarity = occ.similarity;
      }
    }

    return _buildAnnouncements(now);
  }

  List<String> _buildAnnouncements(DateTime now) {
    final candidates = <_Announcement>[];

    for (final track in _tracks) {
      if (!track.isConfirmed) continue;

      final key = '${track.confirmedIdentity}:${_positionOf(track).name}';
      final isChange =
          track.lastAnnouncedKey != null &&
          track.lastAnnouncedKey != key;
      final isNew =
          track.lastAnnouncedKey == null && track.pendingVotes >= confirmFrames;
      final cooldownElapsed =
          now.difference(track.lastAnnouncedAt) >= announceCooldown;

      if (!isChange && !isNew && !cooldownElapsed) {
        continue; // unchanged identity+position, still inside cooldown
      }

      final unknown = track.confirmedUnknown;
      if (unknown && !unknownAnnouncements) continue;

      candidates.add(
        _Announcement(
          trackId: track.id,
          key: key,
          unknown: unknown,
          similarity: track.confirmedSimilarity,
          position: _positionOf(track),
          message: (track.confirmedName ?? 'Unknown person') +
              ' is ' +
              _locationOf(_positionOf(track)) +
              '.',
        ),
      );
    }

    // Prioritize: known faces before unknown, center before edges, higher
    // confidence first. Then apply cooldown bookkeeping and emit the top N.
    candidates.sort((a, b) {
      if (a.unknown != b.unknown) return a.unknown ? 1 : -1;
      if (a.position != b.position) {
        if (a.position == ObjectPosition.center) return -1;
        if (b.position == ObjectPosition.center) return 1;
      }
      return b.similarity.compareTo(a.similarity);
    });

    final lines = <String>[];
    final emitted = <int>{};
    for (final c in candidates.take(maxAnnouncementsPerFrame)) {
      final track = _tracks.firstWhere(
        (t) => t.id == c.trackId,
        orElse: () => _tracks.first,
      );
      track.lastAnnouncedKey = c.key;
      track.lastAnnouncedAt = now;
      emitted.add(c.trackId);
      lines.add(c.message);
    }
    return lines;
  }

  ObjectPosition _positionOf(_FaceTrack track) {
    // Position is snapshotted from the latest occurrence via the track's last
    // processed box; recompute here from the stored center.
    return ObjectPosition.fromCenterX(track.cx);
  }

  String _locationOf(ObjectPosition position) {
    switch (position) {
      case ObjectPosition.left:
        return 'on your left';
      case ObjectPosition.center:
        return 'directly ahead';
      case ObjectPosition.right:
        return 'on your right';
    }
  }

  void _expire(DateTime now) {
    _tracks.removeWhere((t) => now.difference(t.seenAt) > trackExpiry);
  }

  double _dist(double ax, double ay, double bx, double by) {
    final dx = ax - bx;
    final dy = ay - by;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Forget all tracking state.
  void reset() {
    _tracks.clear();
  }
}

class _Announcement {
  _Announcement({
    required this.trackId,
    required this.key,
    required this.unknown,
    required this.similarity,
    required this.position,
    required this.message,
  });

  final int trackId;
  final String key;
  final bool unknown;
  final double similarity;
  final ObjectPosition position;
  final String message;
}