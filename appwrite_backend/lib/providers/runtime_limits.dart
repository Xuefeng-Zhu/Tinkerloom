/// Coordinated bounds for the configured NVIDIA GLM Flash worker.
///
/// The Appwrite Worker Function must be configured with [glmWorkerRuntime].
/// The provider deadline leaves time for validation and durable finalization;
/// both leases outlive the Function's hard runtime so recovery cannot overlap
/// an in-flight provider request.
const glmModelId = 'z-ai/glm-5.3-flash';
const glmProviderDeadline = Duration(seconds: 480);
const glmWorkerRuntime = Duration(seconds: 540);
const workerGenerationLease = Duration(seconds: 550);
const glmGenerationLease = workerGenerationLease;
// Every private Worker execution can run for the same 540-second Function
// timeout, regardless of its mode or selected AI provider.
const workerDispatchLease = Duration(seconds: 560);
const glmDispatchLease = workerDispatchLease;
const workerMediaLease = workerGenerationLease;
