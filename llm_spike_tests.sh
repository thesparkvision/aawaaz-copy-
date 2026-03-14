defaults write dev.shantanugoel.Aawaaz RUN_LLM_SPIKE -bool YES
cd Aawaaz && xcodebuild test -project Aawaaz.xcodeproj -scheme Aawaaz \
  -configuration Debug -only-testing:AawaazTests/LLMSpikeTests
defaults delete dev.shantanugoel.Aawaaz RUN_LLM_SPIKE
