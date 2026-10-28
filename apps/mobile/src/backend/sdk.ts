// Metro selects sdk.native.ts on native platforms and sdk.web.ts on the web.
// This fallback also lets TypeScript inspect the shared adapter contract.
export { createSdk } from "./sdk.web";
