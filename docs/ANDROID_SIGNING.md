# Android signing

APK updates require every build to use the same private key. Local development
may use debug signing, but CI deliberately refuses to create a release until a
permanent key is configured.

## Recommended setup

From a trusted macOS, Linux, or WSL machine with Java's `keytool` and the
[GitHub CLI](https://cli.github.com/) installed, run:

```bash
gh auth login
bash tool/configure_android_signing.sh
```

The interactive script offers two modes:

1. Generate a new dedicated SuperHealth keystore. Use this for a new app.
2. Reuse an existing keystore. Use this only when new builds must update an app
   already installed with that key.

Passwords are read without echo and passed directly to GitHub CLI; they are not
written to the repository or printed. The script configures these repository
secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_STORE_PASSWORD`

The workflow decodes the keystore only inside the Actions runner and deletes it
with the ephemeral runner. Never commit a keystore or password.

Back up the keystore and its passwords in separate secure locations. Losing
either prevents updating an installed build signed with that key. After setup,
rerun the PR's Flutter workflow and confirm that `Require private Android
signing` and `Build release APK` both pass before merging.

After a successful merge to `main`, CI publishes the signed APK under the
matching private GitHub Release, for example `v0.1.0+1`. Release assets are
used for installation downloads because they do not consume Actions artifact
storage. Increment both parts of the `version` field in `pubspec.yaml` before
publishing an update so Android receives a higher build number and GitHub gets
a distinct release tag.

Repository contents remain read-only during pull-request verification. Only
the `main`-only release job receives `contents: write`, which it uses to create
the version tag and upload the APK.

The connected ChatGPT GitHub integration cannot create Actions secrets, so this
one security-sensitive setup must be run by the repository owner.
