# The cloud release job packages the resulting Runner.app as an unsigned IPA.
The standalone project does not use App Store Connect, Match, or upstream Apple credentials.

The supported cloud artifact is an unsigned IPA created by `.github/workflows/release-independent.yaml`.
For local use, run `bundle exec fastlane ios build_unsigned` and sign the result with 全能签 or your own Apple workflow.
