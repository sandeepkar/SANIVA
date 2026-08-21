# SANIVA release checklist

1. Run `./test.sh` and `./build-app.sh` on each supported macOS release.
2. Confirm duplicate scan, cancellation, preview, Finder reveal, and recoverable Trash behavior with disposable fixtures.
3. Confirm permanent Trash/cache and app deletion confirmations on a test account.
4. Set `SANIVA_SIGN_IDENTITY` to an installed `Developer ID Application` identity and run `./build-app.sh`.
5. Store an App Store Connect notary profile in Keychain, then run `./notarize-app.sh PROFILE_NAME`.
6. Verify with `codesign --verify --deep --strict`, `spctl --assess --type execute`, and `stapler validate`.

Ad-hoc signing remains the local-development default. Public distribution requires the developer’s Apple-issued certificate and notarization credentials.
