bool isUnfilledFamilyProfile(String name) => RegExp(
  r'^(parent|grandparent|great[- ]grandparent|child|grandchild|great[- ]grandchild|predecessor|descendant) not added yet$',
  caseSensitive: false,
).hasMatch(name.trim().replaceAll(RegExp(r'\s+'), ' '));

String familyProfileName(Map<String, dynamic> row, String fallback) {
  final displayName = (row['display_name'] ?? '').toString().trim();
  final name = (row['name'] ?? '').toString().trim();
  // Older profile edits left the generated placeholder display name behind.
  if (name.isNotEmpty &&
      !isUnfilledFamilyProfile(name) &&
      isUnfilledFamilyProfile(displayName)) {
    return name;
  }
  if (displayName.isNotEmpty) return displayName;
  return name.isEmpty ? fallback : name;
}
