
import 'package:flutter/material.dart';

import '../services/settings_service.dart';

/// Makes the user's accessibility choices globally effective.
///
/// Five SettingsService values had no runtime consumer at all: they were stored
/// and persisted, but nothing read them. Rather than pushing the same
/// `MediaQuery` / theme arithmetic into every screen — which is exactly how
/// those settings ended up dead in the first place — this widget installs them
/// once, above the navigator, and every descendant inherits the result.
///
/// Each value is derived from [SettingsService] on read, so there is no cached
/// copy to keep in sync and no second source of truth.
class SettingsScope extends StatelessWidget {
  const SettingsScope({super.key, required this.child});

  final Widget child;

  /// The nearest enclosing scope. Falls back to a default-constructed scope
  /// outside the app (for example in an isolated widget test) so widgets never
  /// have to null-check their accessibility context.
static SettingsScopeData of(BuildContext context) {
    final _InheritedSettingsScope? scope = context
        .dependOnInheritedWidgetOfExactType<_InheritedSettingsScope>();
    return scope?.data ?? const SettingsScopeData();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        final SettingsService s = SettingsService.instance;
        final SettingsScopeData data = SettingsScopeData(
          textScale: s.textScaleFactor,
          highContrast: s.highContrast,
          controlScale: s.controlScaleFactor,
          reduceAnimations: s.reduceAnimations,
          voiceFirstMode: s.voiceFirstMode,
        );

        final Widget scoped = _InheritedSettingsScope(data: data, child: child);

        // Motion and text scaling are MediaQuery concerns, so they are applied
        // through it. `disableAnimations` is the framework's own opt-out signal,
        // which Material widgets already respect for page transitions, ripples
        // and indicator ticks — and, unlike TickerMode, it does not stall the
        // controllers that gate state changes. See [SettingsScopeData.duration].
        final MediaQueryData? mq = MediaQuery.maybeOf(context);
        final MediaQueryData base = mq ?? const MediaQueryData();
        final MediaQueryData next = base.copyWith(
          textScaler: data.composeTextScaler(base.textScaler),
          disableAnimations: data.reduceAnimations,
        );
        return MediaQuery(data: next, child: scoped);
      },
    );
  }
}

/// Marks a subtree as decorative motion that may be frozen by reduced animations.
///
/// Wrap decorative, purely visual widgets (pulsing rings, breathing halos) in
/// this. Do NOT wrap widgets whose animation gates a state change the user is
/// waiting on — an intro card removed in `AnimationController.whenComplete`, for
/// example, would never be removed at all.
///
/// When animations are reduced the subtree's tickers are muted, so motion
/// freezes at its current frame rather than being removed from the tree. Any
/// [AnimatedBuilder] in that subtree therefore stops rebuilding, which is
/// exactly the intent: the last frame remains on screen, and nothing that
/// depends on a completion callback is left waiting.
class motionSensitive extends StatelessWidget {
  const motionSensitive({super.key, required this.child, this.fallback});

  final Widget child;

  /// Rendered instead of [child] when animations are reduced.
  ///
  /// Defaults to [child] itself, which freezes the animation at its current
  /// frame instead of removing the element.
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    if (!SettingsScope.of(context).reduceAnimations) return child;
    return TickerMode(enabled: false, child: fallback ?? child);
  }
}

/// An immutable snapshot of the accessibility settings currently in effect.
///
/// Derived from [SettingsService] by [SettingsScope]; never authored directly.
@immutable
class SettingsScopeData {
  const SettingsScopeData({
    this.textScale = 1.0,
    this.highContrast = false,
    this.controlScale = 1.0,
    this.reduceAnimations = false,
    this.voiceFirstMode = true,
  });

  /// Multiplier applied to all text (1.0 / 1.2 / 1.5).
  final double textScale;

  /// Whether the high-contrast theme is active.
  final bool highContrast;

  /// Multiplier applied to interactive control sizes (1.0 / 1.3).
  final double controlScale;

  /// Whether non-essential motion should be suppressed.
  final bool reduceAnimations;

  /// Whether screen changes should be announced and spoken confirmation is
  /// prioritised.
  final bool voiceFirstMode;

  /// Whether non-essential animations may be suppressed.
  bool get animationsEnabled => !reduceAnimations;

  /// Composes this setting's text scale with the platform accessibility scale.
  ///
  /// The user's OS text size is an accessibility control they may have set
  /// because they need it. Overwriting it with a bare `TextScaler.linear(1.2)`
  /// would silently undo that whenever the in-app setting is left at Normal, so
  /// the two are multiplied instead: system 1.3 x in-app 1.5 is honoured as
  /// 1.95x.
  TextScaler composeTextScaler(TextScaler platform) =>
      TextScaler.linear(platform.scale(1.0) * textScale);

  /// Returns [base] unchanged, or [Duration.zero] when animations are reduced.
  ///
  /// The correct fix for an animation that gates a state change is to skip it,
  /// not to mute its ticker. Pair this with an instant state update so the
  /// completion callback still runs:
  ///
  /// ```dart
  /// _controller.reverse().whenComplete(() => setState(() => _gone = true));
  /// ```
  ///
  /// [MediaQueryData.disableAnimations] is a hint Material already honours for
  /// its own transitions; this covers animations owned by the app.
  Duration duration(Duration base) =>
      reduceAnimations ? Duration.zero : base;
}

class _InheritedSettingsScope extends InheritedWidget {
  const _InheritedSettingsScope({required this.data, required super.child});

  final SettingsScopeData data;

  @override
  bool updateShouldNotify(_InheritedSettingsScope oldWidget) =>
      oldWidget.data.textScale != data.textScale ||
      oldWidget.data.highContrast != data.highContrast ||
      oldWidget.data.controlScale != data.controlScale ||
      oldWidget.data.reduceAnimations != data.reduceAnimations ||
      oldWidget.data.voiceFirstMode != data.voiceFirstMode;
}

/// The high-contrast theme, layered on top of whichever base theme is active.
///
/// High Contrast is not a theme of its own — it composes with System / Light /
/// Dark. [applyHighContrast] takes the already-resolved [ThemeData] and returns
/// a variant with stronger separation, so every combination produces a
/// well-defined result without a 3x2 matrix of hand-written themes.
ThemeData applyHighContrast(ThemeData base) {
  final bool isDark = base.brightness == Brightness.dark;
  final ColorScheme scheme = base.colorScheme;

  // Push the extremes apart: near-black/near-white surfaces and fully opaque
  // foreground ink, instead of the soft greys the base theme uses.
  final ColorScheme contrasted = isDark
      ? scheme.copyWith(
          surface: const Color(0xFF000000),
          onSurface: const Color(0xFFFFFFFF),
          primary: const Color(0xFF7FB2FF),
          onPrimary: const Color(0xFF000000),
          outline: const Color(0xFFE6EAF2),
          error: const Color(0xFFFF8A80),
          onError: const Color(0xFF000000),
        )
      : scheme.copyWith(
          surface: const Color(0xFFFFFFFF),
          onSurface: const Color(0xFF000000),
          primary: const Color(0xFF0B47A1),
          onPrimary: const Color(0xFFFFFFFF),
          outline: const Color(0xFF1F2937),
          error: const Color(0xFFB3261E),
          onError: const Color(0xFFFFFFFF),
        );

  return base.copyWith(
    colorScheme: contrasted,
    scaffoldBackgroundColor: contrasted.surface,
    // A visible focus/selection outline everywhere, since low-contrast
    // affordances are the main thing this setting has to fix.
    dividerColor: contrasted.outline,
    splashFactory: InkRipple.splashFactory,
    visualDensity: VisualDensity.standard,
    snackBarTheme: base.snackBarTheme.copyWith(
      backgroundColor: contrasted.inverseSurface,
      contentTextStyle: TextStyle(
        color: contrasted.onInverseSurface,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// Applies the "Large Buttons" multiplier to a theme.
///
/// This is how the setting reaches every screen at once. Scaling the theme's
/// shared control metrics — icon size, minimum button sizes, tap target size,
/// list-tile density — enlarges the standard Material controls (buttons, icon
/// buttons, list tiles, chips) app-wide without editing individual widgets.
///
/// Screens with a custom-drawn primary control should additionally read
/// [AppControlSizes] for that control, which is what the SOS button and the
/// settings action buttons do.
ThemeData applyControlScale(ThemeData base, double scale) {
  if (scale == 1.0) return base;
  return base.copyWith(
    iconTheme: base.iconTheme.copyWith(size: (base.iconTheme.size ?? 24) * scale),
    primaryIconTheme: base.primaryIconTheme.copyWith(
      size: (base.primaryIconTheme.size ?? 24) * scale,
    ),
    // Comfortable targets stay comfortable when scaled up; only the minimum
    // guarantee is raised, so layouts are not forced to reflow unpredictably.
    materialTapTargetSize: MaterialTapTargetSize.padded,
    filledButtonTheme: FilledButtonThemeData(
      style: _scaledStyle(base.filledButtonTheme.style, scale),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _scaledStyle(base.outlinedButtonTheme.style, scale),
    ),
    textButtonTheme: TextButtonThemeData(
      style: _scaledStyle(base.textButtonTheme.style, scale),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: _scaledStyle(base.elevatedButtonTheme.style, scale),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: _scaledStyle(base.iconButtonTheme.style, scale),
    ),
  );
}

ButtonStyle? _scaledStyle(ButtonStyle? style, double scale) {
  // A null style means "no theme-level overrides", so there is nothing to
  // scale from — but returning null would also drop whatever the base theme
  // resolves at runtime. Falling back to a default ButtonStyle keeps the theme
  // coherent and still enlarges the control.
  final ButtonStyle effective = style ?? const ButtonStyle();
  return effective.copyWith(
    minimumSize: WidgetStatePropertyAll<Size>(
      Size(64 * scale, 48 * scale),
    ),
    padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsets.symmetric(horizontal: 20 * scale, vertical: 14 * scale),
    ),
    textStyle: WidgetStatePropertyAll<TextStyle?>(
      effective.textStyle?.resolve(<WidgetState>{})?.copyWith(
        fontSize:
            (effective.textStyle?.resolve(<WidgetState>{})?.fontSize ?? 14) *
                scale,
      ),
    ),
    iconSize: WidgetStatePropertyAll<double>(
      (effective.iconSize?.resolve(<WidgetState>{}) ?? 18) * scale,
    ),
  );
}

/// Shared, centralized control sizing for the "Large Buttons" setting.
///
/// Sized here rather than as scattered literals so the accessibility setting
/// has exactly one number to change, and so major controls can scale without
/// each screen inventing its own multiplier.
class AppControlSizes {
  AppControlSizes(this.scale);

  /// 1.0 normally, 1.3 when Large Buttons is on.
  final double scale;

  static AppControlSizes of(BuildContext context) =>
      AppControlSizes(SettingsScope.of(context).controlScale);

  double scaled(double base) => base * scale;

  /// Minimum height of a primary action button.
  double get primaryButtonHeight => scaled(52);

  /// Minimum side of a square icon control (sound mode, settings, mic).
  double get iconButton => scaled(44);

  /// Minimum side of a primary circular action (SOS-style).
  double get heroButton => scaled(170);

  /// Font size for a primary button label.
  double get primaryButtonLabel => scaled(16);

  EdgeInsets get primaryButtonPadding =>
      EdgeInsets.symmetric(horizontal: scaled(20), vertical: scaled(14));

  /// Wraps [child] so it is never smaller than [minimumSize], honouring Large
  /// Buttons.
  Widget constrain(Widget child, {required double minimumSize}) {
    final double size = scaled(minimumSize);
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: size, minHeight: size),
      child: child,
    );
  }

  /// Padding around a large tappable card, honouring Large Buttons.
  EdgeInsets cardPadding(double base) => EdgeInsets.all(scaled(base));
}
