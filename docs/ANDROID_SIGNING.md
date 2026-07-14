# Android signing

The project uses debug signing when no private release key is supplied. That is convenient for a first personal install, but APK updates require every build to use the same key.

Create and retain a private upload keystore outside this repository. Configure these GitHub repository secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_STORE_PASSWORD`

The workflow decodes the keystore only inside the Actions runner. Never commit a keystore or password. Back up the keystore securely; losing it prevents updating an installed build signed with that key.
