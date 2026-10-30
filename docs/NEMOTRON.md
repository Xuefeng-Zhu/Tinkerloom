# Nemotron and AI generation

Tinkerloom contains a server-side chat-completions adapter for NVIDIA Nemotron models. The adapter can support idea guidance and generation of declarative app definitions. Provider configuration is not present in the current development deployment, and a successful live Nemotron workflow in Tinkerloom has not been verified. Manual building, templates, and the offline preview do not require an AI provider.

## How generation works

The Flutter client requests generation through the authenticated Core Function. Generation work is handled by the private Worker; guidance also uses the configured provider through the backend. Provider credentials stay on the server. Generated responses are parsed and validated against the app definition and its semantic constraints before they can become a private draft. Publishing remains an explicit action, and model-generated executable code is not run.

For NVIDIA routes, the adapter places the generation schema in the model's instructions instead of relying on provider-side JSON-schema enforcement. Local validation remains authoritative; successful HTTP responses alone do not establish a valid app. The current transport applies the model's registered settings, including its baseline thinking-off profile for Nemotron. Experimental profiles described in the AppNest studies do not automatically change the Tinkerloom application's configured transport.

## Server configuration

If you choose to configure NVIDIA, provide the following to the trusted Appwrite Functions using protected server-side environment configuration. Core needs the provider configuration for guidance, and the private Worker needs it for generation. These are examples of configuration values, not instructions to make a provider request or enable a deployment.

| Variable | Value or purpose |
| --- | --- |
| `AI_BASE_URL` | `https://integrate.api.nvidia.com/v1`; the adapter appends `/chat/completions` |
| `AI_MODEL` | One exact supported model ID from the table below |
| `NVIDIA_API_KEY` | Your server-only NVIDIA credential |

The adapter requires a nonempty model and credential and an HTTPS base. NVIDIA configuration accepts the exact base above, with an optional trailing slash. The separate generic `AI_API_KEY` is not sent to NVIDIA. Do not put credentials in Flutter build defines, source files, logs, public documentation, or client-side storage. See the [backend guide](../appwrite_backend/README.md) for Function and worker configuration.

| Nemotron model | Accepted NVIDIA model ID |
| --- | --- |
| Lightning | `nvidia/nemotron-3.5-lightning-30b-a3b` |
| Super | `nvidia/nemotron-3-super-120b-a12b` |
| Ultra | `nvidia/nemotron-3-ultra-550b-a55b` |
| Nano Omni | `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning` |

The source registry establishes accepted configuration, not current model availability, account access, price, or quota. Check those separately with the provider before authorizing any live use. The NVIDIA application route also supports the separate comparison model `z-ai/glm-5.3-flash`; other comparison models in the evaluation registry are not necessarily accepted by application configuration.

## Evidence and limitations

The [Nemotron evaluation summary](NEMOTRON_EVALUATION.md) and [creation pipeline experiments](NEMOTRON_PIPELINES.md) describe synthetic experiments conducted in AppNest. They are useful design and failure-analysis references, but do not verify Tinkerloom's current deployment, authenticated persistence, renderer, device behavior, production readiness, or any Nebius integration. The original study documents remain available under `legacy_appnest/docs/`; their evaluation CLI is not included as a Tinkerloom command.

Normal Tinkerloom tests and CI use local fixtures and do not call an AI provider or Appwrite Cloud. Live provider access, model availability, request usage, and hosted end-to-end behavior require separate authorization and verification. See the [development guide](DEVELOPMENT.md) for offline workflows and quota boundaries.
