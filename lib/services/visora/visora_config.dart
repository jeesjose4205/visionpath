import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runtime-sourced configuration for the Visora assistant AI backend.
///
/// The endpoint, API key and model are entered by the user at runtime (never
/// hard-coded or baked into the app), mirroring the requirement that API keys
/// stay out of the mobile client. When no endpoint/key is configured, Visora
/// falls back to the bundled offline engine so the experience always works.
class VisoraConfig extends ChangeNotifier {
  VisoraConfig._();

  static final VisoraConfig instance = VisoraConfig._();

  static const String _kEndpoint = 'visora.endpoint';
  static const String _kApiKey = 'visora.api_key';
  static const String _kModel = 'visora.model';
  static const String _kWakeWord = 'visora.wake_word';
  static const String _kVoiceOut = 'visora.voice_output';

  String _endpoint = '';
  String _apiKey = '';
  String _model = '';
  bool _wakeWordEnabled = true;
  bool _voiceOutputEnabled = true;

  /// Model IDs discovered from the endpoint's `/models` response. Ephemeral —
  /// re-fetched whenever the backend (endpoint/key) changes. Models that later
  /// turn out to be unavailable (HTTP 404 / model_not_found) are removed here
  /// so they are never auto-selected or re-used.
  List<String> _availableModels = const [];

  /// Whether a real backend request has completed successfully since this
  /// config (or the app) was last changed. Ephemeral — never persisted, so
  /// "connected" is only ever claimed after an actual successful response.
  bool _connectionVerified = false;

  /// OpenAI-compatible chat completions endpoint (e.g. our own backend proxy).
  String get endpoint => _endpoint;

  /// Bearer token / API key for [endpoint]. Persisted locally, never logged.
  String get apiKey => _apiKey;

  /// Model identifier passed in the request body.
  String get model => _model;

  /// Whether the "Visora" wake word is armed on the main screen.
  bool get wakeWordEnabled => _wakeWordEnabled;

  /// Whether Visora speaks responses aloud (TTS).
  bool get voiceOutputEnabled => _voiceOutputEnabled;

  /// True when a real backend call has succeeded (see [markConnectionVerified]).
  /// Shown only transiently; invalidated whenever the backend changes.
  bool get connectionVerified => _connectionVerified;

  /// True when a real backend is configured; otherwise offline engine is used.
  bool get hasBackend => _endpoint.trim().isNotEmpty && _apiKey.trim().isNotEmpty;

  /// Model IDs discovered from the endpoint's `/models` list, chat-suitable
  /// and currently available. Empty until a successful fetch.
  List<String> get availableModels => _availableModels;

  /// Records the discovered, available chat models. Any previously recorded
  /// model that is not in [models] is treated as unavailable.
  void setAvailableModels(List<String> models) {
    _availableModels = List<String>.unmodifiable(models);
    notifyListeners();
  }

  /// True when [modelId] is known to be currently available.
  bool isModelAvailable(String modelId) => _availableModels.contains(modelId);

  /// Drops [modelId] from the available set after the endpoint reported it as
  /// unavailable (e.g. HTTP 404 model_not_found), so it is not used again.
  void markModelUnavailable(String modelId) {
    if (modelId.isEmpty || !_availableModels.contains(modelId)) return;
    _availableModels = List<String>.unmodifiable(
      _availableModels.where((m) => m != modelId),
    );
    notifyListeners();
  }

  /// Record a successful live backend response.
  void markConnectionVerified() {
    _connectionVerified = true;
    notifyListeners();
  }

  /// Drop the "connected" claim (e.g. after a failed test or config change).
  void clearConnectionVerified() {
    _connectionVerified = false;
    notifyListeners();
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _endpoint = p.getString(_kEndpoint) ?? '';
    _apiKey = p.getString(_kApiKey) ?? '';
    _model = p.getString(_kModel) ?? '';
    _wakeWordEnabled = p.getBool(_kWakeWord) ?? true;
    _voiceOutputEnabled = p.getBool(_kVoiceOut) ?? true;
    _connectionVerified = false;
    _availableModels = const [];
    notifyListeners();
  }

  Future<void> setEndpoint(String v) async {
    _endpoint = v.trim();
    _connectionVerified = false;
    _availableModels = const [];
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kEndpoint, _endpoint);
  }

  Future<void> setApiKey(String v) async {
    _apiKey = v.trim();
    _connectionVerified = false;
    _availableModels = const [];
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kApiKey, _apiKey);
  }

  Future<void> setModel(String v) async {
    _model = v.trim();
    _connectionVerified = false;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kModel, _model);
  }

  Future<void> setWakeWordEnabled(bool v) async {
    _wakeWordEnabled = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kWakeWord, v);
  }

  Future<void> setVoiceOutputEnabled(bool v) async {
    _voiceOutputEnabled = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kVoiceOut, v);
  }
}