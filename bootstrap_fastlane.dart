/// Fastlane bootstrap is intentionally disabled for the independent project.
///
/// Releases are built by `.github/workflows/release-independent.yaml` without
/// App Store Connect, Match, SignPath, notification, or upstream credentials.
void main() {
  print('Use the independent unsigned/local-signing release workflow.');
}
