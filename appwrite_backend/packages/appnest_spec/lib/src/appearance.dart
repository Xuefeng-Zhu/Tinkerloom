part of '../appnest_spec.dart';

const appearanceStyles = {'clean', 'editorial', 'playful'};
const appearanceTypographies = {'sans', 'serif'};
const appearanceDensities = {'compact', 'comfortable', 'spacious'};
const appearanceCorners = {'square', 'soft', 'rounded'};
const pageLayouts = {'stacked', 'twoColumn', 'featuredFirst'};
const bannerImagePlacements = {'above', 'beside'};

/// Explicit presentation choices. Omitted choices are resolved by the renderer
/// and never written into older definitions as implicit defaults.
class AppearanceSpec {
  final String style;
  final String? accentColor, typography, density, corners;

  const AppearanceSpec(
    this.style, {
    this.accentColor,
    this.typography,
    this.density,
    this.corners,
  });

  factory AppearanceSpec.fromJson(Map<String, dynamic> j) {
    keys(j, {
      'style',
      'accentColor',
      'typography',
      'density',
      'corners',
    }, 'appearance');
    if (!appearanceStyles.contains(j['style']))
      throw const SpecException('Choose an approved appearance style');
    String? choice(String key, Set<String> options) {
      if (!j.containsKey(key)) return null;
      if (!options.contains(j[key]))
        throw SpecException('Choose an approved appearance $key');
      return j[key] as String;
    }

    String? accent;
    if (j.containsKey('accentColor')) {
      final value = j['accentColor'];
      if (value is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
        throw const SpecException('Accent color must use #RRGGBB');
      }
      accent = value.toUpperCase();
    }
    return AppearanceSpec(
      j['style'] as String,
      accentColor: accent,
      typography: choice('typography', appearanceTypographies),
      density: choice('density', appearanceDensities),
      corners: choice('corners', appearanceCorners),
    );
  }

  Map<String, dynamic> toJson() => {
    'style': style,
    if (accentColor != null) 'accentColor': accentColor,
    if (typography != null) 'typography': typography,
    if (density != null) 'density': density,
    if (corners != null) 'corners': corners,
  };
}
