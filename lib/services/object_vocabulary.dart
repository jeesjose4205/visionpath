/// The single source of truth for the object names VisionPath understands.
///
/// The detection model is a COCO-80 YOLO model, so an object can only ever be
/// described to the user when its name is in [supportedClasses]. Everything
/// that turns free speech into an object name (the Look & Detect assistant and
/// Target Object Navigation) resolves words through this catalog, which is why
/// the two features can never disagree about what the model is able to see.
class ObjectVocabulary {
  ObjectVocabulary._();

  /// The YOLO class names the app currently understands, used both for
  /// matching query words and as a safety net against inventing classes.
  static const List<String> supportedClasses = [
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
  /// An empty list marks a word people ask about that the model cannot see.
  static const Map<String, List<String>> aliases = {
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

  /// Naive singularization, matching the behaviour the assistant already used.
  static String singular(String word) =>
      word.length > 1 && word.endsWith('s')
          ? word.substring(0, word.length - 1)
          : word;

  /// Whether [className] (as reported by the model) is one the model can see.
  static bool isSupported(String className) =>
      supportedClasses.contains(className.toLowerCase());

  /// Normalizes free text into lowercase word tokens.
  static List<String> tokenize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9 ]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();

  /// Extracts the YOLO classes a free-form question is asking about (empty when
  /// the user is not asking about a specific object). Never matches words that
  /// look like an object but are not in the class list, so the assistant
  /// cannot claim to find a door that the model cannot see.
  static List<String> extractClasses(String text) {
    final classes = <String>{};
    final words = tokenize(text);

    for (final entry in aliases.entries) {
      if (text.contains(entry.key) && entry.value.isNotEmpty) {
        classes.addAll(entry.value);
      }
    }

    for (final cls in supportedClasses) {
      final hits = cls.contains(' ')
          ? text.contains(cls)
          : words.any((w) => singular(w) == cls);
      if (hits) classes.add(cls);
    }
    return classes.toList();
  }

  /// Resolves a cleaned target phrase ("dining table", "the sofa") to the
  /// canonical YOLO class names it can mean.
  ///
  /// Multi-word classes are matched first and win outright, so "hot dog"
  /// resolves to `hot dog` and never also to `dog`, while "red chair" still
  /// falls through to the single word. Returns an empty list when the phrase
  /// names something the model cannot detect.
  static List<String> resolvePhrase(String phrase) {
    final words = tokenize(phrase);
    if (words.isEmpty) return const [];

    for (int take = 3; take >= 2; take--) {
      final List<String> resolved = <String>[];
      for (int i = 0; i + take <= words.length; i++) {
        resolved.addAll(
          _match(words.sublist(i, i + take).join(' ')),
        );
      }
      if (resolved.isNotEmpty) return resolved;
    }

    final List<String> single = <String>[];
    for (final word in words) {
      single.addAll(_match(word));
    }
    return single;
  }

  static List<String> _match(String candidate) {
    final key = singular(candidate);
    for (final cls in supportedClasses) {
      if (cls == candidate || (!cls.contains(' ') && key == cls)) {
        return <String>[cls];
      }
    }
    for (final entry in aliases.entries) {
      if (entry.key == candidate || singular(entry.key) == key) {
        return entry.value;
      }
    }
    return const [];
  }
}
