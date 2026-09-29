import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visionpath/services/visora/visora_config.dart';
import 'package:visionpath/services/visora/visora_llm_client.dart';
import 'package:visionpath/services/visora/visora_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('VisoraConfig', () {
    test('starts without a backend', () async {
      final cfg = VisoraConfig.instance;
      await cfg.load();
      expect(cfg.hasBackend, isFalse);
      expect(cfg.wakeWordEnabled, isTrue);
      expect(cfg.voiceOutputEnabled, isTrue);
    });

    test('persists endpoint + key and reports a connected backend', () async {
      final cfg = VisoraConfig.instance;
      await cfg.load();
      await cfg.setEndpoint('https://api.example.com/v1/chat/completions');
      await cfg.setApiKey('secret-token');
      await cfg.setModel('gpt-4o-mini');
      expect(cfg.hasBackend, isTrue);

      // A fresh load from the mock store must restore the same values.
      final reloaded = VisoraConfig.instance;
      await reloaded.load();
      expect(reloaded.endpoint, 'https://api.example.com/v1/chat/completions');
      expect(reloaded.apiKey, 'secret-token');
      expect(reloaded.model, 'gpt-4o-mini');
      expect(reloaded.hasBackend, isTrue);
    });

    test('clearing credentials drops back to offline mode', () async {
      final cfg = VisoraConfig.instance;
      await cfg.load();
      await cfg.setEndpoint('https://api.example.com');
      await cfg.setApiKey('x');
      expect(cfg.hasBackend, isTrue);
      await cfg.setApiKey('');
      expect(cfg.hasBackend, isFalse);
    });
  });

  group('VisoraLlmClient offline engine', () {
    test('answers machine-learning questions offline', () async {
      final client = VisoraLlmClient();
      final answer = await client.generate(const [
        {'role': 'user', 'content': 'Explain machine learning'},
      ]);
      expect(answer.isOffline, isTrue);
      expect(answer.text.toLowerCase(), contains('machine learning'));
    });

    test('replies to greetings', () async {
      final client = VisoraLlmClient();
      final answer = await client.generate(const [
        {'role': 'user', 'content': 'Hi Visora'},
      ]);
      expect(answer.text.toLowerCase(), contains('visora'));
    });

    test('explains what Visora can do', () async {
      final client = VisoraLlmClient();
      final answer = await client.generate(const [
        {'role': 'user', 'content': 'What can you do?'},
      ]);
      expect(answer.text.toLowerCase(), contains('assistant'));
    });

    test('streams deltas that reassemble into the final answer', () async {
      final client = VisoraLlmClient();
      final buffer = StringBuffer();
      final answer = await client.generate(
        const [
          {'role': 'user', 'content': 'Tell me about quantum computing'},
        ],
        onDelta: (delta) => buffer.write(delta),
      );
      expect(buffer.toString(), answer.text);
      expect(buffer.toString(), isNotEmpty);
    });

    test('asks for input when nothing was actually asked', () async {
      final client = VisoraLlmClient();
      final answer = await client.generate(const [
        {'role': 'user', 'content': '   '},
      ]);
      expect(answer.text, isNotEmpty);
    });
  });

  group('VisoraLlmClient.endpointUri', () {
    test('appends /chat/completions to a base URL', () {
      expect(
        VisoraLlmClient.endpointUri('https://api.example.com/v1').toString(),
        'https://api.example.com/v1/chat/completions',
      );
    });

    test('never appends /chat/completions twice', () {
      expect(
        VisoraLlmClient.endpointUri('https://api.example.com/v1/chat/completions')
            .toString(),
        'https://api.example.com/v1/chat/completions',
      );
    });

    test('tolerates a trailing slash and the completions suffix duplicated', () {
      expect(
        VisoraLlmClient.endpointUri('https://api.example.com/v1/chat/completions/')
            .toString(),
        'https://api.example.com/v1/chat/completions',
      );
    });
  });

  group('VisoraLlmClient.modelsUri', () {
    test('derives /models from a full chat-completions endpoint', () {
      expect(
        VisoraLlmClient.modelsUri('https://api.groq.com/openai/v1/chat/completions')
            .toString(),
        'https://api.groq.com/openai/v1/models',
      );
    });

    test('derives /models from a base URL', () {
      expect(
        VisoraLlmClient.modelsUri('https://api.example.com/v1').toString(),
        'https://api.example.com/v1/models',
      );
    });

    test('never appends /models twice', () {
      expect(
        VisoraLlmClient.modelsUri('https://api.example.com/v1/models')
            .toString(),
        'https://api.example.com/v1/models',
      );
    });

    test('tolerates a trailing slash', () {
      expect(
        VisoraLlmClient.modelsUri('https://api.example.com/v1/chat/completions/')
            .toString(),
        'https://api.example.com/v1/models',
      );
    });
  });

  group('VisoraLlmClient model discovery', () {
    const groqModelsBody = '''
{
  "object": "list",
  "data": [
    {"id": "llama-3.3-70b-versatile", "object": "model", "owned_by": "groq", "active": true, "context_window": 131072},
    {"id": "whisper-large-v3", "object": "model", "owned_by": "groq", "active": true},
    {"id": "nomic-embed-text-v1.5", "object": "model", "owned_by": "groq", "active": true},
    {"id": "retired-model", "object": "model", "owned_by": "groq", "active": false}
  ]
}
''';

    test('parses a provider /models response preserving metadata', () {
      final models = VisoraLlmClient.parseModels(groqModelsBody);
      expect(models, hasLength(4));
      final llama = models.firstWhere((m) => m.id == 'llama-3.3-70b-versatile');
      expect(llama.active, isTrue);
      expect(llama.contextWindow, 131072);
      final retired =
          models.firstWhere((m) => m.id == 'retired-model');
      expect(retired.active, isFalse);
    });

    test('filters to active chat models only (no embed/whisper/tts)', () {
      final chat = VisoraLlmClient.chatModels(
        VisoraLlmClient.parseModels(groqModelsBody),
      );
      expect(chat.map((m) => m.id), ['llama-3.3-70b-versatile']);
    });

    test('prefers a configured model when it is still available', () {
      final models = VisoraLlmClient.parseModels(groqModelsBody);
      expect(
        VisoraLlmClient.chooseChatModel(models, preferred: 'nope')!.id,
        'llama-3.3-70b-versatile',
      );
      expect(
        VisoraLlmClient.chooseChatModel(
          [...models, const VisoraModelInfo(id: 'other-model')],
          preferred: 'other-model',
        )!.id,
        'other-model',
      );
    });

    test('returns null when no chat-suitable model exists', () {
      expect(
        VisoraLlmClient.chooseChatModel(const [
          VisoraModelInfo(id: 'nomic-embed-text-v1.5'),
          VisoraModelInfo(id: 'retired-tts', active: false),
        ]),
        isNull,
      );
    });

    test('malformed model payloads yield an empty list', () {
      expect(VisoraLlmClient.parseModels('not json'), isEmpty);
      expect(VisoraLlmClient.parseModels('{"data":"nope"}'), isEmpty);
      expect(VisoraLlmClient.parseModels('{}'), isEmpty);
    });
  });

  group('VisoraConfig available models', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('tracks available models and retires unavailable ones', () async {
      final cfg = VisoraConfig.instance;
      await cfg.load();
      cfg.setAvailableModels(['a', 'b', 'c']);
      expect(cfg.availableModels, ['a', 'b', 'c']);
      cfg.markModelUnavailable('b');
      expect(cfg.availableModels, ['a', 'c']);
      expect(cfg.isModelAvailable('a'), isTrue);
      expect(cfg.isModelAvailable('b'), isFalse);
    });

    test('marking an unknown model unavailable is a no-op', () async {
      final cfg = VisoraConfig.instance;
      await cfg.load();
      cfg.setAvailableModels(['a']);
      cfg.markModelUnavailable('ghost');
      expect(cfg.availableModels, ['a']);
    });

    test('endpoint changes clear the discovered models', () async {
      final cfg = VisoraConfig.instance;
      await cfg.load();
      cfg.setAvailableModels(['a']);
      await cfg.setEndpoint('https://api.example.com/v1');
      expect(cfg.availableModels, isEmpty);
    });
  });

  group('VisoraLlmClient.sanitizeText', () {
    test('preserves normal text and astral emoji', () {
      const wave = '👋';
      final s = 'Hello $wave';
      expect(VisoraLlmClient.sanitizeText(s), s);
    });

    test('strips lone surrogates that break encoding', () {
      final lone = String.fromCharCodes([0xD800, 0x61, 0xDFFF]);
      expect(VisoraLlmClient.sanitizeText(lone), 'a');
    });
  });

  group('VisoraLlmClient.consumeSse', () {
    // A realistic Groq-style SSE body containing a raw multi-byte character
    // ('é' = UTF-8 0xC3 0xA9) inside a delta.
    late List<int> raw;
    late int eA9; // byte index of the low byte of 'é'

    setUp(() {
      raw = utf8.encode(
        'data: {"id":"1","choices":[{"delta":{"content":"Hello"}}]}\r\n'
        'data: {"id":"2","choices":[{"delta":{"content":" é"}}]}\r\n'
        'data: [DONE]\r\n'
        '\r\n',
      );
      eA9 = -1;
      for (var i = 0; i + 1 < raw.length; i++) {
        if (raw[i] == 0xC3 && raw[i + 1] == 0xA9) {
          eA9 = i + 1;
          break;
        }
      }
    });

    test('reassembles events split across arbitrary chunk boundaries', () async {
      final client = VisoraLlmClient();
      // Slices at odd points: one cut lands *inside* a `data:` line and another
      // lands *between* the two bytes of 'é'.
      final stream = Stream.fromIterable([
        raw.sublist(0, 5),
        raw.sublist(5, 34),
        raw.sublist(34, eA9),
        raw.sublist(eA9, eA9 + 1),
        raw.sublist(eA9 + 1),
      ]);
      final deltas = <String>[];
      final text = await client.consumeSse(stream, onDelta: deltas.add);
      expect(text, 'Hello é');
      expect(deltas.join(), 'Hello é');
    });

    test('handles the final unterminated tail', () async {
      final client = VisoraLlmClient();
      final tail =
          utf8.encode('data: {"choices":[{"delta":{"content":"!"}}]}');
      final text = await client.consumeSse(Stream.fromIterable([tail]));
      expect(text, '!');
    });

    test('ignores blank lines, comments and [DONE]', () async {
      final client = VisoraLlmClient();
      final stream = Stream.fromIterable([
        utf8.encode(': keep-alive-comment\r\n\r\n'),
        utf8.encode('data: [DONE]\r\n\r\n'),
      ]);
      final text = await client.consumeSse(stream);
      expect(text, isEmpty);
    });

    test('aborts cleanly when cancelled mid-stream', () async {
      final client = VisoraLlmClient();
      final controller = VisoraRequestController();
      final sc = StreamController<List<int>>();
      final deltas = <String>[];
      final future = client.consumeSse(
        sc.stream,
        onDelta: deltas.add,
        controller: controller,
      );

      sc.add(utf8.encode('data: {"choices":[{"delta":{"content":"Hello"}}]}\n\n'));
      // Let the first chunk be consumed, then cancel before the second.
      await Future<void>.delayed(Duration.zero);
      controller.cancel();
      sc.add(utf8.encode('data: {"choices":[{"delta":{"content":" World"}}]}\n\n'));
      await sc.close();

      final text = await future;
      expect(text, 'Hello');
      expect(deltas, ['Hello']);
    });
  });

  group('VisoraRequestController', () {
    test('cancels exactly once', () {
      final controller = VisoraRequestController();
      expect(controller.isCancelled, isFalse);
      controller.cancel();
      expect(controller.isCancelled, isTrue);
      controller.cancel();
      expect(controller.isCancelled, isTrue);
    });
  });

  group('VisoraSession multi-turn', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('preserves context: 3 questions -> 6 alternating messages, no errors',
        () async {
      final cfg = VisoraConfig.instance;
      await cfg.load();
      await cfg.setVoiceOutputEnabled(false); // offline + mute TTS in tests.

      final session = VisoraSession.instance;
      session.open();
      try {
        await session.handleUserMessage('Hello Visora');
        await session.handleUserMessage('What can you do?');
        await session.handleUserMessage('Explain artificial intelligence');

        final msgs = session.messages;
        expect(msgs, hasLength(6));
        for (var i = 0; i < msgs.length; i++) {
          expect(msgs[i].role, i.isEven ? 'user' : 'assistant');
          expect(msgs[i].isError, isFalse);
          expect(msgs[i].text, isNot(contains('could not reach')));
        }
        expect(msgs[0].text, 'Hello Visora');
        expect(msgs[2].text, 'What can you do?');
        expect(msgs[4].text, 'Explain artificial intelligence');
        expect(msgs[1].text.toLowerCase(), contains('visora'));
        expect(msgs[3].text.toLowerCase(), contains('assistant'));
        expect(msgs[5].text.toLowerCase(), contains('artificial intelligence'));
      } finally {
        await session.close();
      }
    });
  });
}