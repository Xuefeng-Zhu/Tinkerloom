import { NativeModule, requireOptionalNativeModule } from "expo";

declare class TinkerloomDeviceModule extends NativeModule<
  Record<string, never>
> {
  availability(): Promise<{
    flashlight: boolean;
    brightness: boolean;
    keepAwake: boolean;
    haptics: boolean;
  }>;
  setTorch(enabled: boolean, lease: string): Promise<void>;
  setBrightness(value: number | null, lease: string): Promise<void>;
  setKeepAwake(enabled: boolean, lease: string): Promise<void>;
  release(
    control: "flashlight" | "brightness" | "keepAwake" | "haptics",
    lease: string,
  ): Promise<void>;
}

export default requireOptionalNativeModule<TinkerloomDeviceModule>(
  "TinkerloomDevice",
);
