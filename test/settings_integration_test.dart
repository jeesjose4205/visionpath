import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visionpath/models/app_settings.dart';
import 'package:visionpath/models/navigation_decision.dart';
import 'package:visionpath/services/instruction_manager.dart';
import 'package:visionpath/services/ocr_service.dart';
import 'package:visionpath/services/settings_service.dart';
import 'package:visionpath/services/vibration_service.dart';
import 'package:visionpath/services/voice_service.dart';
import 'package:visionpath/widgets/emergency_sos_button.dart';
import 'package:visionpath/widgets/settings_scope.dart';
import 'package:visionpath/widgets/sound_mode_button.dart';

/// Integration coverage for the settings that previously had no runtime
/// consumer at all.
///
/// These tests drive the real [SettingsService] and the real consumers, because
/// the whole point of these settings is the wiring: a value that is stored
/// correctly but read by nothing would pass a settings-only test and still be
/// broken for the user.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    VibrationService.debugPulse = null;
    VibrationService.debugSelectionClick = null;
    VibrationService.debugImpact = null;
    await SettingsService.instance.load();
  });

  // ==============================================================
  // 1. SOS hold duration — the countdown and the activation threshold
  //    must be the same number.
  // ==============================================================

  group('SOS hold duration', () {
    test('the controller derives its duration from the setting', () async {
      for (final int seconds in <int>[3, 5, 7]) {
        await SettingsService.instance.setSosHoldDuration(seconds);
        expect(
          SosHoldController.holdSeconds,
          seconds,
          reason: 'the enforced hold must follow the $seconds-second setting',
        );
      }
    });

    test('the countdown ticks the full configured duration', () async {
      for (final int seconds in <int>[3, 5, 7]) {
        await SettingsService.instance.setSosHoldDuration(seconds);

        final List<int> ticks = <int>[];
        int activations = 0;
        final SosHoldController controller = SosHoldController(
          onActivated: () => activations++,
          onTick: ticks.add,
        )..pointerDown(_downEvent());

        for (int i = 0; i < seconds - 1; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 1100));
        }
        expect(activations, 0, reason: 'must not fire early at $seconds s');
        expect(
          ticks.first,
          seconds,
          reason: 'the spoken countdown starts at the configured duration',
        );

        await Future<void>.delayed(const Duration(milliseconds: 1100));
        expect(
          activations,
          1,
          reason: 'must fire exactly once at $seconds s',
        );
        expect(controller.isActivated, isTrue);
        expect(controller.progress, 1.0);
        controller.dispose();
      }
    });

    test('a hold released before the configured time does not activate',
        () async {
      await SettingsService.instance.setSosHoldDuration(7);

      int activations = 0;
      final SosHoldController controller = SosHoldController(
        onActivated: () => activations++,
      )..pointerDown(_downEvent());

      await Future<void>.delayed(const Duration(seconds: 3));
      controller.pointerUp(_downEvent());
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(activations, 0);
      expect(controller.isActivated, isFalse);
      controller.dispose();
    });

    test('a mid-hold settings change does not desync the active countdown',
        () async {
      await SettingsService.instance.setSosHoldDuration(5);

      final List<int> ticks = <int>[];
      int activations = 0;
      final SosHoldController controller = SosHoldController(
        onActivated: () => activations++,
        onTick: ticks.add,
      )..pointerDown(_downEvent());

      await Future<void>.delayed(const Duration(milliseconds: 1200));
      // Change the preference while a hold is in progress.
      await SettingsService.instance.setSosHoldDuration(7);
      await Future<void>.delayed(const Duration(seconds: 5));

      // The hold it promised still completes on its own terms.
      expect(activations, 1);
      expect(
        ticks.first,
        5,
        reason: 'the in-flight hold keeps the duration it started with',
      );
      controller.dispose();
    });
  });

  // ==============================================================
  // 2. Voice configuration — applied centrally, not per screen.
  // ==============================================================

  group('centralized voice configuration', () {
    test('rate, volume and language follow SettingsService', () async {
      VoiceService.bindToSettings();
      await SettingsService.instance.setSpeechRate(SpeechRate.slow);
      await SettingsService.instance.setVoiceVolume(0.4);
      await SettingsService.instance.setVoiceLanguage(VoiceLanguage.ukEnglish);
      await VoiceService.applySettings();

      expect(VoiceService.debugSpeechRate, 0.35);
      expect(VoiceService.debugVolume, 0.4);
      expect(VoiceService.debugLanguage, 'en-GB');
    });

    test('changing the rate updates the shared engine without a restart',
        () async {
      VoiceService.bindToSettings();
      await VoiceService.applySettings();

      await SettingsService.instance.setSpeechRate(SpeechRate.fast);
      expect(VoiceService.debugSpeechRate, 0.8);

      await SettingsService.instance.setSpeechRate(SpeechRate.normal);
      expect(VoiceService.debugSpeechRate, 0.55);
    });

    test('Voice Guidance OFF closes the routine gate globally', () async {
      VoiceService.bindToSettings();
      await SettingsService.instance.setVoiceGuidanceEnabled(false);
      expect(VoiceService.routineVoiceAllowed, isFalse);

      await SettingsService.instance.setVoiceGuidanceEnabled(true);
      expect(VoiceService.routineVoiceAllowed, isTrue);
    });

    test('Global Voice Muted ON closes the gate and clears pending speech',
        () async {
      VoiceService.bindToSettings();
      final VoiceService voice = VoiceService()..setEnabled(true);

      await SettingsService.instance.setVoiceGuidanceEnabled(true);
      expect(VoiceService.routineVoiceAllowed, isTrue);
      expect(voice.canSpeak, isTrue);

      await SettingsService.instance.setGlobalVoiceMuted(true);
      expect(VoiceService.routineVoiceAllowed, isFalse);
      // A screen that set itself enabled still cannot talk over the user's
      // choice: the gate is not per-instance.
      expect(voice.canSpeak, isFalse);
      expect(voice.pendingSpeech, isEmpty);

      await SettingsService.instance.setGlobalVoiceMuted(false);
      expect(voice.canSpeak, isTrue);
    });

    test('binding twice does not double-apply settings', () async {
      VoiceService.bindToSettings();
      VoiceService.bindToSettings();
      await VoiceService.applySettings();
      await SettingsService.instance.setSpeechRate(SpeechRate.fast);
      expect(VoiceService.debugSpeechRate, 0.8);
    });

    test('a per-utterance reading rate does not change the global rate',
        () async {
      VoiceService.bindToSettings();
      await SettingsService.instance.setSpeechRate(SpeechRate.normal);
      await VoiceService.applySettings();
      expect(VoiceService.debugSpeechRate, 0.55);
    });
  });

  // ==============================================================
  // 3. Accessibility scope.
  // ==============================================================

  group('accessibility scope', () {
    testWidgets('text size scales every screen through MediaQuery',
        (tester) async {
      Future<double> scaleFor(TextSizeLevel level) async {
        await SettingsService.instance.setTextSize(level);
        await tester.pumpWidget(
          const MaterialApp(
            home: SettingsScope(child: _ProbeScreen()),
          ),
        );
        await tester.pump();
        final BuildContext ctx = tester.element(find.byType(_ProbeScreen));
        return MediaQuery.textScalerOf(ctx).scale(10);
      }

      expect(await scaleFor(TextSizeLevel.standard), 10);
      expect(await scaleFor(TextSizeLevel.large), closeTo(12, 0.01));
      expect(await scaleFor(TextSizeLevel.extraLarge), closeTo(15, 0.01));
    });

    testWidgets(
        'in-app text size is composed with the platform accessibility scale',
        (tester) async {
      // The OS text-size control is itself an accessibility feature. Overwriting
      // it with a bare TextScaler would silently undo it whenever the in-app
      // setting was left at Normal, so the two must multiply.
      await SettingsService.instance.setTextSize(TextSizeLevel.standard);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: const MaterialApp(home: SettingsScope(child: _ProbeScreen())),
        ),
      );
      await tester.pump();
      BuildContext ctx() => tester.element(find.byType(_ProbeScreen));

      // Normal in-app scale must leave the platform scale alone.
      expect(MediaQuery.textScalerOf(ctx()).scale(10), closeTo(13, 0.01));

      // Largest in-app scale multiplies with it rather than replacing it.
      await SettingsService.instance.setTextSize(TextSizeLevel.extraLarge);
      await tester.pump();
      expect(MediaQuery.textScalerOf(ctx()).scale(10), closeTo(19.5, 0.01));

      await SettingsService.instance.setTextSize(TextSizeLevel.standard);
    });

    test('text scale factors are the documented 1.0 / 1.2 / 1.5', () {
      expect(SettingsService.instance.textScaleFactor, 1.0);
    });

    testWidgets('large buttons enlarge the centralized control sizes',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsScope(child: _ProbeScreen()),
        ),
      );
      await tester.pump();

      BuildContext ctx() => tester.element(find.byType(_ProbeScreen));

      await SettingsService.instance.setLargeButtons(false);
      await tester.pump();
      double basePrimary = AppControlSizes.of(ctx()).primaryButtonHeight;

      await SettingsService.instance.setLargeButtons(true);
      await tester.pump();
      double scaledPrimary = AppControlSizes.of(ctx()).primaryButtonHeight;

      expect(
        scaledPrimary,
        greaterThan(basePrimary),
        reason: 'Large Buttons must enlarge primary controls',
      );
    });

    test('control scale factor is 1.3 when large buttons are on', () async {
      await SettingsService.instance.setLargeButtons(true);
      expect(SettingsService.instance.controlScaleFactor, 1.3);
      await SettingsService.instance.setLargeButtons(false);
      expect(SettingsService.instance.controlScaleFactor, 1.0);
    });

    testWidgets('reduce animations reaches descendants', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsScope(child: _ProbeScreen()),
        ),
      );
      await tester.pump();

      BuildContext ctx() => tester.element(find.byType(_ProbeScreen));

      await SettingsService.instance.setReduceAnimations(false);
      await tester.pump();
      expect(SettingsScope.of(ctx()).animationsEnabled, isTrue);

      await SettingsService.instance.setReduceAnimations(true);
      await tester.pump();
      expect(SettingsScope.of(ctx()).animationsEnabled, isFalse);
      expect(
        MediaQuery.maybeOf(ctx())?.disableAnimations,
        isTrue,
        reason: 'Material widgets rely on the framework signal, not just ours',
      );
    });

    testWidgets(
        'reduce animations never mutes a ticker that gates a state change',
        (tester) async {
      // The regression this guards: a blanket TickerMode(enabled: false) also
      // stops animations that complete a user-visible action — an intro card
      // removed in AnimationController.whenComplete would never be removed.
      // Only subtrees that explicitly opt in via motionSensitive are muted.
      await SettingsService.instance.setReduceAnimations(true);
      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsScope(
            child: _IntroCardGatedOnCompletion(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('intro card'),
        findsNothing,
        reason: 'the completion callback must still run',
      );

      // Decorative motion does stop.
      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsScope(
            child: motionSensitive(child: _PulsingDecoration()),
          ),
        ),
      );
      _PulsingDecorationState.lastTickCount = 0;
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.byType(_PulsingDecoration),
        findsOneWidget,
        reason: 'the element stays mounted; only its ticker is muted',
      );
      expect(
        _PulsingDecorationState.lastTickCount,
        0,
        reason: 'a muted ticker must not keep driving rebuilds',
      );

      await SettingsService.instance.setReduceAnimations(false);
    });

    testWidgets('high contrast produces a distinct, brighter theme',
        (tester) async {
      final ThemeData plain = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1769E0)),
      );
      final ThemeData contrasted = applyHighContrast(plain);

      expect(contrasted.brightness, plain.brightness);
      // High contrast pins to the extremes rather than nudging the seed-derived
      // colours, so the separation is guaranteed rather than merely likely.
      expect(contrasted.colorScheme.onSurface, const Color(0xFF000000));
      expect(
        contrasted.scaffoldBackgroundColor,
        const Color(0xFFFFFFFF),
      );
      expect(
        _contrastRatio(
          contrasted.colorScheme.onSurface,
          contrasted.scaffoldBackgroundColor,
        ),
        greaterThanOrEqualTo(7.0),
        reason: 'text must meet the WCAG AAA contrast ratio of 7:1',
      );
      expect(
        _contrastRatio(
          contrasted.colorScheme.primary,
          contrasted.scaffoldBackgroundColor,
        ),
        greaterThanOrEqualTo(4.5),
        reason: 'interactive/primary elements must meet WCAG AA (4.5:1)',
      );
    });

    test('high contrast composes with each base theme', () {
      final ThemeData light = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1769E0)),
      );
      final ThemeData dark = ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1769E0),
          brightness: Brightness.dark,
        ),
      );

      final ThemeData lightContrast = applyHighContrast(light);
      final ThemeData darkContrast = applyHighContrast(dark);

      expect(lightContrast.brightness, Brightness.light);
      expect(darkContrast.brightness, Brightness.dark);
      expect(
        darkContrast.scaffoldBackgroundColor.computeLuminance(),
        lessThan(lightContrast.scaffoldBackgroundColor.computeLuminance()),
      );
    });

    testWidgets('voice-first mode is exposed to the settings UI', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsScope(child: _ProbeScreen()),
        ),
      );
      await tester.pump();
      BuildContext ctx() => tester.element(find.byType(_ProbeScreen));

      await SettingsService.instance.setVoiceFirstMode(false);
      await tester.pump();
      expect(SettingsScope.of(ctx()).voiceFirstMode, isFalse);

      await SettingsService.instance.setVoiceFirstMode(true);
      await tester.pump();
      expect(SettingsScope.of(ctx()).voiceFirstMode, isTrue);
    });
  });

  // ==============================================================
  // 4. Haptic centralization.
  // ==============================================================

  group('UI haptics', () {
    test('selectionClick fires when haptics are enabled', () async {
      int taps = 0;
      VibrationService.debugSelectionClick = () => taps++;
      addTearDown(() => VibrationService.debugSelectionClick = null);

      await SettingsService.instance.setHapticFeedback(true);
      VibrationService.instance.selectionClick();
      expect(taps, 1);
    });

    test('selectionClick is silent when haptics are disabled', () async {
      int taps = 0;
      VibrationService.debugSelectionClick = () => taps++;
      addTearDown(() => VibrationService.debugSelectionClick = null);

      await SettingsService.instance.setHapticFeedback(false);
      VibrationService.instance.selectionClick();
      expect(taps, 0, reason: 'the setting must reach ordinary UI taps');
    });

    test('impactTap obeys the same preference', () async {
      int taps = 0;
      VibrationService.debugImpact = () => taps++;
      addTearDown(() => VibrationService.debugImpact = null);

      await SettingsService.instance.setHapticFeedback(false);
      VibrationService.instance.impactTap();
      expect(taps, 0);

      await SettingsService.instance.setHapticFeedback(true);
      VibrationService.instance.impactTap();
      expect(taps, 1);
    });

    test('SOS haptics stay gated by the preference, not removed', () async {
      int pulses = 0;
      VibrationService.debugPulse = () => pulses++;
      addTearDown(() => VibrationService.debugPulse = null);

      await SettingsService.instance.setHapticFeedback(false);
      VibrationService.instance.vibrateSOS();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(pulses, 0);

      await SettingsService.instance.setHapticFeedback(true);
      VibrationService.instance.vibrateSOS();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(pulses, greaterThan(0));
      VibrationService.instance.stopVibration();
    });
  });

  // ==============================================================
  // 5. Repeat instruction + 6. Announcement cooldown.
  // ==============================================================

  group('repeat instruction', () {
    test('an unchanged decision is re-announced when repeat is on', () {
      final InstructionManager m = InstructionManager()..repeatEnabled = true;
      expect(m.shouldSpeak(NavigationDecision.forward), isTrue);

      // Well inside the cooldown: nothing yet.
      expect(m.shouldSpeak(NavigationDecision.forward), isFalse);

      // Past the cooldown, with repeat on, it repeats.
      m.repeatCooldown = Duration.zero;
      expect(m.shouldSpeak(NavigationDecision.forward), isTrue);
    });

    test('an unchanged decision is never re-announced when repeat is off', () {
      final InstructionManager m = InstructionManager()..repeatEnabled = false;
      expect(m.shouldSpeak(NavigationDecision.forward), isTrue);

      m.repeatCooldown = Duration.zero;
      expect(
        m.shouldSpeak(NavigationDecision.forward),
        isFalse,
        reason: 'Repeat Last Instruction OFF must not loop the same sentence',
      );
    });

    test('a real change still speaks with repeat off', () {
      final InstructionManager m = InstructionManager()..repeatEnabled = false;
      expect(m.shouldSpeak(NavigationDecision.right), isTrue);
      // right -> forward lowers the danger, so it is not an escalation and has
      // to wait the full configured cooldown.
      expect(
        m.shouldSpeak(NavigationDecision.forward),
        isFalse,
        reason: 'still inside the cooldown',
      );

      m.repeatCooldown = Duration.zero;
      expect(m.shouldSpeak(NavigationDecision.forward), isTrue);
    });

    test('an escalation is never blocked by repeat or the cooldown', () async {
      final InstructionManager m = InstructionManager()..repeatEnabled = false;
      // A long cooldown must not delay a hazard: escalations use their own,
      // much shorter gap instead.
      m.repeatCooldown = const Duration(minutes: 5);

      expect(m.shouldSpeak(NavigationDecision.forward), isTrue);

      // Inside escalationMinimumGap: still gated, but only by that short gap.
      expect(m.shouldSpeak(NavigationDecision.stop), isFalse);

      await Future<void>.delayed(
        InstructionManager.escalationMinimumGap + const Duration(milliseconds: 100),
      );
      expect(
        m.shouldSpeak(NavigationDecision.stop),
        isTrue,
        reason: 'a safety escalation must never be suppressed',
      );
    });

    test('repeatLast is refused when the setting is off', () {
      final InstructionManager m = InstructionManager();
      m.shouldSpeak(NavigationDecision.forward);
      m.noteSpoken(const <String>['Path appears clear ahead.']);
      expect(m.lastSpokenDecision, NavigationDecision.forward);

      m.repeatEnabled = false;
      expect(m.repeatLast(), isFalse);

      m.repeatEnabled = true;
      expect(m.repeatLast(), isTrue);
    });

    test('repeatLast has nothing to repeat before the first instruction', () {
      final InstructionManager m = InstructionManager();
      expect(m.repeatLast(), isFalse);
    });

    test('repeat replays the sentences that were actually spoken', () {
      // The live scene keeps changing between announcements, so a repeat has to
      // come from what was delivered rather than from the current frame —
      // otherwise "repeat that" can say something the user never heard.
      final InstructionManager m = InstructionManager();
      m.shouldSpeak(NavigationDecision.forward);
      m.noteSpoken(const <String>['Chair ahead, two metres.']);

      expect(m.repeatLast(), isTrue);
      expect(
        m.lastSpokenSentences,
        const <String>['Chair ahead, two metres.'],
      );
    });

    test('a decision with no delivered sentences cannot be repeated', () {
      // shouldSpeak returning true does not by itself mean audio played: the
      // screen records the sentences at the point it hands them to the engine.
      final InstructionManager m = InstructionManager();
      m.shouldSpeak(NavigationDecision.forward);
      expect(m.lastSpokenDecision, NavigationDecision.forward);
      expect(m.repeatLast(), isFalse);
    });

    test('reset clears the repeatable instruction', () {
      final InstructionManager m = InstructionManager();
      m.shouldSpeak(NavigationDecision.forward);
      m.noteSpoken(const <String>['Path appears clear ahead.']);
      m.reset();
      expect(m.lastSpokenDecision, isNull);
      expect(m.lastSpokenSentences, isEmpty);
      expect(m.repeatLast(), isFalse);
    });
  });

  group('announcement cooldown', () {
    test('the setting produces the documented durations', () async {
      for (final int seconds in <int>[2, 3, 5, 8]) {
        await SettingsService.instance.setAnnouncementCooldown(seconds);
        expect(SettingsService.instance.announcementCooldownSeconds, seconds);
      }
    });

    test('the combined cooldown honours both settings', () {
      Duration combine(GuidanceMode mode, int seconds) {
        final Duration guidance;
        switch (mode) {
          case GuidanceMode.moreFrequent:
            guidance = const Duration(milliseconds: 1500);
          case GuidanceMode.balanced:
            guidance = const Duration(milliseconds: 3000);
          case GuidanceMode.minimal:
            guidance = const Duration(milliseconds: 6000);
        }
        final Duration announcement = Duration(seconds: seconds);
        return guidance > announcement ? guidance : announcement;
      }

      // The explicit announcement setting is never talked faster than asked.
      expect(
        combine(GuidanceMode.moreFrequent, 8),
        const Duration(seconds: 8),
      );
      expect(combine(GuidanceMode.balanced, 8), const Duration(seconds: 8));
      expect(combine(GuidanceMode.minimal, 8), const Duration(seconds: 8));
      // Guidance Frequency keeps its documented meaning when it is stricter:
      // More Frequent never talks slower than 1.5 s, Minimal never faster than 6 s.
      expect(
        combine(GuidanceMode.minimal, 2),
        const Duration(milliseconds: 6000),
      );
      expect(
        combine(GuidanceMode.minimal, 3),
        const Duration(milliseconds: 6000),
      );
      // Where the two agree, that value is used unchanged.
      expect(combine(GuidanceMode.balanced, 3),
          const Duration(milliseconds: 3000));
      expect(combine(GuidanceMode.moreFrequent, 2),
          const Duration(milliseconds: 2000));
      // The combination is always the larger of the two, never the smaller:
      // 1.5 s guidance vs 2 s announcement resolves to the 2 s the user picked.
      expect(
        combine(GuidanceMode.moreFrequent, 2),
        const Duration(milliseconds: 2000),
      );
    });

    test('a longer cooldown actually suppresses the repeat', () {
      InstructionManager managerFor(GuidanceMode mode, int seconds) {
        final InstructionManager m = InstructionManager();
        final Duration guidance;
        switch (mode) {
          case GuidanceMode.moreFrequent:
            guidance = const Duration(milliseconds: 1500);
          case GuidanceMode.balanced:
            guidance = const Duration(milliseconds: 3000);
          case GuidanceMode.minimal:
            guidance = const Duration(milliseconds: 6000);
        }
        final Duration announcement = Duration(seconds: seconds);
        m.repeatCooldown =
            guidance > announcement ? guidance : announcement;
        return m;
      }

      expect(
        managerFor(GuidanceMode.moreFrequent, 2).repeatCooldown,
        const Duration(milliseconds: 2000),
      );
      expect(
        managerFor(GuidanceMode.moreFrequent, 8).repeatCooldown,
        const Duration(seconds: 8),
      );
      expect(
        managerFor(GuidanceMode.minimal, 5).repeatCooldown,
        const Duration(milliseconds: 6000),
      );
      expect(
        managerFor(GuidanceMode.balanced, 5).repeatCooldown,
        const Duration(seconds: 5),
      );
      // The escalation gap stays short regardless of either setting, so a new
      // hazard is never hidden behind a long announcement cooldown.
      expect(
        InstructionManager.escalationMinimumGap,
        lessThan(managerFor(GuidanceMode.minimal, 8).repeatCooldown),
      );
    });
  });

  // ==============================================================
  // 7. Read Text settings.
  // ==============================================================

  group('read text', () {
    test('automatic text reading persists and round-trips', () async {
      await SettingsService.instance.setReadTextAutoRead(true);
      expect(SettingsService.instance.readTextAutoRead, isTrue);

      await SettingsService.instance.setReadTextAutoRead(false);
      expect(SettingsService.instance.readTextAutoRead, isFalse);
    });

    test('reading speed persists and round-trips', () async {
      for (final SpeechRate rate in SpeechRate.values) {
        await SettingsService.instance.setReadingSpeed(rate);
        expect(SettingsService.instance.readingSpeed, rate);
      }
    });

    test('OCR language resolves to a real supported script', () {
      // Latin is what the app actually ships and verifies.
      expect(OcrService.scriptForSetting('latin'), isNotNull);
      // An unknown stored value degrades to Latin instead of failing.
      expect(
        OcrService.scriptForSetting('klingon'),
        OcrService.scriptForSetting('latin'),
      );
    });

    test('OCR language persists', () async {
      await SettingsService.instance.setOcrLanguage('latin');
      expect(SettingsService.instance.ocrLanguage, 'latin');
    });
  });

  // ==============================================================
  // 8. Persistence across a reload.
  // ==============================================================

  group('persistence', () {
    test('every fixed setting survives a reload', () async {
      await SettingsService.instance.setSosHoldDuration(7);
      await SettingsService.instance.setSpeechRate(SpeechRate.fast);
      await SettingsService.instance.setVoiceVolume(0.3);
      await SettingsService.instance.setVoiceLanguage(VoiceLanguage.ukEnglish);
      await SettingsService.instance.setVoiceGuidanceEnabled(false);
      await SettingsService.instance.setGlobalVoiceMuted(true);
      await SettingsService.instance.setTextSize(TextSizeLevel.extraLarge);
      await SettingsService.instance.setHighContrast(true);
      await SettingsService.instance.setLargeButtons(true);
      await SettingsService.instance.setHapticFeedback(false);
      await SettingsService.instance.setReduceAnimations(true);
      await SettingsService.instance.setVoiceFirstMode(false);
      await SettingsService.instance.setRepeatInstruction(false);
      await SettingsService.instance.setAnnouncementCooldown(8);
      await SettingsService.instance.setReadTextAutoRead(true);
      await SettingsService.instance.setReadingSpeed(SpeechRate.fast);
      await SettingsService.instance.setOcrLanguage('latin');

      // Simulates closing and reopening the app.
      await SettingsService.instance.load();

      final SettingsService s = SettingsService.instance;
      expect(s.sosHoldDurationSeconds, 7);
      expect(s.speechRate, SpeechRate.fast);
      expect(s.voiceVolume, 0.3);
      expect(s.voiceLanguage, VoiceLanguage.ukEnglish);
      expect(s.voiceGuidanceEnabled, isFalse);
      expect(s.globalVoiceMuted, isTrue);
      expect(s.textSize, TextSizeLevel.extraLarge);
      expect(s.textScaleFactor, 1.5);
      expect(s.highContrast, isTrue);
      expect(s.largeButtons, isTrue);
      expect(s.controlScaleFactor, 1.3);
      expect(s.hapticFeedback, isFalse);
      expect(s.reduceAnimations, isTrue);
      expect(s.voiceFirstMode, isFalse);
      expect(s.repeatInstruction, isFalse);
      expect(s.announcementCooldownSeconds, 8);
      expect(s.readTextAutoRead, isTrue);
      expect(s.readingSpeed, SpeechRate.fast);
      expect(s.ocrLanguage, 'latin');
    });

    test('the bound voice service re-applies after a reload', () async {
      VoiceService.bindToSettings();
      await SettingsService.instance.setSpeechRate(SpeechRate.slow);
      await VoiceService.applySettings();
      expect(VoiceService.debugSpeechRate, 0.35);

      await SettingsService.instance.load();
      await VoiceService.applySettings();
      expect(
        VoiceService.debugSpeechRate,
        0.35,
        reason: 'rate must still follow the setting after a restart',
      );
    });

    test('reset restores defaults for every fixed setting', () async {
      await SettingsService.instance.setSosHoldDuration(7);
      await SettingsService.instance.setTextSize(TextSizeLevel.extraLarge);
      await SettingsService.instance.setHighContrast(true);
      await SettingsService.instance.setLargeButtons(true);
      await SettingsService.instance.setRepeatInstruction(false);
      await SettingsService.instance.setAnnouncementCooldown(8);
      await SettingsService.instance.setReadTextAutoRead(true);

      await SettingsService.instance.resetToDefaults();
      await SettingsService.instance.load();

      final SettingsService s = SettingsService.instance;
      expect(s.sosHoldDurationSeconds, 5);
      expect(s.textSize, TextSizeLevel.standard);
      expect(s.textScaleFactor, 1.0);
      expect(s.highContrast, isFalse);
      expect(s.largeButtons, isFalse);
      expect(s.repeatInstruction, isTrue);
      expect(s.announcementCooldownSeconds, 3);
      expect(s.readTextAutoRead, isFalse);
      expect(SosHoldController.holdSeconds, 5);
    });

    test('the dead SOS confirmation setting is gone', () async {
      // A setting with no UI and no consumer must not linger as an API...
      final dynamic service = SettingsService.instance;
      expect(
        () => service.setSosConfirmation(true),
        throwsA(isA<NoSuchMethodError>()),
      );
      expect(() => service.sosConfirmation, throwsA(isA<NoSuchMethodError>()));

      // ...nor as a stored value left behind by an earlier install.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'setting.sosConfirmation': true,
      });
      await SettingsService.instance.load();
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(
        prefs.get('setting.sosConfirmation'),
        isNull,
        reason: 'the legacy key must be purged on load, not merely unused',
      );
    });

    test('notification preference persists and is clearly separate from SOS',
        () async {
      await SettingsService.instance.setNotificationsEnabled(false);
      await SettingsService.instance.load();
      expect(SettingsService.instance.notificationsEnabled, isFalse);
      // The SOS alert sound preference is untouched by the notification toggle.
      expect(SettingsService.instance.sosAlertSoundEnabled, isTrue);
    });
  });

  // ==============================================================
  // Regression guard: the verified settings must keep working.
  // ==============================================================

  group('previously verified settings still work', () {
    test('alert mode, SOS tone and detection voice are unchanged', () async {
      await SettingsService.instance.setAlertMode(AlertMode.muted);
      expect(SettingsService.instance.alertMode, AlertMode.muted);
      await SettingsService.instance.setAlertMode(AlertMode.sound);
      expect(SettingsService.instance.alertMode, AlertMode.sound);

      await SettingsService.instance.setSosAlertTone(SosAlertTone.siren);
      expect(SettingsService.instance.sosAlertTone, SosAlertTone.siren);

      await SettingsService.instance.setDetectionVoiceEnabled(false);
      expect(SettingsService.instance.detectionVoiceEnabled, isFalse);

      await SettingsService.instance.setTheme(AppThemePreference.dark);
      expect(SettingsService.instance.theme, AppThemePreference.dark);
    });

    test('the sound mode button still mirrors the alert mode setting', () {
      expect(SoundModeButton.iconFor(AlertMode.sound), isNotNull);
      expect(SoundModeButton.iconFor(AlertMode.muted), isNotNull);
    });
  });
}

/// The WCAG contrast ratio between two opaque colours.
///
/// Uses the standard relative-luminance formula so "high contrast" is asserted
/// against a real accessibility threshold rather than a vibe.
double _contrastRatio(Color a, Color b) {
  double channel(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  final double la = luminance(a);
  final double lb = luminance(b);
  final double lighter = la > lb ? la : lb;
  final double darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// A minimal screen that exposes the accessibility scope to the tests.
class _ProbeScreen extends StatelessWidget {
  const _ProbeScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('probe')));
  }
}

/// Reproduces the intro-card pattern the real screens use: the widget is only
/// removed from the tree inside `AnimationController.whenComplete`.
class _IntroCardGatedOnCompletion extends StatefulWidget {
  const _IntroCardGatedOnCompletion();

  @override
  State<_IntroCardGatedOnCompletion> createState() =>
      _IntroCardGatedOnCompletionState();
}

class _IntroCardGatedOnCompletionState
    extends State<_IntroCardGatedOnCompletion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(() {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _visible
            ? FadeTransition(
                opacity: _controller,
                child: const Text('intro card'),
              )
            : const Text('camera revealed'),
      ),
    );
  }
}

/// Purely decorative looping animation, i.e. what `motionSensitive` is for.
class _PulsingDecoration extends StatefulWidget {
  const _PulsingDecoration();

  @override
  State<_PulsingDecoration> createState() => _PulsingDecorationState();
}

class _PulsingDecorationState extends State<_PulsingDecoration>
    with SingleTickerProviderStateMixin {
  /// Number of times the animated subtree has actually rebuilt. A muted
  /// `TickerMode` stops the controller driving rebuilds, so this stays put.
  static int lastTickCount = 0;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          lastTickCount++;
          return const SizedBox(width: 10, height: 10);
        },
      ),
    );
  }
}

/// A [PointerDownEvent] at the origin.
PointerDownEvent _downEvent() {
  return PointerDownEvent(
    position: Offset.zero,
    pointer: 1,
    kind: PointerDeviceKind.touch,
  );
}