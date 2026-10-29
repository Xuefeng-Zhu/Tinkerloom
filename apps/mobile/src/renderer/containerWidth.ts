import { useCallback, useState } from "react";
import type { LayoutChangeEvent } from "react-native";
/** Unknown/hidden containers use the conservative narrow layout; malformed measurements cannot replace a known width. */
export function nextContainerWidth(previous: number, measured: number): number {
  return Number.isFinite(measured) && measured >= 0 ? measured : previous;
}
export function compactRecordTable(width: number, fontScale: number): boolean {
  return (
    !Number.isFinite(width) ||
    width < 640 ||
    !Number.isFinite(fontScale) ||
    fontScale >= 1.5
  );
}
/** Width belongs to this mounted content region, independent of the device/browser window. */
export function useContainerWidth(): readonly [
  number,
  (event: LayoutChangeEvent) => void,
] {
  const [width, setWidth] = useState(0);
  const onLayout = useCallback((event: LayoutChangeEvent) => {
    const measured = event.nativeEvent.layout.width;
    setWidth((previous) => nextContainerWidth(previous, measured));
  }, []);
  return [width, onLayout];
}
