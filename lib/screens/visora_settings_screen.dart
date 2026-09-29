import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/visora/visora_config.dart';
import '../services/visora/visora_llm_client.dart';
import '../widgets/settings_widgets.dart';

/// Visora assistant configuration: AI backend connection (endpoint, API key,
/// model) plus wake word and spoken-output toggles.
///
/// Credentials are entered by the user at runtime and persisted locally with
/// SharedPreferences; nothing is hard-coded or baked into the app. The model
/// list is discovered live from the provider's `/models` endpoint, so obsolete
/// IDs are never built into the app. When no backend endpoint/key is
/// configured, Visora transparently falls back to the bundled offline engine
/// so the assistant still answers.
class VisoraSettingsScreen extends StatefulWidget {
  const VisoraSettingsScreen({super.key});

  @override
  State<VisoraSettingsScreen> createState() => _VisoraSettingsScreenState();
}

class _VisoraSettingsScreenState extends State<VisoraSettingsScreen> {
  final VisoraConfig _cfg = VisoraConfig.instance;
  bool _testing = false;
  bool _modelsLoading = false;

  @override
  void initState() {
    super.initState();
    _cfg.load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _cfg,
      builder: (context, _) {
        return SettingsScaffold(
          title: 'Visora AI',
          subtitle:
              'Visora is your AI assistant. Connect an OpenAI-compatible '
              'endpoint to enable full answers, or use the built-in offline '
              'engine.',
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const SettingsSectionTitle('AI Backend'),
              SettingsCard(
                child: Column(
                  children: [
                    _CredentialRow(
                      icon: Icons.link_rounded,
                      title: 'Endpoint URL',
                      hint: 'https://api.example.com/v1/chat/completions',
                      value: _cfg.endpoint,
                      obscure: false,
                      keyboard: TextInputType.url,
                      onSave: (v) => _cfg.setEndpoint(v),
                    ),
                    _divider(),
                    _CredentialRow(
                      icon: Icons.key_rounded,
                      title: 'API Key',
                      hint: 'sk-…',
                      value: _cfg.apiKey,
                      obscure: true,
                      onSave: (v) => _cfg.setApiKey(v),
                    ),
                    _divider(),
                    if (_cfg.availableModels.isNotEmpty)
                      SettingsChoice(
                        title: 'Model',
                        selected: _cfg.model,
                        choices: [
                          for (final id in _cfg.availableModels)
                            (label: id, value: id),
                        ],
                        description:
                            '${_cfg.availableModels.length} model(s) available '
                            'from this provider',
                        onSelected: (v) => _cfg.setModel(v),
                      )
                    else
                      _CredentialRow(
                        icon: Icons.smart_toy_rounded,
                        title: 'Model',
                        hint: 'gpt-4o-mini',
                        value: _cfg.model,
                        obscure: false,
                        onSave: (v) => _cfg.setModel(v),
                      ),
                    _divider(),
                    _refreshModelsRow(),
                  ],
                ),
              ),
              SettingsNote(
                !_cfg.hasBackend
                    ? 'No endpoint configured yet — Visora will use the '
                          'built-in offline engine until you add one.'
                    : _cfg.connectionVerified
                        ? 'Backend connected. Visora will stream answers from '
                              'your configured endpoint.'
                        : 'Endpoint configured — tap "Test Connection" to '
                              'verify it works before relying on it.',
              ),
              const SettingsSectionTitle('Assistant'),
              SettingsCard(
                child: Column(
                  children: [
                    SettingsToggle(
                      title: 'Wake Word "Visora"',
                      description:
                          'Say "Visora" near the phone to open the assistant '
                          'hands-free from the main screen.',
                      value: _cfg.wakeWordEnabled,
                      onChanged: (v) => _cfg.setWakeWordEnabled(v),
                    ),
                    _divider(),
                    SettingsToggle(
                      title: 'Voice Output',
                      description:
                          'Visora speaks her answers out loud. Turn off to '
                          'read only.',
                      value: _cfg.voiceOutputEnabled,
                      onChanged: (v) => _cfg.setVoiceOutputEnabled(v),
                    ),
                  ],
                ),
              ),
              const SettingsSectionTitle('Connection Test'),
              SettingsCard(
                child: SettingsActionButton(
                  label: _testing ? 'Testing…' : 'Test Connection',
                  icon: Icons.api_rounded,
                  description: _cfg.hasBackend
                      ? 'Sends: "Reply with exactly: Visora is connected."'
                      : 'Configure an endpoint and API key first.',
                  onTap: _cfg.hasBackend && !_testing ? _runTest : null,
                ),
              ),
              const SettingsSectionTitle('Security'),
              SettingsNote(
                'Your API key is stored only on this device and sent only to '
                'your configured endpoint. Never share or commit it.',
              ),
            ],
          ),
        );
      },
    );
  }

Future<void> _runTest() async {
    setState(() => _testing = true);
    final client = VisoraLlmClient();
    final answer = await client.generate(const [
      {'role': 'user', 'content': 'Reply with exactly: Visora is connected.'},
    ]);
    if (!mounted) return;
    setState(() => _testing = false);

    if (answer.succeeded) {
      _cfg.markConnectionVerified();
      _showResult('Connected', 'Visora is connected.');
      return;
    }

    _cfg.clearConnectionVerified();
    // Whatever went wrong, drop the connected claim so it can only appear
    // after a verified successful response.
    if (!_cfg.hasBackend) {
      _showResult('Test failed', 'No backend configured.');
      return;
    }
    final code = answer.statusCode?.toString() ?? 'error';

    // A 404 marks the model unavailable (also done by the client); if other
    // models are known, switch to the next suitable one automatically.
    if (answer.statusCode == 404 && _cfg.availableModels.isNotEmpty) {
      final retired = _cfg.model;
      final next = VisoraLlmClient.chooseChatModel(
        [
          for (final id in _cfg.availableModels) VisoraModelInfo(id: id),
        ],
      );
      if (next != null && next.id != retired) {
        await _cfg.setModel(next.id);
        _debugLog('Selected Visora model: ${next.id}');
        _showResult(
          'Model unavailable',
          '$retired was retired by the provider. Switched to ${next.id} — '
          'tap Test Connection again.',
        );
        return;
      }
    }

    final detail = answer.isOffline
        ? 'The request fell back to the offline engine.'
        : answer.text.trim();
    _showResult('Test failed (HTTP $code)', detail);
  }

  Widget _refreshModelsRow() {
    final subtitle = _cfg.availableModels.isEmpty
        ? 'Models available to this provider'
        : '${_cfg.availableModels.length} available — '
            '${_cfg.model.isEmpty ? 'none selected' : 'using "${_cfg.model}"'}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.sync_rounded, color: settingsBlue, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Available Models',
                  style: TextStyle(
                    color: settingsInk,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: settingsSubtext,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 34,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                foregroundColor: settingsBlue,
                backgroundColor: const Color(0xFFEEF4FF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _cfg.hasBackend && !_modelsLoading
                  ? _refreshModels
                  : null,
              child: Text(_modelsLoading ? 'Loading…' : 'Refresh'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshModels() async {
    if (!_cfg.hasBackend || _modelsLoading) return;
    setState(() => _modelsLoading = true);
    final client = VisoraLlmClient();
    final chat = VisoraLlmClient.chatModels(await client.fetchModels());
    if (!mounted) return;
    setState(() => _modelsLoading = false);

    if (chat.isEmpty) {
      _showResult(
        'No models found',
        'Could not fetch a model list from this endpoint. Check the URL and '
        'API key.',
      );
      return;
    }

    _cfg.setAvailableModels([
      for (final model in chat) model.id,
    ]);
    // Auto-select the first suitable chat model when the configured one is no
    // longer available from the provider.
    final chosen = VisoraLlmClient.chooseChatModel(
      chat,
      preferred: _cfg.model,
    );
    if (chosen != null && chosen.id != _cfg.model) {
      await _cfg.setModel(chosen.id);
      _debugLog('Selected Visora model: ${chosen.id}');
    }
    _showResult('Models refreshed', '${chat.length} model(s) available.');
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print(message);
    }
  }

  void _showResult(String title, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title: $message'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _CredentialRow extends StatefulWidget {
  const _CredentialRow({
    required this.icon,
    required this.title,
    required this.hint,
    required this.value,
    required this.obscure,
    required this.onSave,
    this.keyboard,
  });

  final IconData icon;
  final String title;
  final String hint;
  final String value;
  final bool obscure;
  final TextInputType? keyboard;
  final ValueChanged<String> onSave;

  @override
  State<_CredentialRow> createState() => _CredentialRowState();
}

class _CredentialRowState extends State<_CredentialRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _CredentialRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value &&
        _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final v = _controller.text.trim();
    if (v.isEmpty) return;
    widget.onSave(v);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(widget.icon, color: settingsBlue, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: settingsInk,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                TextField(
                  controller: _controller,
                  obscureText: widget.obscure,
                  keyboardType: widget.keyboard ?? TextInputType.text,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(
                    color: settingsInk,
                    fontSize: 14.5,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: const TextStyle(
                      color: settingsSubtext,
                      fontSize: 13.5,
                    ),
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: (_) => _save(),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 44,
            height: 34,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: settingsBlue,
                backgroundColor: const Color(0xFFEEF4FF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _save,
              child: const Icon(Icons.check_rounded, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _divider() => const Divider(height: 1, color: settingsBorder);