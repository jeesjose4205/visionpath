import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/services/speech_queue.dart';

void main() {
  group('speech queue: ordering', () {
    test('starts idle with nothing pending', () {
      final SpeechQueue queue = SpeechQueue();
      expect(queue.state, SpeechState.idle);
      expect(queue.isSpeaking, isFalse);
      expect(queue.hasPending, isFalse);
      expect(queue.pendingCount, 0);
      expect(queue.takeNext(), isNull);
    });

    test('sentences leave the queue in the order they arrived', () {
      final SpeechQueue queue = SpeechQueue();
      queue.add('Person detected, 1.8 meters ahead.');
      queue.add('Chair detected, 2.4 meters to your left.');
      queue.add('Table detected, 3.1 meters ahead.');

      expect(queue.state, SpeechState.queued);
      expect(queue.pendingCount, 3);
      expect(queue.takeNext(), 'Person detected, 1.8 meters ahead.');
      expect(queue.takeNext(), 'Chair detected, 2.4 meters to your left.');
      expect(queue.takeNext(), 'Table detected, 3.1 meters ahead.');
      expect(queue.takeNext(), isNull);
    });

    test('one sentence at a time, waiting for completion', () {
      final SpeechQueue queue = SpeechQueue();
      queue.add('first');
      queue.add('second');

      expect(queue.takeNext(), 'first');
      expect(queue.state, SpeechState.speaking);
      expect(queue.activeSentence, 'first');

      // Second is still waiting; it must not start before the first finishes.
      expect(queue.pending, ['second']);

      queue.finishCurrent();
      expect(queue.state, SpeechState.queued);
      expect(queue.takeNext(), 'second');
      queue.finishCurrent();

      expect(queue.state, SpeechState.idle);
      expect(queue.hasPending, isFalse);
    });

    test('finishing twice is harmless', () {
      final SpeechQueue queue = SpeechQueue();
      queue.add('only');
      queue.takeNext();
      queue.finishCurrent();
      queue.finishCurrent();
      expect(queue.state, SpeechState.idle);
      expect(queue.isSpeaking, isFalse);
      expect(queue.activeSentence, isNull);
    });
  });

  group('speech queue: duplicate protection', () {
    test('the same sentence is never queued twice', () {
      final SpeechQueue queue = SpeechQueue();
      const String sentence = 'Person detected, 2.1 meters ahead.';

      expect(queue.add(sentence), isTrue);
      for (int frame = 0; frame < 100; frame++) {
        expect(queue.add(sentence), isFalse, reason: 'frame $frame');
      }
      expect(queue.pendingCount, 1);
      expect(queue.pending, [sentence]);
    });

    test('a sentence being spoken is not queued again', () {
      final SpeechQueue queue = SpeechQueue();
      const String sentence = 'Chair detected, 2.4 meters to your left.';

      expect(queue.add(sentence), isTrue);
      expect(queue.takeNext(), sentence);
      expect(queue.state, SpeechState.speaking);

      // Same frame again while it is still playing.
      expect(queue.add(sentence), isFalse);
      expect(queue.pendingCount, 0);
    });

    test('a sentence may be queued again once it finished', () {
      final SpeechQueue queue = SpeechQueue();
      const String sentence = 'Table detected, 2.2 meters ahead.';
      queue.add(sentence);
      queue.takeNext();
      queue.finishCurrent();
      expect(queue.add(sentence), isTrue);
    });

    test('the queue keeps distinct sentences in order, without duplicates',
        () {
      final SpeechQueue queue = SpeechQueue();
      final List<String> sentences = [
        'Person detected, 2.1 meters ahead.',
        'Chair detected, 2.8 meters to your left.',
      ];
      // The detector generates the same two sentences on many frames.
      for (int frame = 0; frame < 20; frame++) {
        for (final String s in sentences) {
          queue.add(s);
        }
      }
      expect(queue.pending, sentences);
    });

    test('blank sentences are rejected', () {
      final SpeechQueue queue = SpeechQueue();
      expect(queue.add(''), isFalse);
      expect(queue.add('   '), isFalse);
      expect(queue.pendingCount, 0);
    });

    test('a re-queued sentence is not blocked by a stale duplicate marker', () {
      final SpeechQueue queue = SpeechQueue();
      const String sentence = 'Bottle detected, 0.4 meters ahead.';
      queue.add(sentence);
      expect(queue.takeNext(), sentence);
      expect(queue.pendingCount, 0);
      // Still speaking: refused.
      expect(queue.add(sentence), isFalse);
      queue.finishCurrent();
      // Finished: allowed again (the object moved and came back).
      expect(queue.add(sentence), isTrue);
    });
  });

  group('speech queue: lifecycle', () {
    test('clear drops everything pending', () {
      final SpeechQueue queue = SpeechQueue();
      queue.add('a');
      queue.add('b');
      queue.takeNext();
      queue.add('c');

      queue.clear();

      expect(queue.state, SpeechState.idle);
      expect(queue.pendingCount, 0);
      expect(queue.pending, isEmpty);
      expect(queue.activeSentence, isNull);
    });

    test('after clear the same sentence can be queued again', () {
      final SpeechQueue queue = SpeechQueue();
      const String sentence = 'Person detected, 1.5 meters ahead.';
      queue.add(sentence);
      queue.clear();
      expect(queue.add(sentence), isTrue);
    });

    test('the pending snapshot cannot be mutated from outside', () {
      final SpeechQueue queue = SpeechQueue();
      queue.add('a');
      expect(() => queue.pending.add('b'), throwsUnsupportedError);
    });
  });

  group('speech queue: camera frame simulation', () {
    test('100 identical frames produce exactly one queued sentence', () {
      final SpeechQueue queue = SpeechQueue();
      for (int frame = 0; frame < 100; frame++) {
        queue.add('Person detected, 2.1 meters ahead.');
      }
      expect(queue.pendingCount, 1);
    });

    test('one meaningful change adds exactly one more sentence', () {
      final SpeechQueue queue = SpeechQueue();
      const String before = 'Person detected, 2.1 meters ahead.';
      const String after = 'Person detected, 1.6 meters ahead.';

      // Unchanged frames: nothing new.
      for (int frame = 0; frame < 40; frame++) {
        queue.add(before);
      }
      expect(queue.pending, [before]);

      // The person walked closer: one new sentence, the old one is playing.
      expect(queue.takeNext(), before);
      expect(queue.add(after), isTrue);
      expect(queue.pending, [after]);
    });

    test('a closing hazard flushes the pending queue and speaks now', () {
      final SpeechQueue queue = SpeechQueue();
      queue.add('Chair detected, 2.8 meters to your left.');
      queue.takeNext();
      queue.add('Table detected, 3.2 meters to your right.');

      // Urgent warning takes over: everything waiting is dropped.
      queue.clear();
      expect(queue.state, SpeechState.idle);

      expect(queue.add('Stop. Person very close.'), isTrue);
      expect(queue.pending, ['Stop. Person very close.']);
    });
  });
}