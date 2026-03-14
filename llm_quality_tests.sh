# Enable and run
defaults write dev.shantanugoel.Aawaaz RUN_QUALITY_TESTS -bool YES
cd Aawaaz && xcodebuild test -project Aawaaz.xcodeproj -scheme Aawaaz \
  -configuration Debug -only-testing:AawaazTests/CleanupQualityTests \
  2>&1 | tee quality-test-output-step.txt
defaults delete dev.shantanugoel.Aawaaz RUN_QUALITY_TESTS

# Deterministic-only test (no LLM, runs always):
#xcodebuild test -project Aawaaz.xcodeproj -scheme Aawaaz \
#  -configuration Debug \
#  -only-testing:AawaazTests/CleanupQualityTests/testDeterministicStagesOnly
