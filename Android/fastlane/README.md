This is a stock fastlane configuration file for your Skip project.
To use fastlane to distribute your app:

1. Update the metadata text files in metadata/android/en-US/
2. Add screenshots to screenshots/en-US
3. Download your Android API JSON file to apikey.json (see https://docs.fastlane.tools/actions/upload_to_play_store/)
4. Run `fastlane assemble` to build the app
5. Run `fastlane release` to submit a new release to the App Store

For the bundle name and version numbers, the ../Skip.env file will be used.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
