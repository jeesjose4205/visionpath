import 'package:flutter/painting.dart';

import '../models/detected_object.dart';
import '../models/object_position.dart';
import '../models/proximity_level.dart';

/// One object inside a combined announcement, with everything the sentence
/// says about it.
class SceneSlot {
  SceneSlot({
    required this.label,
    required this.className,
    required this.position,
    required this.meters,
  });

  /// Human-readable class name as it is spoken ("Chair").
  final String label;

  /// Lower-case class key used for deduplication and change detection.
  final String className;

  final ObjectPosition position;

  /// Smoothed distance, or null when depth has no valid reading.
  final double? meters;

  /// Identity of this slot: one physical object is one class on one side.
  String get key => '$className|${position.label}';
}

/// The sentences produced for one analysed frame.
///
/// [sentences] holds one COMPLETE sentence per object that needs to be heard,
/// already ordered by importance, so the caller can queue them one by one.
/// [slots] is the FULL current scene state, including objects that did not
/// change — that is what gets remembered on commit, so an object the user has
/// already heard is never announced again.
class SceneAnnouncement {
  const SceneAnnouncement({
    required this.sentences,
    required this.slots,
    required this.members,
  });

  /// One ready-to-speak sentence per changed object, e.g.
  /// ["Person detected, 1.8 meters ahead.",
  ///  "Chair detected, 2.4 meters to your left."]
  final List<String> sentences;

  /// Every object currently in the spoken scene, in priority order.
  final List<SceneSlot> slots;

  /// The detections [sentences] are about, in the same order.
  final List<DetectedObject> members;

  /// Scene signature: class + side + distance for each spoken object. This is
  /// the state remembered by [SceneAnnouncer.commit] and used for logging.
  ///
  /// Change detection does NOT compare signatures: it compares real distances
  /// so a quantized band boundary can never fake a change.
  String get signature => slots
      .map((SceneSlot s) => '${s.key}|${s.meters?.toStringAsFixed(2) ?? 'na'}')
      .join('|');
}

/// SceneAnnouncer turns the detections of one frame into complete sentences,
/// one per relevant object, each naming the object and its own distance.
///
/// It is a pure helper driven by [NavigationService] — it owns no camera, no
/// model, no voice and no widgets. Everything it reports comes from the real
/// detections the pipeline already produced:
///
///   * **dedup** – the same class detected twice in one frame (overlapping
///     boxes) is one object, never two,
///   * **tracking** – detections are associated across frames by class plus
///     box overlap (IoU) and side, so one physical object keeps one identity,
///   * **smoothing** – each object's spoken distance is an exponential moving
///     average of its own measurements, so 2.4/2.3/2.4/2.5 m is spoken once as
///     2.4 m,
///   * **change detection** – a sentence is produced ONLY for an object that
///     newly appeared, disappeared, changed side, or moved at least
///     [DISTANCE_CHANGE_THRESHOLD] metres from what was last announced,
///   * **ordering** – the object blocking the path first, then collision risk,
///     then nearest, then directly ahead, then left/right,
///   * **restraint** – at most [maxAnnouncedObjects] objects per announcement,
///     and background structures are never spoken.
class SceneAnnouncer {
  /// Maximum number of objects described at once. More than this and the
  /// utterance stops being useful to listen to.
  static const int maxAnnouncedObjects = 3;

  /// Metres an object must travel before it is worth speaking again.
  ///
  /// Below this the depth sensor is only wobbling (2.10 m vs 2.08 m), and
  /// re-announcing it would be noise. Adjust here if the camera proves noisier
  /// or steadier than expected.
  static const double DISTANCE_CHANGE_THRESHOLD = 0.3;

  /// Weight of the newest measurement in the smoothed distance.
  static const double smoothingAlpha = 0.35;

  /// Box overlap required to treat two frames as the same object.
  static const double iouMatchThreshold = 0.3;

  /// Frames a track survives without a matching detection (~3 s at 5 FPS) so a
  /// brief occlusion does not destroy the object's history.
  static const int trackLostGrace = 15;

  /// Class label used by the depth pipeline for an unidentified obstacle.
  static const String ghostClass = 'obstacle';

  /// Structural classes that describe the room, not something to walk into.
  /// They stay in the camera overlay but are never spoken.
  static const Set<String> backgroundClasses = <String>{
    'wall',
    'floor',
    'ceiling',
    'ground',
  };

  final List<_Track> _tracks = <_Track>[];

  /// What the user was last told, per object slot. This — not the previous
  /// frame — is the baseline for both "is this new?" and "is it approaching?".
  final Map<String, SceneSlot> _announced = <String, SceneSlot>{};

  /// Announcement composed for the most recent frame.
  SceneAnnouncement? _pending;

  /// True once the caller took responsibility for [_pending] (queued it).
  bool _pendingCommitted = false;

  /// True when the current frame contains something meaningfully different
  /// from the last announced state. A caller that did not queue yet keeps
  /// seeing `true`, so the sentences are still queued as soon as possible.
  bool get hasChange {
    final SceneAnnouncement? pending = _pending;
    if (pending == null || _pendingCommitted) return false;
    return pending.sentences.isNotEmpty;
  }

  /// The announcement composed for the most recent frame, if any.
  SceneAnnouncement? get pending => _pending;

  /// One complete sentence per object that needs to be spoken right now.
  List<String> get pendingSentences =>
      _pending?.sentences ?? const <String>[];

  /// Mark the current state as announced.
  ///
  /// Call this once the sentences have been handed to the speech queue: from
  /// that point the queue owns delivery, so the same scene must not be queued
  /// again on the next frame.
  void commit() {
    final SceneAnnouncement? pending = _pending;
    if (pending == null) return;
    // Remember the WHOLE scene, not just what changed: objects the user has
    // already heard must not look new on the next frame.
    _announced
      ..clear()
      ..addEntries(
        pending.slots.map(
          (SceneSlot s) => MapEntry<String, SceneSlot>(s.key, s),
        ),
      );
    _pendingCommitted = true;
  }

  /// Drop the sentences for this frame but keep object history.
  ///
  /// Used while a safety warning owns the user's attention: the scene must not
  /// queue anything behind "Stop.", but when the hazard is gone the announcer
  /// must still know what was already said.
  void suppressPending() {
    _pending = null;
  }

  /// Forget everything: used when navigation starts or stops, so a new run
  /// never compares itself against the previous run's scene.
  void reset() {
    _tracks.clear();
    _pending = null;
    _pendingCommitted = false;
    _announced.clear();
  }

  /// Build the sentences for one analysed frame.
  ///
  /// [detections] are the enriched detections (position and calibrated
  /// distance already applied), [primaryBlocker] is the object the path
  /// analysis flagged (spoken first), and [include] is the caller's relevance
  /// filter (the per-category announcement switches).
  ///
  /// Only objects whose state actually changed produce a sentence; an
  /// unchanged scene returns an announcement with no sentences.
  SceneAnnouncement? compose({
    required List<DetectedObject> detections,
    DetectedObject? primaryBlocker,
    bool Function(DetectedObject object)? include,
  }) {
    final List<DetectedObject> relevant = _dedupe(
      detections.where((DetectedObject o) {
        if (o.confidence <= 0) return false;
        if (backgroundClasses.contains(_classOf(o))) return false;
        return include == null || include(o);
      }).toList(),
    );

    // Track every relevant detection (ghosts included) so distances and
    // identities stay continuous, but only speak identified objects.
    final List<_Track> matched = _associate(relevant);

    final List<_Track> spoken = matched.where((_Track t) => !t.isGhost).toList();
    if (spoken.isEmpty) {
      // An unidentified obstacle is still worth one line when nothing else is
      // in the frame; the depth pipeline only creates it when a real,
      // unnameable hazard blocked the path.
      spoken.addAll(matched.where((_Track t) => t.isGhost));
    }
    if (spoken.isEmpty) {
      _pending = null;
      return null;
    }

    spoken.sort(_comparatorFor(primaryBlocker));

    // The full current scene (used as the "already told" state), then the
    // capped slice of objects that actually changed and need a sentence.
    final List<SceneSlot> allSlots =
        spoken.map(_slotFor).toList(growable: false);
    final List<SceneSlot> changedSlots = <SceneSlot>[];
    final List<DetectedObject> changedMembers = <DetectedObject>[];
    for (int i = 0; i < allSlots.length; i++) {
      if (i >= maxAnnouncedObjects) break;
      final SceneSlot slot = allSlots[i];
      if (!_isChanged(slot)) continue;
      changedSlots.add(slot);
      changedMembers.add(spoken[i].object);
    }

    _pendingCommitted = false;
    _pending = SceneAnnouncement(
      sentences: changedSlots.map(_speakOne).toList(),
      slots: allSlots,
      members: changedMembers,
    );
    return _pending;
  }

  // ------------------------------------------------------------------
  // Change detection
  // ------------------------------------------------------------------

  /// Whether this object has to be spoken again.
  ///
  /// Distances are compared as real values against what was last announced, so
  /// 2.08 m against an announced 2.10 m is NOT a change while 1.60 m is. Using
  /// quantized bands here would make a band boundary look like movement.
  bool _isChanged(SceneSlot slot) {
    final SceneSlot? told = _announced[slot.key];
    if (told == null) return true;
    final double? a = told.meters;
    final double? b = slot.meters;
    if (a == null || b == null) return a != b;
    return (a - b).abs() >= DISTANCE_CHANGE_THRESHOLD;
  }

  /// Describe one track for the current frame.
  SceneSlot _slotFor(_Track track) {
    return SceneSlot(
      label: track.object.displayName,
      className: track.className,
      position: track.position,
      meters: track.spokenMeters,
    );
  }

  // ------------------------------------------------------------------
  // Deduplication
  // ------------------------------------------------------------------

  /// One object per class per side: overlapping duplicate boxes of the same
  /// chair in the same frame are one chair.
  List<DetectedObject> _dedupe(List<DetectedObject> detections) {
    final List<DetectedObject> unique = <DetectedObject>[];
    final Map<String, int> seen = <String, int>{};

    for (final DetectedObject obj in detections) {
      final String key = _classOf(obj);
      final String slotKey = '$key|${_positionOf(obj).label}';
      final int? index = seen[slotKey];
      if (index == null) {
        seen[slotKey] = unique.length;
        unique.add(obj);
      } else if (_closer(obj, unique[index])) {
        unique[index] = obj;
      }
    }
    return unique;
  }

  static String _classOf(DetectedObject obj) => obj.className.toLowerCase();

  static ObjectPosition _positionOf(DetectedObject obj) =>
      obj.position ?? ObjectPosition.fromCenterX(obj.centerX);

  bool _closer(DetectedObject candidate, DetectedObject current) {
    final double? a = candidate.distanceMeters;
    final double? b = current.distanceMeters;
    if (a != null && b != null) return a < b;
    if (a != null && b == null) return true;
    if (a == null && b != null) return false;
    return _area(candidate) > _area(current);
  }

  double _area(DetectedObject obj) {
    final Rect box = obj.boundingBox;
    return box.width * box.height;
  }

  // ------------------------------------------------------------------
  // Tracking
  // ------------------------------------------------------------------

  /// Associate this frame's detections with existing tracks (class + IoU/side)
  /// and return one track per detection.
  List<_Track> _associate(List<DetectedObject> detections) {
    final List<_Track> used = <_Track>[];
    final List<_Track> matched = <_Track>[];

    for (final DetectedObject obj in detections) {
      _Track? best;
      double bestScore = 0;

      for (final _Track track in _tracks) {
        if (used.contains(track)) continue;
        if (track.className != _classOf(obj)) continue;
        final double iou = _iou(track.box, obj.boundingBox);
        final bool sameSide = track.position == _positionOf(obj);
        // Either real box overlap, or an un-overlappable box on the same side
        // (a small distant object can jitter a lot between frames).
        final bool match = iou >= iouMatchThreshold || (iou > 0 && sameSide);
        if (!match) continue;
        final double score = iou + (sameSide ? 0.25 : 0);
        if (score > bestScore) {
          bestScore = score;
          best = track;
        }
      }

      if (best == null) {
        best = _Track(obj);
        _tracks.add(best);
      } else {
        used.add(best);
        best.update(obj);
      }
      matched.add(best);
    }

    // Unmatched tracks age out; their history survives the lost grace so a
    // briefly occluded object is recognised when it reappears.
    for (final _Track track in _tracks) {
      if (!used.contains(track) && !matched.contains(track)) {
        track.missedFrames++;
      }
    }
    _tracks.removeWhere((_Track t) => t.missedFrames > trackLostGrace);

    return matched;
  }

  double _iou(Rect a, Rect b) {
    final double left = a.left > b.left ? a.left : b.left;
    final double top = a.top > b.top ? a.top : b.top;
    final double right = a.right < b.right ? a.right : b.right;
    final double bottom = a.bottom < b.bottom ? a.bottom : b.bottom;
    if (right <= left || bottom <= top) return 0;
    final double intersection = (right - left) * (bottom - top);
    final double union = _areaRect(a) + _areaRect(b) - intersection;
    if (union <= 0) return 0;
    return intersection / union;
  }

  double _areaRect(Rect r) =>
      r.width <= 0 || r.height <= 0 ? 0 : r.width * r.height;

  // ------------------------------------------------------------------
  // Ordering
  // ------------------------------------------------------------------

  /// Path blocker first, then collision risk, then nearest, then a stable
  /// left-to-right order so the sentence never reshuffles on its own.
  int Function(_Track, _Track) _comparatorFor(DetectedObject? blocker) {
    int blockerRank(_Track track) =>
        blocker != null && identical(track.object, blocker) ? 1 : 0;

    return (_Track a, _Track b) {
      final int blockerOrder = blockerRank(b).compareTo(blockerRank(a));
      if (blockerOrder != 0) return blockerOrder;

      final int danger = _dangerRank(a.object).compareTo(_dangerRank(b.object));
      if (danger != 0) return danger;

      // An object with no depth reading cannot be ranked by distance, so it
      // goes after the ones we can actually place.
      final double aDistance = a.spokenMeters ?? double.infinity;
      final double bDistance = b.spokenMeters ?? double.infinity;
      final int byDistance = aDistance.compareTo(bDistance);
      if (byDistance != 0) return byDistance;

      return _sideRank(a).compareTo(_sideRank(b));
    };
  }

  static int _dangerRank(DetectedObject obj) {
    switch (obj.proximity ?? ProximityLevel.far) {
      case ProximityLevel.veryNear:
        return 3;
      case ProximityLevel.near:
        return 2;
      case ProximityLevel.medium:
        return 1;
      case ProximityLevel.far:
        return 0;
    }
  }

  /// Directly ahead first, then left, then right — an object in the walking
  /// path is more useful than one beside it.
  static int _sideRank(_Track track) {
    switch (track.position) {
      case ObjectPosition.center:
        return 0;
      case ObjectPosition.left:
        return 1;
      case ObjectPosition.right:
        return 2;
    }
  }

  // ------------------------------------------------------------------
  // Wording
  // ------------------------------------------------------------------

  /// One complete sentence per object:
  ///   "Person detected, 1.8 meters ahead."
  ///   "Chair detected, 2.4 meters to your left."
  ///
  /// The distance is only ever the value the depth system actually produced
  /// for this object; when it has none, the sentence simply omits it rather
  /// than inventing one.
  String _speakOne(SceneSlot slot) {
    final String where = _positionPhrase(slot.position);
    final double? meters = slot.meters;

    if (meters == null) return '${slot.label} detected $where.';
    final String value = _spokenMeters(meters);
    final String unit = value == '1' ? 'meter' : 'meters';
    return '${slot.label} detected, $value $unit $where.';
  }

  /// Meters for speech: trailing zeros are dropped ("3 meters", "0.4 meters")
  /// because reading "3.0" aloud sounds like false precision.
  static String _spokenMeters(double meters) {
    final String formatted = formatDistanceMeters(meters);
    if (formatted.endsWith('.0')) {
      return formatted.substring(0, formatted.length - 2);
    }
    final int dot = formatted.indexOf('.');
    if (dot >= 0 && formatted.endsWith('0') && formatted.length - dot == 3) {
      return formatted.substring(0, formatted.length - 1);
    }
    return formatted;
  }

  /// Physical side, as the camera preview shows it: the boxes are already
  /// normalized against the upright preview, so physical left stays LEFT.
  static String _positionPhrase(ObjectPosition position) {
    switch (position) {
      case ObjectPosition.center:
        return 'ahead';
      case ObjectPosition.left:
        return 'to your left';
      case ObjectPosition.right:
        return 'to your right';
    }
  }
}

/// History of one physical object across frames.
class _Track {
  _Track(this.object) {
    className = object.className.toLowerCase();
    box = object.boundingBox;
    position = object.position ?? ObjectPosition.fromCenterX(object.centerX);
    _smoothed = _validMeters(object);
  }

  late String className;
  late Rect box;
  late ObjectPosition position;

  /// Frames since this track was last matched to a detection.
  int missedFrames = 0;

  /// Distance smoothed across this object's own measurements.
  double? _smoothed;

  late DetectedObject object;

  /// The smoothed distance to speak, or null when the depth system has no
  /// valid reading for this object in this frame.
  double? get spokenMeters => _smoothed;

  bool get isGhost => className == SceneAnnouncer.ghostClass;

  void update(DetectedObject next) {
    object = next;
    box = next.boundingBox;
    position = next.position ?? ObjectPosition.fromCenterX(next.centerX);
    missedFrames = 0;

    final double? measured = _validMeters(next);
    if (measured == null) return;
    _smoothed = _smoothed == null
        ? measured
        : SceneAnnouncer.smoothingAlpha * measured +
            (1 - SceneAnnouncer.smoothingAlpha) * _smoothed!;
  }

  /// A distance is only ever taken from the depth system, never invented.
  static double? _validMeters(DetectedObject obj) {
    final double? meters = obj.distanceMeters;
    if (meters == null) return null;
    if (meters.isNaN || meters.isInfinite || meters <= 0) return null;
    return meters;
  }
}
