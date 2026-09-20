import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'voice_input.dart';

/// Google speech recognition via an invisible WebView.
///
/// Chrome's Web Speech API (`webkitSpeechRecognition`) routes audio to the
/// same Google recognizer the system uses, but it requires neither a Google
/// Cloud API key nor a local speech engine — the page just needs to run in a
/// secure context (loopback is one) and be granted microphone access by the
/// host app ([onPermissionRequest]).
///
/// A tiny HTTP server on 127.0.0.1 serves a speech page; the engine bridges
/// recognition events back over a JavaScript handler. Because WebView speech
/// needs network to reach Google's servers, the caller should keep an offline
/// fallback ([SpeechService]) ready.
class WebSpeechEngine implements VoiceInput {
  WebSpeechEngine({this.languageCode = 'en-US'});

  /// BCP-47 language tag sent to Google, e.g. 'en-US'.
  final String languageCode;

  HttpServer? _server;
  InAppWebViewController? _controller;
  bool _pageReady = false;
  bool _unsupported = false;
  bool _listening = false;
  String _lastError = '';

  /// Called with partial transcriptions while the user is speaking.
  @override
  void Function(String partial)? onPartial;

  /// Called once with the final recognized words.
  @override
  void Function(String finalWords)? onResult;

  /// Called when the recognizer reports an error or the listener notices one.
  @override
  void Function(String message)? onError;

  @override
  bool get isAvailable => _pageReady;

  @override
  bool get isListening => _listening;

  @override
  String get lastError => _lastError;

  /// Speech page served on 127.0.0.1 so the WebView sees a secure context
  /// (loopback is always potentially trustworthy).
  static String _page(String lang) => '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
</head>
<body>
<script>
(function () {
  var lang = '${lang.replaceAll("'", "")}';
  var rec = null;
  function send(type) {
    try { window.flutter_inappwebview.callHandler('speechEvent', type); } catch (e) {}
  }
  function initRec() {
    var SR = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SR) { send('unsupported'); return; }
    rec = new SR();
    rec.lang = lang;
    rec.interimResults = true;
    rec.continuous = false;
    rec.maxAlternatives = 1;
    rec.onstart = function () { send('started'); };
    rec.onend = function () { send('ended'); };
    rec.onerror = function (e) { send('error:' + (e.error || 'unknown')); };
    rec.onresult = function (ev) {
      var interim = '', finalText = '';
      for (var i = ev.resultIndex; i < ev.results.length; i++) {
        var t = ev.results[i][0].transcript;
        if (ev.results[i].isFinal) { finalText += t; } else { interim += t; }
      }
      if (finalText) { send('final:' + finalText); }
      else if (interim && interim.trim()) { send('partial:' + interim); }
    };
    window.__recognizer = rec;
    send('ready');
  }
  window.startSpeech = function () {
    if (!window.__recognizer) { send('unsupported'); return; }
    try { window.__recognizer.start(); } catch (e) { send('error:not-allowed'); }
  };
  window.stopSpeech = function () {
    if (window.__recognizer) { try { window.__recognizer.stop(); } catch (e) {} }
  };
  window.cancelSpeech = function () {
    if (window.__recognizer) { try { window.__recognizer.abort(); } catch (e) {} }
  };
  initRec();
})();
</script>
</body>
</html>
''';

  /// Bind the localhost server and make the WebView load the speech page.
  /// Call from the hosting widget's [State.initState].
  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((request) {
      final path = request.uri.path;
      final get = request.method == 'GET' || request.method == 'HEAD';
      if (get && (path == '/' || path == '/index.html')) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..headers.set(HttpHeaders.cacheControlHeader, 'no-store, no-cache')
          ..write(_page(languageCode))
          ..close();
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.close();
      }
    });
  }

  /// Wait (bounded) until the page reports it is ready or unsupported.
  @override
  Future<bool> initialize() async {
    if (_pageReady) return true;
    if (_unsupported) {
      _lastError = 'This device has no speech recognition available.';
      return false;
    }
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < const Duration(seconds: 25)) {
      if (_pageReady) return true;
      if (_unsupported) {
        _lastError = 'This device has no speech recognition available.';
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    _lastError = 'The speech recognizer could not be started.';
    return false;
  }

  @override
  Future<bool> listen() async {
    if (!_pageReady && !await initialize()) return false;
    if (_listening) return true;
    final controller = _controller;
    if (controller == null) {
      _lastError = 'The speech recognizer could not be started.';
      return false;
    }
    _listening = true;
    _lastError = '';
    try {
      await controller.evaluateJavascript(source: 'startSpeech()');
      return true;
    } catch (e) {
      _listening = false;
      _lastError = 'The microphone could not be started.';
      return false;
    }
  }

  @override
  Future<void> stop() async {
    _listening = false;
    try {
      await _controller?.evaluateJavascript(source: 'stopSpeech()');
    } catch (_) {}
  }

  @override
  Future<void> cancel() async {
    _listening = false;
    try {
      await _controller?.evaluateJavascript(source: 'cancelSpeech()');
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    _listening = false;
    _controller?.dispose();
    _controller = null;
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
    _pageReady = false;
    _unsupported = false;
  }

  /// The InAppWebView to embed (keep it attached, tiny and invisible).
  Widget build() {
    final uri = _startUri;
    if (uri == null) return const SizedBox.shrink();
    return InAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: true,
        mediaPlaybackRequiresUserGesture: false,
        allowFileAccess: true,
      ),
      initialUrlRequest: URLRequest(url: uri),
      onWebViewCreated: (controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
          handlerName: 'speechEvent',
          callback: (arguments) => _onEvent(
            arguments.isEmpty ? '' : (arguments.first?.toString() ?? ''),
          ),
        );
      },
      onPermissionRequest: (controller, request) async {
        final microphone = PermissionResourceType.MICROPHONE;
        if (request.resources.contains(microphone)) {
          return PermissionResponse(
            resources: [microphone],
            action: PermissionResponseAction.GRANT,
          );
        }
        return PermissionResponse(
          resources: request.resources,
          action: PermissionResponseAction.DENY,
        );
      },
    );
  }

  WebUri? get _startUri {
    final server = _server;
    if (server == null) return null;
    return WebUri('http://127.0.0.1:${server.port}/');
  }

  void _onEvent(String message) {
    if (message == 'ready') {
      _pageReady = true;
      _unsupported = false;
      return;
    }
    if (message == 'unsupported') {
      _unsupported = true;
      _pageReady = false;
      _lastError = 'This device has no speech recognition available.';
      return;
    }
    if (message == 'started') {
      _listening = true;
      return;
    }
    if (message == 'ended') {
      _listening = false;
      return;
    }
    if (message.startsWith('final:')) {
      _listening = false;
      final text = message.substring(6).trim();
      if (text.isNotEmpty) onResult?.call(text);
      return;
    }
    if (message.startsWith('partial:')) {
      final text = message.substring(8).trim();
      if (text.isNotEmpty) onPartial?.call(text);
      return;
    }
    if (message.startsWith('error:')) {
      _listening = false;
      final code = message.substring(6).trim();
      _lastError = _mapError(code);
      onError?.call(_lastError);
      return;
    }
  }

  /// Normalize Web Speech error codes to the tokens the screen understands.
  String _mapError(String code) {
    switch (code) {
      case 'no-speech':
        return 'timeout';
      case 'audio-capture':
        return 'the microphone could not be accessed';
      case 'not-allowed':
        return 'permission_denied';
      case 'service-not-allowed':
        return 'This device has no speech recognition available.';
      case 'network':
        return 'network';
      case 'aborted':
        return 'aborted';
      default:
        return code;
    }
  }
}