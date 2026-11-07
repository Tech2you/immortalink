// Enable only with the deployed, tested publication gate and matching policy.
const contentScreeningControlsEnabled = bool.fromEnvironment(
  'CONTENT_SCREENING_CONTROLS_ENABLED',
  defaultValue: false,
);
const contentScreeningPolicyVersion = 'openai-safety-text-photo-2026-11-05';
