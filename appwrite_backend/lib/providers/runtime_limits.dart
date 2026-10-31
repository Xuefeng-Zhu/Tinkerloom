/// Coordinated bounds for the configured NVIDIA GLM Flash worker.
///
/// The Appwrite Worker Function must be configured with [glmWorkerRuntime].
/// The provider deadline leaves time for validation and durable finalization;
/// both leases outlive the Function's hard runtime so recovery cannot overlap
/// an in-flight provider request.
const glmModelId = 'z-ai/glm-5.3-flash';
const glmProviderDeadline = Duration(seconds: 210);
const glmWorkerRuntime = Duration(seconds: 270);
const glmGenerationLease = Duration(seconds: 280);
const glmDispatchLease = Duration(seconds: 290);
