import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'visora_config.dart';

/// Minimal OpenAI-compatible chat-completions client for Visora.
///
/// Speaks to any `POST /chat/completions` endpoint that supports SSE
/// streaming (`stream: true`), accumulating `choices[0].delta.content` chunks
/// as they arrive so the UI can progressively render text. Built on
/// `dart:io` [HttpClient] so no new dependencies are needed.
///
/// Also discovers the provider's model catalog via `GET /models` so the
/// settings screen can offer a live dropdown of currently available models.
/// Obsolete model IDs are never hard-coded; the list always comes from the
/// configured provider at runtime.
///
/// When no backend is configured (no endpoint/key), [generate] falls back to a
/// small bundled offline answer engine so the assistant always responds.
class VisoraLlmClient {
  /// Monotonic request ID for correlating concurrent requests in DEBUG logs.
  static int _nextRequestId = 0;

  /// Stream the response for [messages]. [onDelta] is invoked with each text
  /// chunk as it arrives. Returns the fully accumulated answer, including the
  /// HTTP status observed (or null when the answer came from the offline
  /// engine or a pre-HTTP network failure).
  ///
  /// Every call builds a **fresh** HTTP request on a **fresh** [HttpClient] and
  /// a **fresh** local response buffer — no stream, connection or buffer is
  /// ever reused between turns. If [controller] is provided, [VisoraRequestController.cancel]
  /// aborts this request cleanly so a newer request can supersede it.
  Future<VisoraAnswer> generate(
    List<Map<String, String>> messages, {
    void Function(String delta)? onDelta,
    VisoraRequestController? controller,
  }) async {
    final requestId = ++_nextRequestId;
    final config = VisoraConfig.instance;
    if (!config.hasBackend) {
      return _offlineAnswer(messages, onDelta,
          controller: controller, requestId: requestId);
    }

    final Uri uri;
    try {
      uri = endpointUri(config.endpoint);
    } catch (e) {
      _debugLog('Visora request: invalid endpoint "${config.endpoint}"');
      return const VisoraAnswer(
        'The AI service endpoint in Visora settings is not a valid URL.',
        isError: true,
      );
    }
    _debugLog('Visora REQUEST START id=$requestId ${_preview(uri.toString())}');
    _debugLog('Visora conversation message count: ${messages.length}');
    for (var i = 0; i < messages.length; i++) {
      _debugLog('Visora message $i role=${messages[i]['role']}');
    }
    final lastUser = messages.isEmpty ? '' : messages.last['content'] ?? '';
    _debugLog('Visora REQUEST id=$requestId user="${_preview(lastUser)}"');

    final body = jsonEncode({
      'model': config.model.isEmpty ? 'gpt-4o-mini' : config.model,
      // Sanitize every message before encoding: a lone surrogate in history
      // would make utf8.encode throw "Contains invalid characters.".
      'messages': [
        for (final m in messages)
          {
            'role': m['role'],
            'content': sanitizeText(m['content'] ?? ''),
          },
      ],
      'stream': true,
    });
    _debugLog('Visora request: model="${config.model.isEmpty ? 'gpt-4o-mini' : config.model}"');
    // The body holds only messages; never log the API key.
    _debugLog('Visora request body: $body');

    // Transient conditions worth one transparent retry on a fresh connection:
    // HTTP 408/429/5xx, a transport error before any content streamed, or a
    // 200 with no content. A mid-stream reset AFTER content has already
    // streamed is not retried (the partial text was already shown live).
    var result = const _ChatAttempt(VisoraAnswer('', isError: true));
    for (var attempt = 1; attempt <= _kMaxAttempts; attempt++) {
      if (controller?.isCancelled ?? false) {
        return const VisoraAnswer('', isError: true);
      }
      if (attempt > 1) {
        _debugLog('Visora REQUEST RETRY id=$requestId attempt=$attempt');
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (controller?.isCancelled ?? false) {
          return const VisoraAnswer('', isError: true);
        }
      }
      result = await _chatOnce(
        uri,
        body,
        onDelta,
        controller: controller,
        requestId: requestId,
        attempt: attempt,
      );
      if (!result.canRetry) break;
    }
    if (controller?.isCancelled ?? false) {
      return const VisoraAnswer('', isError: true);
    }
    return result.answer;
  }

  static const int _kMaxAttempts = 2;

  /// Execute one HTTP POST; [canRetry] is true only for cleanly transient
  /// failures (see caller). Each attempt owns a fresh [HttpClient], request and
  /// response buffer, plus a read-stall watchdog so a dead connection can't
  /// hang the assistant.
  Future<_ChatAttempt> _chatOnce(
    Uri uri,
    String body,
    void Function(String)? onDelta, {
    required VisoraRequestController? controller,
    required int requestId,
    required int attempt,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..userAgent = 'VisionPath-Visora/1.0';

    // Wiring a cancel closes the socket client, force-terminating the SSE
    // read; any socket error it raises is mapped back to "cancelled".
    controller?._attach(() {
      try {
        client.close(force: true);
      } catch (_) {}
    });

    Timer? watchdog;
    void resetWatchdog() {
      watchdog?.cancel();
      watchdog = Timer(const Duration(seconds: 60), () {
        _debugLog('Visora SSE id=$requestId stalled; aborting');
        try {
          client.close(force: true);
        } catch (_) {}
      });
    }

    // Counts chars actually flushed to the session this attempt. If a set
    // resets mid-stream AFTER content, we treat it as real (no retry) so live
    // partial text is never replayed twice from a retry.
    var flushed = 0;

    try {
      if (controller?.isCancelled ?? false) {
        return const _ChatAttempt(VisoraAnswer('', isError: true));
      }
      final request = await client.postUrl(uri);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      // Never print the Authorization header value (it carries the API key).
      final key = _normalizeKey(VisoraConfig.instance.apiKey);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      request.write(body);

      final response = await request.close();
      _debugLog('Visora response id=$requestId (attempt $attempt): HTTP ${response.statusCode}');
      _debugLog('Groq chat response id=$requestId (attempt $attempt): HTTP ${response.statusCode}');

      if (response.statusCode != 200) {
        final errorBody = await _readBody(response);
        _debugLog('Visora response body id=$requestId: $errorBody');
        if (response.statusCode == 404) {
          // Endpoint says this model does not exist — retire it so we never
          // keep hammering it (and never auto-select it again).
          final cfg = VisoraConfig.instance;
          if (cfg.model.isNotEmpty) cfg.markModelUnavailable(cfg.model);
        }
        final answer = VisoraAnswer(
          'The AI service returned HTTP ${response.statusCode}. '
          'Check the endpoint, API key and model in Visora settings.',
          isError: true,
          statusCode: response.statusCode,
        );
        return _ChatAttempt(answer, canRetry: _isTransientStatus(response.statusCode));
      }

      if (controller?.isCancelled ?? false) {
        return const _ChatAttempt(VisoraAnswer('', isError: true));
      }
      final text = await _streamSse(
        response,
        (delta) {
          flushed += delta.length;
          onDelta?.call(delta);
        },
        controller: controller,
        requestId: requestId,
        onChunk: resetWatchdog,
      );
      watchdog?.cancel();
      if (controller?.isCancelled ?? false) {
        return const _ChatAttempt(VisoraAnswer('', isError: true));
      }
      if (text.isEmpty) {
        return const _ChatAttempt(
          VisoraAnswer(
            'The AI returned no answer. Please try again.',
            isError: true,
            statusCode: 200,
          ),
          canRetry: true,
        );
      }
      _debugLog(
        'Visora REQUEST SUCCESS id=$requestId http=200 len=${text.length}',
      );
      return _ChatAttempt(VisoraAnswer(text, statusCode: 200));
    } catch (e) {
      // A deliberate cancellation is not a real error — stay quiet so the
      // superseding request owns the UI.
      if (controller?.isCancelled ?? false) {
        return const _ChatAttempt(VisoraAnswer('', isError: true));
      }
      _debugLog('Visora REQUEST END id=$requestId (attempt $attempt) error: $e');
      // Content already streamed live is not retried (deliberately — see the
      // "flushed" doc above), so the live partial text is never replayed.
      // A transport error before anything streamed is retried on a fresh
      // connection.
      return _ChatAttempt(
        const VisoraAnswer(
          'I could not reach the AI service right now. Check your Visora '
          'settings and your internet connection, then try again.',
          isError: true,
        ),
        canRetry: flushed == 0,
      );
    } finally {
      watchdog?.cancel();
      controller?._detach();
      _debugLog('Visora REQUEST END id=$requestId (attempt $attempt)');
      client.close(force: true);
    }
  }

  bool _isTransientStatus(int status) =>
      status == 408 || status == 429 ||
      (status >= 500 && status <= 504);

  /// Fetch the provider's current model catalog from `GET /models`.
  ///
  /// Returns model metadata (including the `active` flag and `context_window`
  /// when the provider reports them). The API key is sent as the bearer token
  /// and is never logged. On any failure an empty list is returned and the
  /// reason is logged in DEBUG builds.
  Future<List<VisoraModelInfo>> fetchModels() async {
    final config = VisoraConfig.instance;
    if (!config.hasBackend) return const [];

    final Uri uri;
    try {
      uri = modelsUri(config.endpoint);
    } catch (e) {
      _debugLog('Groq models request: invalid endpoint "${config.endpoint}"');
      return const [];
    }
    _debugLog('Groq models request: GET $uri');

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = 'VisionPath-Visora/1.0';

    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${_normalizeKey(config.apiKey)}',
      );
      final response = await request.close();
      _debugLog('Groq models request: HTTP ${response.statusCode}');
      if (response.statusCode != 200) {
        final errorBody = await _readBody(response);
        _debugLog('Groq models response body: $errorBody');
        return const [];
      }
      final body = await response.transform(const Utf8Decoder()).join();
      final models = parseModels(body);
      _debugLog('Available Groq models: ${models.map((m) => m.id).join(', ')}');
      return models;
    } catch (e) {
      _debugLog('Groq models request error: $e');
      return const [];
    } finally {
      client.close(force: true);
    }
  }

  /// Resolve the stored endpoint to a full `/chat/completions` URL.
  ///
  /// Accepts a base URL (`https://api.example.com/v1`) and appends the
  /// completion path, and also accepts the full URL already ending in
  /// `/chat/completions` — the path is never appended twice.
  static Uri endpointUri(String endpoint) {
    var url = endpoint.trim();
    // Any trailing slashes first, so ".../chat/completions/" is detected.
    url = url.replaceFirst(RegExp(r'/+$'), '');
    const suffix = '/chat/completions';
    if (!url.toLowerCase().endsWith(suffix)) {
      url = '$url$suffix';
    }
    return Uri.parse(url);
  }

  /// Resolve the stored endpoint to the provider's `GET /models` URL.
  ///
  /// Derives the models list endpoint from the configured chat-completions
  /// endpoint (e.g. `…/v1/chat/completions` → `…/v1/models`), and never
  /// appends `/models` twice.
  static Uri modelsUri(String endpoint) {
    var url = endpoint.trim().replaceFirst(RegExp(r'/+$'), '');
    const chatSuffix = '/chat/completions';
    if (url.toLowerCase().endsWith(chatSuffix)) {
      url = url
          .substring(0, url.length - chatSuffix.length)
          .replaceFirst(RegExp(r'/+$'), '');
    }
    const modelsSuffix = '/models';
    if (url.toLowerCase().endsWith(modelsSuffix)) return Uri.parse(url);
    return Uri.parse('$url$modelsSuffix');
  }

  /// Parse an OpenAI-compatible `GET /models` JSON body.
  ///
  /// Preserves provider metadata (`active`, `context_window`) when present.
  /// Malformed or unexpected shapes yield an empty list rather than throwing.
  static List<VisoraModelInfo> parseModels(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return const [];
      final data = decoded['data'];
      if (data is! List) return const [];
      final result = <VisoraModelInfo>[];
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final id = item['id'];
        if (id is! String || id.trim().isEmpty) continue;
        final activeValue = item['active'];
        final active = activeValue is bool ? activeValue : true;
        final ctx = item['context_window'];
        result.add(
          VisoraModelInfo(
            id: id.trim(),
            active: active,
            contextWindow: ctx is num ? ctx.toInt() : null,
          ),
        );
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  /// All model IDs from [models] that look usable for chat/completions (the
  /// provider's `/models` list includes non-chat entries such as embeddings).
  static List<VisoraModelInfo> chatModels(List<VisoraModelInfo> models) =>
      models.where(isChatSuitable).toList();

  /// Select the model to use: [preferred] when it is available and suitable,
  /// otherwise the first suitable chat model, otherwise `null` (no models).
  static VisoraModelInfo? chooseChatModel(
    List<VisoraModelInfo> models, {
    String? preferred,
  }) {
    final suitable = models.where(isChatSuitable).toList();
    if (suitable.isEmpty) return null;
    if (preferred != null) {
      for (final model in suitable) {
        if (model.id == preferred) return model;
      }
    }
    return suitable.first;
  }

/// A model is usable for chat when the provider marks it `active` and its ID
/// does not indicate a non-chat kind. The `/models` endpoint does not expose
/// capabilities, so the known non-chat families (embeddings, transcription /
/// TTS audio models) are excluded by ID — everything else is offered.
  static bool isChatSuitable(VisoraModelInfo model) {
    if (!model.active) return false;
    final id = model.id.toLowerCase();
    if (id.contains('embed')) return false;
    if (id.contains('whisper')) return false;
    if (id.contains('tts')) return false;
    return true;
  }

  static String _normalizeKey(String apiKey) {
    final key = apiKey.trim();
    if (key.toLowerCase().startsWith('bearer ')) {
      return key.substring(7).trim();
    }
    return key;
  }

  /// Return [text] with invalid characters removed.
  ///
  /// A lone (unpaired) UTF-16 surrogate is rejected by Dart's strict
  /// `String`/charset validation with exactly:
  ///   `Invalid argument (string): Contains invalid characters.`
  /// (thrown by `String.fromCharCodes`, `utf8.encode`, etc.). Such code units
  /// could enter the pipeline from JSON payloads using `\udxxx` escapes or bad
  /// transcriptions, so every string that goes into an outgoing request body,
  /// the conversation history, the UI or TTS is scrubbed here. Valid surrogate
  /// pairs (astral emoji etc.) are preserved.
  static String sanitizeText(String text) {
    var hasLone = false;
    for (final unit in text.codeUnits) {
      if (unit >= 0xD800 && unit <= 0xDFFF) {
        hasLone = true;
        break;
      }
    }
    if (!hasLone) return text;
    final out = StringBuffer();
    for (final codePoint in text.runes) {
      if (codePoint >= 0xD800 && codePoint <= 0xDFFF) continue;
      out.writeCharCode(codePoint);
    }
    return out.toString();
  }

  /// Short preview of [s] for DEBUG logs (the API key never reaches here).
  static String _preview(String s) {
    if (s.length <= 200) return s;
    return '${s.substring(0, 200)}… (${s.length} chars)';
  }

  Future<String> _readBody(HttpClientResponse response) async {
    try {
      return await response.transform(const Utf8Decoder()).join();
    } catch (_) {
      return '';
    }
  }

  /// Consume a raw HTTP byte stream as Server-Sent Events (SSE) and return the
  /// accumulated assistant text.
  ///
  /// The response stream is read as **bytes**, never as raw text: chunks are
  /// appended to a persistent byte buffer, complete lines (terminated by
  /// `\n`) are extracted one at a time, and only complete lines are UTF-8
  /// decoded. An SSE event's `data:` payload is JSON-decoded on its own — raw
  /// SSE markup is never handed to a JSON decoder, and `data: [DONE]` is
  /// ignored. Content split across network chunks (or a multibyte character
  /// split across chunks) is reassembled by buffering until a line terminator
  /// arrives, and the final leftover bytes are handled when the stream ends.
  ///
  /// Every non-empty extracted content chunk is forwarded to [onDelta].
  Future<String> _streamSse(
    HttpClientResponse response,
    void Function(String)? onDelta, {
    VisoraRequestController? controller,
    int? requestId,
    void Function()? onChunk,
  }) {
    return consumeSse(
      response,
      onDelta: onDelta,
      controller: controller,
      requestId: requestId,
      onChunk: onChunk,
    );
  }

  /// Same as [_streamSse] but operating on any byte stream, so the parser can
  /// be unit-tested with hand-crafted chunk splits. Aborts cleanly the moment
  /// [controller] is cancelled, and a malformed line is skipped (logged) rather
  /// than failing the whole request. [onChunk] (if given) is called on every
  /// raw chunk so a caller can reset a read-stall watchdog.
  Future<String> consumeSse(
    Stream<List<int>> chunks, {
    void Function(String)? onDelta,
    VisoraRequestController? controller,
    int? requestId,
    void Function()? onChunk,
  }) async {
    final text = StringBuffer(); // fresh accumulator per request.
    final pending = <int>[];
    var consumedLines = 0;

    await for (final rawChunk in chunks) {
      if (controller?.isCancelled ?? false) break;
      onChunk?.call();
      _debugLog('Visora SSE id=$requestId raw chunk: ${rawChunk.length} bytes');
      pending.addAll(rawChunk);

      var index = 0;
      while (index < pending.length) {
        final nl = pending.indexOf(0x0A, index);
        if (nl == -1) break;
        final lineBytes = List<int>.from(pending.sublist(index, nl));
        index = nl + 1;
        if (lineBytes.isNotEmpty && lineBytes.last == 0x0D) {
          lineBytes.removeLast(); // strip Windows \r\n carriage return.
        }
        final String line;
        try {
          line = utf8.decode(lineBytes);
        } catch (e) {
          _debugLog(
            'Visora SSE id=$requestId invalid line skipped: '
            '${lineBytes.length} bytes, $e',
          );
          continue;
        }
        consumedLines++;
        _debugLog(
          'Visora SSE id=$requestId decoded line $consumedLines: '
          '"${_preview(line)}"',
        );
        _handleSseLine(line, text, onDelta);
      }

      if (index > 0) pending.removeRange(0, index);
    }

    // Late flush: bytes that arrived without a trailing newline. Decode the
    // complete leftover; the stream normally ends on a clean boundary.
    if (pending.isNotEmpty &&
        !(controller?.isCancelled ?? false)) {
      try {
        var tail = utf8.decode(pending);
        if (tail.endsWith('\r')) {
          tail = tail.substring(0, tail.length - 1);
        }
        if (tail.isNotEmpty) {
          _debugLog('Visora SSE id=$requestId final tail: "${_preview(tail)}"');
          _handleSseLine(tail, text, onDelta);
        }
      } catch (e) {
        _debugLog('Visora SSE id=$requestId final tail decode error: $e');
      }
    }
    return text.toString().trim();
  }

  void _handleSseLine(
    String line,
    StringBuffer buffer,
    void Function(String)? onDelta,
  ) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('data:')) return;
    final payload = trimmed.substring(5).trim();
    if (payload.isEmpty) return;
    if (payload == '[DONE]') return;
    _debugLog('Visora SSE event: "${_preview(payload)}"');

    final delta = _deltaFromPayload(payload);
    if (delta.isEmpty) return;
    final clean = sanitizeText(delta);
    buffer.write(clean);
    _debugLog('Visora SSE content: "${_preview(clean)}"');
    onDelta?.call(clean);
  }

  /// Extract the assistant text from a single SSE payload object.
  ///
  /// Handles both OpenAI-stream `choices[n].delta.content`, non-stream
  /// `choices[n].message.content`, and the raw `{ "content": ... }` shape some
  /// compatible endpoints emit.
  String _deltaFromPayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return '';

      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty) {
        final choice = choices.first;
        if (choice is! Map<String, dynamic>) return '';
        final delta = choice['delta'];
        if (delta is Map<String, dynamic>) {
          final content = delta['content'];
          if (content is String && content.isNotEmpty) return content;
        }
        final message = choice['message'];
        if (message is Map<String, dynamic>) {
          final content = message['content'];
          if (content is String && content.isNotEmpty) return content;
        }
        return '';
      }

      final content = decoded['content'];
      if (content is String && content.isNotEmpty) return content;
    } catch (_) {}
    return '';
  }

  Future<VisoraAnswer> _offlineAnswer(
    List<Map<String, String>> messages,
    void Function(String)? onDelta, {
    VisoraRequestController? controller,
    int? requestId,
  }) async {
    _debugLog('Visora REQUEST START id=$requestId (offline engine)');
    _debugLog('Visora conversation message count: ${messages.length}');
    for (var i = 0; i < messages.length; i++) {
      _debugLog('Visora message $i role=${messages[i]['role']}');
    }

    final last = messages.isEmpty ? null : messages.last['content'] ?? '';
    final text = (last ?? '').trim().toLowerCase();

    String answer;
    if (text.isEmpty) {
      answer = 'Please ask me something.';
    } else if (text.contains('can you') ||
        text.contains('what can you do') ||
        text.contains('who are you')) {
      answer = 'I am Visora, your AI assistant built into VisionPath. You can '
          'ask me general questions, get definitions, writing help, ideas, and '
          'more. For full live answers, connect an assistant backend in '
          'Visora settings.';
    } else if (text.contains('hello') || text.contains('hi ') || text == 'hi') {
      answer = 'Hello! I am Visora, your AI assistant. How can I help you today?';
    } else if (text.contains('quantum')) {
      answer = 'Quantum computing uses qubits, which can represent 0 and 1 at '
          'the same time, to explore many possibilities at once. This makes '
          'certain problems much faster to solve than with classical computers.';
    } else if (text.contains('machine learning')) {
      answer = 'Machine learning is a branch of artificial intelligence where '
          'computers learn patterns from data instead of being given explicit '
          'rules. It powers many everyday tools, including speech assistants '
          'and object recognition like the camera features in VisionPath.';
    } else if (text.contains('artificial intelligence') ||
        text.contains('what is ai')) {
      answer = 'Artificial intelligence, or AI, is the field of computer '
          'science focused on creating systems that can perform tasks that '
          'normally require human intelligence, such as understanding '
          'language, recognizing objects, and making decisions.';
    } else if (text.contains('einstein')) {
      answer = 'Albert Einstein was a theoretical physicist best known for the '
          'theory of relativity and the famous equation E equals m c squared.';
    } else if (text.contains('car engine') ||
        (text.contains('engine') && text.contains('how'))) {
      answer = 'A car engine turns fuel into motion. Air and fuel are drawn '
          'into cylinders, compressed, and ignited. The expanding gas pushes a '
          'piston, which turns the crankshaft and ultimately the wheels.';
    } else if (text.contains('email')) {
      answer = 'I can help you write an email. Tell me who it is for, what you '
          'want to say, and the tone you would like, and I will draft it for '
          'you.';
    } else if (text.contains('translate')) {
      answer = 'I can translate a sentence for you. Type or speak the sentence '
          'and tell me the language you want it in, and I will translate it.';
    } else if (text.contains('summarize')) {
      answer = 'I can summarize text for you. Paste or dictate the text, and I '
          'will give you a short clear summary.';
    } else if (text.contains('project ideas') ||
        text.contains('ideas for a project')) {
      answer = 'Some project ideas: a personal budget tracker, a habit '
          'tracking app, a recipe finder that uses what is in your kitchen, a '
          'language flashcard game, or a smart plant watering reminder.';
    } else {
      answer = 'That is a great question. Right now I am running in offline '
          'mode. To answer questions like this with full AI capability, open '
          'Visora settings and connect an assistant backend, then talk to me '
          'again.';
    }

    for (var i = 0; i < answer.length; i += 3) {
      if (controller?.isCancelled ?? false) break;
      final end = i + 3 > answer.length ? answer.length : i + 3;
      await Future<void>.delayed(const Duration(milliseconds: 12));
      onDelta?.call(answer.substring(i, end));
    }
    _debugLog('Visora REQUEST SUCCESS id=$requestId offline len=${answer.length}');
    _debugLog('Visora REQUEST END id=$requestId');
    if (controller?.isCancelled ?? false) {
      return const VisoraAnswer('', isError: true);
    }
    return VisoraAnswer(answer, isOffline: true);
  }

  /// Log to the console only in DEBUG builds; never logs the API key.
  void _debugLog(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print(message);
    }
  }
}

/// Result of one [VisoraLlmClient._chatOnce] attempt. [canRetry] marks only
/// cleanly transient failures (transport error with nothing streamed yet, HTTP
/// 408/429/5xx, or a 200 that returned no content) so the caller can make a
/// single fresh attempt without replaying live-streamed partial text.
class _ChatAttempt {
  const _ChatAttempt(this.answer, {this.canRetry = false});

  final VisoraAnswer answer;
  final bool canRetry;
}

/// Cooperative cancellation handle for a single [VisoraLlmClient.generate]
/// call. A newer request cancels the active handle so the older request aborts
/// its SSE read and retreats from the UI instead of racing the new one.
class VisoraRequestController {
  bool _cancelled = false;
  void Function()? _abort;

  /// True once [cancel] has been called.
  bool get isCancelled => _cancelled;

  /// Abort the associated request; using more than once is a no-op.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final abort = _abort;
    _abort = null;
    abort?.call();
  }

  void _attach(void Function() abort) {
    _abort = abort;
  }

  void _detach() {
    _abort = null;
  }
}

/// Result of a Visora LLM call.
class VisoraAnswer {
  const VisoraAnswer(
    this.text, {
    this.isOffline = false,
    this.isError = false,
    this.statusCode,
  });

  final String text;

  /// True when the answer came from the offline fallback engine.
  final bool isOffline;

  /// True when the answer represents a failed/errored request.
  final bool isError;

  /// The HTTP status of a successful or failed backend call; null for the
  /// offline engine or network failures raised before an HTTP response.
  final int? statusCode;

  /// Whether this is a genuine, successful backend response.
  bool get succeeded =>
      !isOffline && !isError && statusCode != null && statusCode == 200;
}

/// Metadata for a single model entry in a provider's `/models` response.
class VisoraModelInfo {
  const VisoraModelInfo({
    required this.id,
    this.active = true,
    this.contextWindow,
  });

  final String id;

  /// Provider-reported availability; defaults to true when the provider does
  /// not include an `active` field (e.g. OpenAI's list).
  final bool active;

  /// Provider-reported context-window size, when available.
  final int? contextWindow;

  @override
  bool operator ==(Object other) => other is VisoraModelInfo && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'VisoraModelInfo($id)';
}