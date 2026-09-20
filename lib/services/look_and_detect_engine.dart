import 'package:flutter/foundation.dart';

import '../models/look_and_detect.dart';
import '../models/object_position.dart';
import '../models/proximity_level.dart';
import 'settings_service.dart';

/// Per-class track used for change detection across frames.
class _Track {
  _Track(this.className);

  final String className;
  bool present = false;
  bool graceActive = false;
  ObjectPosition position = ObjectPosition.center;
  ProximityLevel proximity = ProximityLevel.far;
  DateTime seenAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime absentSince = DateTime.fromMillisecondsSinceEpoch(0);
  bool everAnnounced = false;
  DateTime? lastAnnouncedAt;
  ObjectPosition? announcedPosition;
  ProximityLevel? announcedProximity;

  // Familiar-person identity confirmation (votes across frames).
  String? pendingName;
  int nameVotes = 0;
  String? confirmedName;
  DateTime lastNameSeenAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool nameJustConfirmed = false;
}

class _Candidate {
  _Candidate(this.score, this.track, this.text);
  final int score;
  final _Track track;
  final String text;
}

/// LookAndDetectEngine is the pure-Dart brain of the Look & Detect feature.
///
/// Responsibilities:
///  1. Keep the current scene snapshot (objects + positions + names).
///  2. Detect meaningful environmental changes and emit short, natural,
///     non-overloading voice announcements (people get priority; nothing is
///     repeated while it is unchanged).
///  3. Answer user questions ("What is around me?", "What is on my left?",
///     "Find the bottle", "Describe the scene") based only on what the camera
///     actually sees.
///
/// The engine never fabricates information: a requested object that is not
/// detected is honestly reported as "not found".
class LookAndDetectEngine extends ChangeNotifier {
  LookAndDetectEngine({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  List<SceneObject> _current = const [];
  final Map<String, _Track> _tracks = {};
  DateTime? _lastAnnounceAt;
  String _lastAnnouncement = '';
  String _lastResponse = '';
  String? _lastTopicClass;

  /// Current scene snapshot (unmodifiable).
  List<SceneObject> get currentObjects => List.unmodifiable(_current);

  /// The last automatically voiced announcement.
  String get lastAnnouncement => _lastAnnouncement;

  /// The last answer given to a user query.
  String get lastResponse => _lastResponse;

  static const Map<int, String> _numWords = {
    1: 'one',
    2: 'two',
    3: 'three',
    4: 'four',
    5: 'five',
  };

  static const Set<String> _vehicles = {
    'car',
    'truck',
    'bus',
    'bicycle',
    'motorcycle',
    'train',
    'airplane',
    'boat',
  };

  static const Set<String> _animals = {
    'cat',
    'dog',
    'bird',
    'horse',
    'sheep',
    'cow',
    'elephant',
    'bear',
    'zebra',
    'giraffe',
  };

  static const Set<String> _furniture = {
    'chair',
    'sofa',
    'couch',
    'table',
    'dining table',
    'bench',
    'bed',
    'refrigerator',
    'tv',
    'microwave',
    'oven',
    'toaster',
    'sink',
    'potted plant',
    'book',
    'clock',
    'vase',
    'bottle',
    'bowl',
    'cup',
    'wine glass',
    'umbrella',
    'backpack',
    'handbag',
    'suitcase',
    'laptop',
    'remote',
    'keyboard',
    'cell phone',
    'mouse',
    'teddy bear',
  };

  // ------------------------------------------------------------------
  // Scene ingestion
  // ------------------------------------------------------------------

  /// Ingests the latest recognised scene and, when something meaningful
  /// changed, returns a short natural announcement to be spoken (or null).
  String? updateScene(List<SceneObject> objects) {
    final now = _clock();
    _current = List.of(objects);

    final byClass = <String, List<SceneObject>>{};
    for (final o in objects) {
      byClass.putIfAbsent(o.className.toLowerCase(), () => []).add(o);
    }
    final prev = _tracks;

    // Build fresh tracks for classes present this frame.
    final fresh = <String, _Track>{};
    for (final entry in byClass.entries) {
      final cls = entry.key;
      final primary = _primaryInstance(entry.value);
      final was = prev[cls];
      final t = was ?? _Track(cls);
      t.present = true;
      t.graceActive = false;
      t.position = primary.position;
      t.proximity = primary.proximity;
      t.seenAt = now;

      if (cls == 'person') {
        final names = <String>{
          for (final o in entry.value)
            if (o.knownName != null) o.knownName!,
        };
        if (names.isNotEmpty) {
          final name = names.first;
          if (t.pendingName == name) {
            t.nameVotes++;
          } else {
            t.pendingName = name;
            t.nameVotes = 1;
          }
          t.lastNameSeenAt = now;
          if (t.nameVotes >= 3 &&
              (t.confirmedName == null || t.confirmedName != name)) {
            t.confirmedName = name;
            t.nameJustConfirmed = true;
          }
        } else if (t.confirmedName != null &&
            now.difference(t.lastNameSeenAt) > const Duration(seconds: 2)) {
          // Recognition missed this frame for a while: un-confirm the name.
          t.confirmedName = null;
          t.pendingName = null;
          t.nameVotes = 0;
        }
      }
      fresh[cls] = t;
    }

    // Handle disappeared classes with a short grace period so blinking
    // detections do not cause appear/depart ping-pong announcements.
    final departedPeople = <_Track>[];
    for (final entry in prev.entries) {
      if (fresh.containsKey(entry.key)) continue;
      final t = entry.value;
      t.present = false;
      if (!t.graceActive) {
        t.graceActive = true;
        t.absentSince = now;
        continue;
      }
      if (now.difference(t.absentSince) >= const Duration(milliseconds: 1600)) {
        if (t.everAnnounced && entry.key == 'person') {
          t.position = t.announcedPosition ?? t.position;
          departedPeople.add(t);
        }
        prev.remove(entry.key);
      }
    }

    // Merge surviving (grace) tracks with fresh tracks.
    prev.addAll(fresh);

    // Build announcement candidates from changes.
    final candidates = <_Candidate>[];
    for (final t in prev.values) {
      if (!t.present) continue;
      if (!t.everAnnounced) {
        t.everAnnounced = true;
        if (_allowed(t.className)) {
          candidates.add(_Candidate(
            _scoreFor(t),
            t,
            _appearedText(t),
          ));
        }
      } else {
        // Change detection on an already-announced track.
        if (_canAnnounce(t, now) &&
            t.announcedPosition != null &&
            t.position != t.announcedPosition &&
            _allowed(t.className)) {
          candidates.add(_Candidate(
            _scoreFor(t) - 4,
            t,
            _movedText(t),
          ));
        }
        if (_canAnnounce(t, now) &&
            t.announcedProximity != null &&
            _approaching(t.announcedProximity!, t.proximity) &&
            _allowed(t.className)) {
          candidates.add(_Candidate(
            _scoreFor(t) - 6,
            t,
            _approachText(t),
          ));
        }
        if (t.nameJustConfirmed) {
          candidates.add(_Candidate(
            120,
            t,
            '${t.confirmedName} is ${positionPhraseLong(t.position)}.',
          ));
          t.nameJustConfirmed = false;
        }
      }
    }
    for (final t in departedPeople) {
      candidates.add(_Candidate(30, t, 'Person moved away.'));
    }

    if (candidates.isEmpty) {
      if (_lastAnnouncement.isNotEmpty) {
        _lastAnnouncement = '';
      }
      return null;
    }

    // Priority selection: top 2 candidates, respecting gaps.
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final chosen = <String>[];
    for (final c in candidates) {
      if (chosen.length >= 2) break;
      if (_lastAnnounceAt != null &&
          now.difference(_lastAnnounceAt!) < _gap()) {
        break;
      }
      if (!_canAnnounce(c.track, now)) continue;
      chosen.add(c.text);
      c.track.lastAnnouncedAt = now;
      c.track.announcedPosition = c.track.position;
      c.track.announcedProximity = c.track.proximity;
      _lastAnnounceAt = now;
    }
    if (chosen.isEmpty) return null;

    final msg = _joinNatural(chosen);
    _lastAnnouncement = msg;
    notifyListeners();
    return msg;
  }

  bool _canAnnounce(_Track t, DateTime now) {
    if (t.lastAnnouncedAt == null) return true;
    return now.difference(t.lastAnnouncedAt!) >= _gap();
  }

  Duration _gap() {
    final seconds = SettingsService.instance.announcementCooldownSeconds;
    return Duration(seconds: seconds.clamp(2, 10));
  }

  /// Whether the proximity moved significantly toward the user.
  bool _approaching(ProximityLevel was, ProximityLevel now) {
    return now.rank > was.rank &&
        (now == ProximityLevel.near || now == ProximityLevel.veryNear);
  }

  /// Whether [className] may be announced, honoring the Detection category
  /// toggles in the settings.
  bool _allowed(String className) {
    final s = SettingsService.instance;
    if (className == 'person') return s.peopleAnnouncements;
    if (_vehicles.contains(className)) return s.vehicleAnnouncements;
    if (_animals.contains(className)) return s.animalAnnouncements;
    if (_furniture.contains(className)) return s.furnitureAnnouncements;
    return s.obstacleAnnouncements;
  }

  // ------------------------------------------------------------------
  // Announcement phrasing
  // ------------------------------------------------------------------

  SceneObject _primaryInstance(List<SceneObject> list) {
    final sorted = List<SceneObject>.of(list);
    sorted.sort((a, b) {
      if (a.proximity.rank != b.proximity.rank) {
        return b.proximity.rank.compareTo(a.proximity.rank);
      }
      final da = (a.centerX - 0.5).abs();
      final db = (b.centerX - 0.5).abs();
      if (da != db) return da.compareTo(db);
      return b.confidence.compareTo(a.confidence);
    });
    return sorted.first;
  }

  int _scoreFor(_Track t) {
    var score = 40;
    if (t.className == 'person') {
      score = 100;
      if (t.confirmedName != null) score += 20;
    } else if (_vehicles.contains(t.className)) {
      score = 80;
    } else if (_animals.contains(t.className)) {
      score = 60;
    }
    switch (t.proximity) {
      case ProximityLevel.veryNear:
        score += 20;
      case ProximityLevel.near:
        score += 12;
      case ProximityLevel.medium:
        score += 6;
      case ProximityLevel.far:
        break;
    }
    if (t.position == ObjectPosition.center) score += 8;
    return score;
  }

  String _appearedText(_Track t) {
    if (t.className == 'person') {
      final phrase = _peoplePhrase();
      return phrase.isNotEmpty ? phrase : "There's someone ahead.";
    }
    final String base;
    if (t.confirmedName != null) {
      base = '${t.confirmedName} ${positionPhraseShort(t.position)}.';
    } else {
      base =
          'There is ${_article(t.className)} ${t.className} '
          '${positionPhraseShort(t.position)}.';
    }
    if (t.proximity == ProximityLevel.veryNear) {
      return 'Very close. $base';
    }
    return base;
  }

  String _movedText(_Track t) {
    final label = t.confirmedName ?? _capitalize(t.className);
    return '$label is now ${positionPhraseShort(t.position)}.';
  }

  String _approachText(_Track t) {
    final label = t.confirmedName ?? _capitalize(t.className);
    if (_vehicles.contains(t.className) || _animals.contains(t.className)) {
      return 'A ${t.className} is getting close.';
    }
    return '$label is nearby.';
  }

  /// Natural phrase describing the people currently seen (optionally on one
  /// side only). Returns '' when there are none.
  String _peoplePhrase({ObjectPosition? side}) {
    final people = _current
        .where((o) => o.isPerson && (side == null || o.position == side))
        .toList();
    if (people.isEmpty) return '';

    if (people.length == 1) {
      final o = people.first;
      final name = o.knownName;
      if (name != null) return '$name is ${positionPhraseLong(o.position)}.';
      return "There's someone ${positionPhraseLong(o.position)}.";
    }

    final known = <String>[];
    for (final o in people) {
      if (o.knownName != null && known.length < 2) {
        known.add('${o.knownName} is ${positionPhraseLong(o.position)}.');
      }
    }
    final sorted = List<SceneObject>.of(people)
      ..sort((a, b) => b.proximity.rank.compareTo(a.proximity.rank));
    final a = sorted[0];
    final b = sorted[1];
    final String positionPart;
    if (a.position == b.position) {
      positionPart = 'They are ${positionPhraseLong(a.position)}.';
    } else {
      positionPart =
          'One person is ${positionPhraseLong(a.position)} and another is '
          '${positionPhraseLong(b.position)}.';
    }
    final count = _numWords[people.length] ?? '${people.length}';
    if (known.isEmpty) {
      return 'There are $count people. $positionPart';
    }
    return 'There are $count people. ${known.join(' ')}';
  }

  String _joinNatural(List<String> parts) {
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first;
    final cleaned = [
      for (final p in parts)
        p.endsWith('.') ? p.substring(0, p.length - 1) : p,
    ];
    if (cleaned.length == 2) return '${cleaned[0]} and ${cleaned[1]}.';
    return '${cleaned.sublist(0, cleaned.length - 1).join(', ')}, and '
        '${cleaned.last}.';
  }

  // ------------------------------------------------------------------
  // Scene description
  // ------------------------------------------------------------------

  /// A natural, conversational description of the current environment, built
  /// only from what the camera actually sees. Speaks like a human assistant
  /// rather than a list of detections, and never invents objects.
  String describeScene() {
    final objs = _current;
    if (objs.isEmpty) {
      return "I can't see anything clearly right now. Try pointing the camera "
          'at whatever you want me to describe.';
    }

    final objects = objs.where((o) => !o.isPerson).toList();
    final parts = <String>[];
    final peoplePart = _peopleSentence();
    if (peoplePart.isNotEmpty) parts.add(peoplePart);
    final objectPart = _objectsSentence(objects);
    if (objectPart.isNotEmpty) parts.add(objectPart);

    final env = _environmentPhrase();
    final joined = _joinNatural(parts);
    return env.isEmpty ? joined : '$env $joined';
  }

  /// Natural sentence about the people currently seen ('' when none).
  String _peopleSentence() {
    final people = _current.where((o) => o.isPerson).toList();
    if (people.isEmpty) return '';

    if (people.length == 1) {
      final o = people.first;
      if (o.knownName != null) {
        return 'I can see ${o.knownName} ${positionPhraseLong(o.position)}.';
      }
      return 'I can see ${_itemPhrase(o, count: 1)}.';
    }

    final named = people.where((o) => o.knownName != null).toList();
    if (named.isNotEmpty && named.length == people.length && named.length <= 2) {
      final names = [
        for (final o in named) '${o.knownName} is ${positionPhraseLong(o.position)}',
      ];
      return 'I can see ${names.join(' and ')}.';
    }

    final count = _numWords[people.length] ?? '${people.length}';
    return 'There are $count people around.';
  }

  /// Natural sentence about the visible objects (people excluded).
  String _objectsSentence(List<SceneObject> objects) {
    if (objects.isEmpty) return '';

    final grouped = <String, List<SceneObject>>{};
    for (final o in objects) {
      final key = o.className.toLowerCase();
      grouped.putIfAbsent(key, () => []).add(o);
    }

    final entries = grouped.entries.toList()
      ..sort((a, b) {
        final an = _primaryInstance(a.value);
        final bn = _primaryInstance(b.value);
        final r = bn.proximity.rank.compareTo(an.proximity.rank);
        if (r != 0) return r;
        return ((an.centerX - 0.5).abs()).compareTo((bn.centerX - 0.5).abs());
      });

    final items = <String>[];
    for (final e in entries.take(4)) {
      items.add(_itemPhrase(_primaryInstance(e.value), count: e.value.length));
    }

    // Honest hedge when the model is unsure: no raw confidence on screen or in
    // the wording, just conservative framing.
    final lowConfidence = entries.any((e) {
      final avg = e.value.fold<double>(
              0, (s, o) => s + o.confidence) /
          e.value.length;
      return avg < 0.6;
    });

    var joined = _joinNatural(items);
    if (!joined.endsWith('.')) joined = '$joined.';
    final lead = entries.length > 4
        ? ', plus a few other things'
        : '';
    final verb = lowConfidence ? 'I think I can see' : 'I can see';
    return '$verb $joined$lead';
  }

  /// A natural item phrase: "a chair slightly to your left, right up close"
  /// or "two chairs directly ahead". [count] is how many instances of this
  /// class are visible so plurals are grammatically correct.
  String _itemPhrase(SceneObject o, {required int count}) {
    final where = positionPhraseLong(o.position);
    final here = _proximityModifier(o.proximity);
    final String head;
    if (count == 1) {
      head = '${_article(o.displayName)} ${o.displayName}';
    } else {
      head = '${_numWords[count] ?? '$count'} ${_plural(o.displayName)}';
    }
    if (here.isEmpty) return '$head $where';
    return '$head $where, $here';
  }

  /// Spoken proximity descriptors for natural phrasing.
  String _proximityModifier(ProximityLevel p) {
    switch (p) {
      case ProximityLevel.veryNear:
        return 'right up close to you';
      case ProximityLevel.near:
        return 'close by';
      case ProximityLevel.medium:
        return 'a little way off';
      case ProximityLevel.far:
        return '';
    }
  }

  /// Best-effort coarse environment label ("in a room" vs "outdoors").
  String _environmentPhrase() {
    var outdoor = false;
    var indoor = false;
    for (final o in _current) {
      final cls = o.className.toLowerCase();
      if (_vehicles.contains(cls)) outdoor = true;
      if (_furniture.contains(cls)) indoor = true;
    }
    if (outdoor && !indoor) return 'You appear to be outdoors.';
    if (indoor && !outdoor) return 'You appear to be in a room.';
    return '';
  }

  // ------------------------------------------------------------------
  // Question answering
  // ------------------------------------------------------------------

  /// Answer a free-text user question based on the current scene. The returned
  /// string is meant to be spoken. Never invents objects that are not seen.
  String answerQuery(String raw) {
    final original = raw.trim();
    final text = original.toLowerCase();

    if (text.isEmpty) {
      _lastResponse =
          'Ask what is around you, or let me help you find something.';
      return _lastResponse;
    }

    // Repeat the last response.
    if (_hasAny(text, const ['repeat', 'again', 'say that', 'say it'])) {
      final last = _lastResponse.isNotEmpty
          ? _lastResponse
          : (_lastAnnouncement.isNotEmpty
              ? _lastAnnouncement
              : "I haven't said anything yet.");
      _lastResponse = last;
      return _lastResponse;
    }

    final wantsPeople = _hasAny(text, const [
      'person',
      'people',
      'anyone',
      'anybody',
      'someone',
      'somebody',
      'is there a man',
      'is there a woman',
    ]);

    // Position queries take priority over a generic "what do you see".
    final wantsLeft = _hasAny(text, const ['left']);
    final wantsRight = _hasAny(text, const ['right']);
    final wantsFront = _hasAny(
      text,
      const ['front of me', 'ahead', 'in front', 'before me'],
    );
    if (wantsLeft || wantsRight || wantsFront) {
      final side = wantsLeft
          ? ObjectPosition.left
          : (wantsRight ? ObjectPosition.right : ObjectPosition.center);
      if (wantsPeople) {
        final part = _peoplePhrase(side: side);
        _lastTopicClass = 'person';
        if (part.isEmpty) {
          _lastResponse = _noneAt(side);
          return _lastResponse;
        }
        _lastResponse = part;
        return _lastResponse;
      }
      _lastResponse = _responseAt(side);
      return _lastResponse;
    }

    // People-only queries.
    if (wantsPeople) {
      final part = _peoplePhrase();
      _lastTopicClass = 'person';
      if (part.isEmpty) {
        _lastResponse = "I don't see anyone right now.";
        return _lastResponse;
      }
      _lastResponse = part;
      return _lastResponse;
    }

    // Scene description queries.
    if (_hasAny(text, const [
      'around me',
      'surround',
      'describe',
      'what do you see',
      'what do i see',
      'what is there',
      'what is here',
    ])) {
      _lastResponse = describeScene();
      return _lastResponse;
    }

    // Find / is-there / where-is object queries.
    final targets = _extractClasses(text);
    if (targets.isNotEmpty) {
      _lastTopicClass = targets.first;
      _lastResponse = _responseForClasses(targets, original);
      return _lastResponse;
    }

    // Follow-up proximity questions about the last topic.
    if (_lastTopicClass != null &&
        _hasAny(text, const ['close', 'nearby', 'far', 'near'])) {
      _lastResponse = _proximityAnswer(_lastTopicClass!);
      return _lastResponse;
    }

    // Find-without-a-target guidance.
    if (_hasAny(text, const ['find', 'where is', 'where are', 'look for'])) {
      _lastResponse = 'What would you like me to look for?';
      return _lastResponse;
    }

    _lastResponse =
        "I'm not sure what you asked. Try asking what is around you, "
        'what is in front of you, or ask me to find something.';
    return _lastResponse;
  }

  String _noneAt(ObjectPosition side) {
    switch (side) {
      case ObjectPosition.left:
        return 'Nothing on your left.';
      case ObjectPosition.center:
        return 'Nothing directly ahead.';
      case ObjectPosition.right:
        return 'Nothing on your right.';
    }
  }

  String _responseAt(ObjectPosition side) {
    final atSide =
        _current.where((o) => o.position == side).toList();
    if (atSide.isEmpty) return _noneAt(side);

    final people = atSide.where((o) => o.isPerson).toList();
    final objects = atSide.where((o) => !o.isPerson).toList();

    final parts = <String>[];
    if (people.isNotEmpty) {
      final part = _peoplePhrase(side: side);
      if (part.isNotEmpty) parts.add(part);
    }
    // One representative per class at this side, nearest first.
    final byClass = <String, SceneObject>{};
    for (final o in objects) {
      final key = o.className.toLowerCase();
      final existing = byClass[key];
      if (existing == null || o.proximity.rank > existing.proximity.rank) {
        byClass[key] = o;
      }
    }
    final sorted = byClass.values.toList()
      ..sort((a, b) => b.proximity.rank.compareTo(a.proximity.rank));
    for (final o in sorted.take(2)) {
      parts.add('I can see ${_itemPhrase(o, count: 1)}.');
    }

    if (parts.length == 1) return parts.first;
    return _joinNatural(parts);
  }

  String _responseForClasses(List<String> classes, String original) {
    final found = <String, List<SceneObject>>{};
    for (final cls in classes) {
      final matches =
          _current.where((o) => o.className.toLowerCase() == cls).toList();
      if (matches.isNotEmpty) found[matches.first.className] = matches;
    }

    if (found.isEmpty) {
      final display = _displayForUnknownQuery(classes.last, original);
      return "I can't find ${_article(display)} $display right now.";
    }

    final parts = <String>[];
    final entries = found.entries.toList();
    for (final entry in entries) {
      final matches = entry.value;
      if (matches.length == 1) {
        final o = matches.first;
        if (o.isPerson) {
          parts.add(
            'I can see ${o.knownName ?? 'someone'} '
            '${positionPhraseLong(o.position)}.',
          );
        } else {
          parts.add('I can see ${_itemPhrase(o, count: 1)}.');
        }
      } else {
        final count = _numWords[matches.length] ?? '${matches.length}';
        final positions = matches.map((o) => o.position).toSet().toList();
        final positionPart =
            positions.length == 1
                ? positionPhraseLong(positions.first)
                : 'in different places';
        parts.add(
          'I see $count ${_plural(matches.first.displayName)}. '
          'They are $positionPart.',
        );
      }
    }
    return parts.join(' ');
  }

  String _proximityAnswer(String cls) {
    final matches =
        _current.where((o) => o.className.toLowerCase() == cls).toList();
    if (matches.isEmpty) {
      return "I can't see it right now.";
    }
    final nearest = _primaryInstance(matches);
    switch (nearest.proximity) {
      case ProximityLevel.veryNear:
        return 'Yes, it is very close.';
      case ProximityLevel.near:
        return 'Yes, it appears nearby.';
      case ProximityLevel.medium:
        return 'It is a short distance ahead.';
      case ProximityLevel.far:
        return 'It looks farther away.';
    }
  }

  // ------------------------------------------------------------------
  // Query parsing helpers
  // ------------------------------------------------------------------

  static bool _hasAny(String text, List<String> needles) {
    for (final n in needles) {
      if (text.contains(n)) return true;
    }
    return false;
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  static String _plural(String display) {
    return display.toLowerCase().endsWith('s')
        ? display.toLowerCase()
        : '${display.toLowerCase()}s';
  }

  static String _article(String display) {
    final first = display.isEmpty ? '' : display[0].toLowerCase();
    return ('aeiou'.contains(first)) ? 'an' : 'a';
  }

  /// The YOLO class names the app currently understands, used both for
  /// matching query words and as a safety net against inventing classes.
  static const List<String> _classes = [
    'person',
    'bicycle',
    'car',
    'motorcycle',
    'airplane',
    'bus',
    'train',
    'truck',
    'boat',
    'traffic light',
    'fire hydrant',
    'stop sign',
    'parking meter',
    'bench',
    'bird',
    'cat',
    'dog',
    'horse',
    'sheep',
    'cow',
    'elephant',
    'bear',
    'zebra',
    'giraffe',
    'backpack',
    'umbrella',
    'handbag',
    'tie',
    'suitcase',
    'frisbee',
    'sports ball',
    'kite',
    'baseball glove',
    'skateboard',
    'tennis racket',
    'bottle',
    'wine glass',
    'cup',
    'fork',
    'knife',
    'spoon',
    'bowl',
    'banana',
    'apple',
    'sandwich',
    'orange',
    'broccoli',
    'carrot',
    'hot dog',
    'pizza',
    'donut',
    'cake',
    'chair',
    'couch',
    'potted plant',
    'bed',
    'dining table',
    'toilet',
    'tv',
    'laptop',
    'mouse',
    'remote',
    'keyboard',
    'cell phone',
    'microwave',
    'oven',
    'toaster',
    'sink',
    'refrigerator',
    'book',
    'clock',
    'vase',
    'scissors',
    'teddy bear',
    'hair drier',
    'toothbrush',
  ];

  /// Common words a user might say mapped onto the YOLO class(es) they mean.
  static const Map<String, List<String>> _aliases = {
    'table': ['dining table'],
    'dining table': ['dining table'],
    'phone': ['cell phone'],
    'cell phone': ['cell phone'],
    'mobile': ['cell phone'],
    'sofa': ['couch'],
    'couch': ['couch'],
    'fridge': ['refrigerator'],
    'refrigerator': ['refrigerator'],
    'television': ['tv'],
    'screen': ['tv'],
    'motorbike': ['motorcycle'],
    'bike': ['bicycle'],
    'vehicle': ['car', 'bus', 'truck', 'motorcycle', 'bicycle'],
    'bag': ['handbag', 'backpack', 'suitcase'],
    'cup': ['cup', 'wine glass'],
    'glass': ['wine glass'],
    'bottle': ['bottle'],
    'chair': ['chair'],
    'laptop': ['laptop'],
    'book': ['book'],
    'dog': ['dog'],
    'cat': ['cat'],
    'person': ['person'],
    'people': ['person'],
    'door': <String>[],
    'stairs': <String>[],
    'window': <String>[],
  };

  /// Extracts the YOLO classes the question is asking about (empty when the
  /// user is not asking about a specific object). Never matches words that
  /// look like an object but are not in the class list, so the assistant
  /// cannot claim to find a door that the model cannot see.
  List<String> _extractClasses(String text) {
    final classes = <String>{};
    final words = text
        .split(RegExp('[^a-z0-9 ]'))
        .join(' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    for (final entry in _aliases.entries) {
      if (text.contains(entry.key) && entry.value.isNotEmpty) {
        classes.addAll(entry.value);
      }
    }

    for (final cls in _classes) {
      final hits = cls.contains(' ')
          ? text.contains(cls)
          : words.any((w) => _singular(w) == cls);
      if (hits) classes.add(cls);
    }
    return classes.toList();
  }

  static String _singular(String word) =>
      word.length > 1 && word.endsWith('s')
          ? word.substring(0, word.length - 1)
          : word;

  static String _displayForUnknownQuery(String cls, String original) {
    final words = original
        .toLowerCase()
        .split(RegExp('[^a-z0-9 ]'))
        .join(' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    for (final w in words) {
      if (w.startsWith(cls) || cls.startsWith(w)) return w;
    }
    return cls;
  }

  /// Reset all state (e.g. when leaving the screen). Current scene is kept so
  /// late queries still show the last observation; tracking is cleared.
  void reset() {
    _tracks.clear();
    _lastAnnounceAt = null;
    _lastAnnouncement = '';
    _lastResponse = '';
    _lastTopicClass = null;
    _current = const [];
    notifyListeners();
  }
}