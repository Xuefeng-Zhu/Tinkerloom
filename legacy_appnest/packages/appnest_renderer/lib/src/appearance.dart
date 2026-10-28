part of '../appnest_renderer.dart';

/// Resolved design values shared by the live runtime, preview and thumbnails.
/// This extension is absent for legacy definitions, preserving their geometry.
@immutable
class MiniAppAppearanceTokens extends ThemeExtension<MiniAppAppearanceTokens> {
  final String style;
  final double spacingScale, radius;
  const MiniAppAppearanceTokens({
    required this.style,
    required this.spacingScale,
    required this.radius,
  });
  @override
  MiniAppAppearanceTokens copyWith({
    String? style,
    double? spacingScale,
    double? radius,
  }) => MiniAppAppearanceTokens(
    style: style ?? this.style,
    spacingScale: spacingScale ?? this.spacingScale,
    radius: radius ?? this.radius,
  );
  @override
  MiniAppAppearanceTokens lerp(
    covariant MiniAppAppearanceTokens? other,
    double t,
  ) => other == null
      ? this
      : MiniAppAppearanceTokens(
          style: t < .5 ? style : other.style,
          spacingScale: ui.lerpDouble(spacingScale, other.spacingScale, t)!,
          radius: ui.lerpDouble(radius, other.radius, t)!,
        );
}

double _space(BuildContext context, double value) =>
    value *
    (Theme.of(context).extension<MiniAppAppearanceTokens>()?.spacingScale ?? 1);

double _radius(BuildContext context, double fallback) =>
    Theme.of(context).extension<MiniAppAppearanceTokens>()?.radius ?? fallback;

/// The chosen accent is a seed, never an unchecked foreground color. Material's
/// tonal palette derives contrasting foreground/container pairs for every style.
ThemeData resolveMiniAppAppearanceTheme(ThemeData base, AppSpec spec) {
  final appearance = spec.appearance;
  if (appearance == null) return base;
  final editorial = appearance.style == 'editorial';
  final playful = appearance.style == 'playful';
  final seed = appearance.accentColor == null
      ? _appColor(spec.theme)
      : Color(
          0xff000000 |
              int.parse(appearance.accentColor!.substring(1), radix: 16),
        );
  final density =
      appearance.density ??
      (editorial
          ? 'spacious'
          : playful
          ? 'comfortable'
          : 'compact');
  final scale = switch (density) {
    'compact' => .8,
    'spacious' => 1.25,
    _ => 1.0,
  };
  final corners =
      appearance.corners ??
      (editorial
          ? 'square'
          : playful
          ? 'rounded'
          : 'soft');
  final radius = switch (corners) {
    'square' => 0.0,
    'rounded' => 28.0,
    _ => 10.0,
  };
  final serif =
      (appearance.typography ?? (editorial ? 'serif' : 'sans')) == 'serif';
  final generated = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.light,
  );
  final canvas = editorial
      ? const Color(0xfff5f0e5)
      : playful
      ? Color.alphaBlend(
          generated.primary.withValues(alpha: .065),
          Colors.white,
        )
      : const Color(0xfff5f6f7);
  final surface = editorial ? const Color(0xfffffcf5) : Colors.white;
  final ink = editorial ? const Color(0xff29271f) : const Color(0xff20252a);
  final colors = generated.copyWith(
    surface: surface,
    onSurface: ink,
    surfaceContainerLow: canvas,
    surfaceContainerLowest: surface,
    surfaceContainer: Color.alphaBlend(ink.withValues(alpha: .045), canvas),
    surfaceContainerHigh: Color.alphaBlend(ink.withValues(alpha: .065), canvas),
    surfaceContainerHighest: Color.alphaBlend(
      ink.withValues(alpha: .09),
      canvas,
    ),
    onSurfaceVariant: const Color(0xff4c5053),
    outline: const Color(0xff737779),
    outlineVariant: editorial
        ? const Color(0xffd7cdbd)
        : const Color(0xffdfe2e4),
  );
  final bodyFont = base.textTheme.bodyMedium?.fontFamily ?? 'Roboto';
  final text = base.textTheme.apply(
    fontFamily: bodyFont,
    bodyColor: ink,
    displayColor: ink,
  );
  TextStyle? heading(TextStyle? value, {double? size}) => value?.copyWith(
    fontFamily: serif ? 'Lora' : bodyFont,
    fontWeight: playful
        ? FontWeight.w800
        : editorial
        ? FontWeight.w500
        : FontWeight.w600,
    fontSize: size,
    letterSpacing: editorial
        ? -.4
        : playful
        ? -.65
        : -.2,
  );
  final textTheme = text.copyWith(
    displayLarge: heading(text.displayLarge),
    displayMedium: heading(text.displayMedium),
    displaySmall: heading(text.displaySmall, size: playful ? 42 : null),
    headlineLarge: heading(text.headlineLarge),
    headlineMedium: heading(
      text.headlineMedium,
      size: playful
          ? 36
          : editorial
          ? 34
          : 28,
    ),
    headlineSmall: heading(text.headlineSmall, size: playful ? 28 : null),
    titleLarge: heading(text.titleLarge),
    titleMedium: heading(text.titleMedium),
    titleSmall: heading(text.titleSmall),
  );
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radius),
  );
  final bordered = shape.copyWith(
    side: BorderSide(color: colors.outlineVariant),
  );
  final buttonStyle = ButtonStyle(
    shape: WidgetStatePropertyAll(shape),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 20 * scale, vertical: 14 * scale),
    ),
    minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
    textStyle: WidgetStatePropertyAll(
      textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
  return base.copyWith(
    brightness: Brightness.light,
    colorScheme: colors,
    scaffoldBackgroundColor: canvas,
    textTheme: textTheme,
    extensions: [
      ...base.extensions.values.where(
        (value) => value is! MiniAppAppearanceTokens,
      ),
      MiniAppAppearanceTokens(
        style: appearance.style,
        spacingScale: scale,
        radius: radius,
      ),
    ],
    // Compact changes spacing, never the minimum interactive hit target.
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: playful ? shape : bordered,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 16 * scale,
        vertical: 16 * scale,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: colors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: colors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle),
    textButtonTheme: TextButtonThemeData(style: buttonStyle),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(shape),
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: shape,
      side: BorderSide(color: colors.outlineVariant),
    ),
    listTileTheme: ListTileThemeData(
      shape: shape,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 16 * scale,
        vertical: 4 * scale,
      ),
      titleTextStyle: textTheme.titleMedium,
      subtitleTextStyle: textTheme.bodyMedium,
    ),
    dialogTheme: DialogThemeData(backgroundColor: surface, shape: shape),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: colors.primaryContainer,
      indicatorShape: shape,
      labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: surface,
      indicatorColor: colors.primaryContainer,
      indicatorShape: shape,
      selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
        color: colors.primary,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: textTheme.labelMedium,
    ),
    dividerTheme: DividerThemeData(color: colors.outlineVariant),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: colors.primary),
    bannerTheme: MaterialBannerThemeData(
      backgroundColor: canvas,
      contentTextStyle: textTheme.bodySmall,
    ),
  );
}
