const firstAccountSetupKey = 'ever_roots_setup_v1';
const firstAccountSetupStepKey = 'ever_roots_setup_step';

// Presentation state only; never use user-editable metadata for permissions.
bool needsFirstAccountSetup(Map<String, dynamic>? metadata) =>
    metadata?[firstAccountSetupKey] == 'pending';

int firstAccountSetupStep(Map<String, dynamic>? metadata) {
  final step = metadata?[firstAccountSetupStepKey];
  return step is int && step >= 0 && step <= 3 ? step : 0;
}
