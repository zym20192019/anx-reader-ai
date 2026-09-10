# The cloud release job packages the resulting app bundle as an unsigned ZIP/DMG.
The standalone project does not use App Store Connect, Match, or upstream Apple credentials.

The supported cloud artifacts are unsigned ZIP/DMG packages created by `.github/workflows/release-independent.yaml`.
For local use, run `bundle exec fastlane mac build_unsigned`, then sign/notarize locally if required.
