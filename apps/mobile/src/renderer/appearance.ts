import type { AppSpec, PageSpec, ViewSpec } from "../spec/types";
export interface AppearanceTokens {
  accent: string;
  onAccent: string;
  canvas: string;
  surface: string;
  ink: string;
  muted: string;
  outline: string;
  radius: number;
  spacing: number;
  serif: boolean;
  style: string;
}
const accentColors = {
  amber: "#a86012",
  blue: "#386ad2",
  rose: "#af4b71",
  sage: "#507963",
  teal: "#177d79",
};
function rgb(hex: string) {
  return [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
}
function luminance(hex: string) {
  const [r, g, b] = rgb(hex).map((v) => {
    const n = v / 255;
    return n <= 0.04045 ? n / 12.92 : ((n + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
export function resolveAppearance(spec: AppSpec): AppearanceTokens {
  const appearance = spec.appearance,
    style = appearance?.style ?? "legacy",
    editorial = style === "editorial",
    playful = style === "playful",
    accent = appearance?.accentColor ?? accentColors[spec.theme],
    density =
      appearance?.density ??
      (editorial ? "spacious" : playful ? "comfortable" : "compact"),
    corners =
      appearance?.corners ??
      (editorial ? "square" : playful ? "rounded" : "soft");
  const luminanceValue = luminance(accent);
  return {
    accent,
    onAccent:
      (luminanceValue + 0.05) / 0.05 >= 1.05 / (luminanceValue + 0.05)
        ? "#000000"
        : "#ffffff",
    canvas: editorial
      ? "#f5f0e5"
      : playful
        ? `#${rgb(accent)
            .map((v) =>
              Math.round(v * 0.065 + 255 * 0.935)
                .toString(16)
                .padStart(2, "0"),
            )
            .join("")}`
        : "#f5f6f7",
    surface: editorial ? "#fffcf5" : "#ffffff",
    ink: editorial ? "#29271f" : "#20252a",
    muted: "#4c5053",
    outline: editorial ? "#d7cdbd" : "#dfe2e4",
    radius: corners === "square" ? 0 : corners === "rounded" ? 28 : 10,
    spacing: appearance
      ? density === "compact"
        ? 0.8
        : density === "spacious"
          ? 1.25
          : 1
      : 1,
    serif:
      (appearance?.typography ?? (editorial ? "serif" : "sans")) === "serif",
    style,
  };
}
export function pageRows(
  page: PageSpec | undefined,
  views: readonly ViewSpec[],
  width: number,
  fontScale: number,
): ViewSpec[][] {
  if (
    !page ||
    page.layout === undefined ||
    page.layout === "stacked" ||
    width < 960 ||
    fontScale >= 1.5
  )
    return views.map((view) => [view]);
  const rows: ViewSpec[][] = [];
  let pair: ViewSpec[] = [];
  for (const [i, view] of views.entries()) {
    const wide =
      ["table", "calendar", "board", "form", "details"].includes(view.type) ||
      (page.layout === "featuredFirst" && i === 0);
    if (wide) {
      if (pair.length) {
        rows.push(pair);
        pair = [];
      }
      rows.push([view]);
    } else {
      pair.push(view);
      if (pair.length === 2) {
        rows.push(pair);
        pair = [];
      }
    }
  }
  if (pair.length) rows.push(pair);
  return rows;
}
