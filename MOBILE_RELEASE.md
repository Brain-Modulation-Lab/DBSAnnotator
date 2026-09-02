# Release runbook

Everything needed to turn a verified build into an installable one, per platform.
[`.github/workflows/ci.yml`](.github/workflows/ci.yml) already contains the build
jobs and reads the secret and variable names below; this document is the one-time
setup that arms them.

Nothing here is required to *run* the app. Building from source needs only the
Flutter SDK — see the documentation's Installation page.

## 1. App icon

The source mark is `assets/icon/app_icon.png` (1024×1024). To regenerate every
platform's icons from it:

```bash
dart run flutter_launcher_icons   # config is in pubspec.yaml
```

Commit the generated files under `android/`, `ios/`, `macos/` and
`windows/runner/resources/`. The tool has no Linux support; the Linux window icon
is set by hand in `linux/runner/my_application.cc` from the bundled asset.

## 2. Android signing (→ signed APK on the GitHub Release)

**The gradle side is already wired.** `android/app/build.gradle.kts` reads the
signing config from `android/key.properties` if present, otherwise from the
`ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD` / `ANDROID_STORE_PASSWORD`
environment variables plus a keystore at `android/app/upload-keystore.jks` —
which is exactly where the CI job decodes it. With neither configured it falls
back to the **debug** key and says so in the build log.

That fallback matters: a debug-signed APK installs and runs, so it is fine for
this week's testing, but it is not distributable. Play rejects it, and a device
that installed it cannot later be upgraded by a properly signed build — it has to
be uninstalled first, taking its data with it. So sign before handing a build to
anyone else.

**Generate an upload keystore** (keep the `.jks` OUT of git — already gitignored):

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias upload
```

**Local builds** — create `android/key.properties` (gitignored):

```
storePassword=<store password>
keyPassword=<key password>
keyAlias=upload
storeFile=<absolute path to upload-keystore.jks>
```

**GitHub secrets** — `ANDROID_KEYSTORE_BASE64` (`base64 -w0 upload-keystore.jks`),
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD`. The CI
android job reads all four. Set them and `flutter build apk --release` is signed,
attached to the Release for sideloading, and the `.aab` alongside it is ready for
Google Play.

Confirm which key a build actually used:

```bash
keytool -printcert -jarfile build/app/outputs/flutter-apk/app-release.apk
```

The debug key is issued to `CN=Android Debug`. Anything else means it is signed
with yours.

## 3. iOS / TestFlight (→ research distribution)

iPadOS cannot be sideloaded from GitHub — TestFlight is the channel.

1. **Apple Developer Program** — enroll Wyss Center as an **organization**
   (needs a **D-U-N-S number**); apply for the **nonprofit fee waiver** ($0).
   This includes code-signing certificates + TestFlight + App Store.
2. **App Store Connect API key** — create an API key (App Manager role);
   download the `.p8` once. It gives three values → GitHub secrets:
   `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`,
   `APP_STORE_CONNECT_API_KEY` (the `.p8` contents).
3. **fastlane** — add `ios/fastlane/Fastfile`:

   ```ruby
   default_platform(:ios)
   platform :ios do
     lane :beta do
       api_key = app_store_connect_api_key(
         key_id: ENV["APP_STORE_CONNECT_KEY_ID"],
         issuer_id: ENV["APP_STORE_CONNECT_ISSUER_ID"],
         key_content: ENV["APP_STORE_CONNECT_API_KEY"],
       )
       build_app(scheme: "Runner", export_method: "app-store")
       upload_to_testflight(api_key: api_key, skip_waiting_for_build_processing: true)
     end
   end
   ```

   Then replace the placeholder step in the iOS CI job with
   `run: cd ios && fastlane beta` (guarded by `env.APP_STORE_CONNECT_KEY_ID != ''`,
   already in place). Signing certs/profiles: use `fastlane match` or Xcode
   automatic signing with the API key.

## 4. Windows / Microsoft Store (→ MSIX)

**No code-signing certificate is needed, and none should be bought.** Microsoft
re-signs MSIX packages themselves after certification: *"You don't need to
purchase a CA-trusted code signing certificate for MSIX/AppX Store
submissions"*, and *"USB tokens or hardware security modules (HSMs) are not
required."* This holds only for MSIX — an MSI or EXE submission is **not**
re-signed and would have to be Authenticode-signed by you, which is one more
reason MSIX is the format here. Partner Center registration is also free now, for
both individual and company accounts, so there is no fee waiver to apply for.

(Microsoft **Trusted Signing**, the cheap way to sign *outside* the Store, is
almost certainly unavailable to this project: public-trust identity validation
requires a legal entity in the USA, Canada, the EU or the UK with three or more
years of verifiable history. The Wyss Center is a Swiss foundation. Don't budget
for it without checking eligibility first.)

### Build it

```bash
flutter build windows --release      # build first
dart run msix:create                 # then package
```

That order is not optional. `msix_config` sets `build_windows: false` because
letting the packaging step launch its own `flutter build windows` has twice
caused Flutter's build system to delete
`windows/flutter/ephemeral/cpp_client_wrapper/*.cc` and then skip re-copying
them, so the *next* build fails with `C1083: Cannot open source file` on files
nobody touched. If you ever hit that, `flutter clean` fixes it.

The output is `build/windows/msix/dbs_annotator.msix`.

### The signing certificate (sideload builds only)

**Do not distribute a package signed with the default certificate.** With no
`certificate_path` configured, the tool signs with a `test_certificate.pfx` that
ships *inside the msix pub package* — subject `CN=Msix Testing, O=Msix Testing
Corporation` — so its private key is public and anyone can sign anything with it.
Asking someone to trust that certificate asks them to trust every package signed
with it, forever. It is fine for "does my package install at all" on your own
machine and nothing more.

For anything you hand to another person, make your own:

```powershell
# Subject must match the `publisher` you set in msix_config, exactly.
$c = New-SelfSignedCertificate -Type Custom -Subject "CN=Wyss Center for Bio and Neuroengineering" `
  -KeyUsage DigitalSignature -FriendlyName "DBS Annotator sideload" `
  -CertStoreLocation "Cert:\CurrentUser\My" `
  -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}")
$p = ConvertTo-SecureString -String "<password>" -Force -AsPlainText
Export-PfxCertificate -cert "Cert:\CurrentUser\My\$($c.Thumbprint)" -FilePath signing.pfx -Password $p
```

Then set `certificate_path`/`certificate_password` (or pass
`--certificate-path`/`--certificate-password`) and add `publisher: CN=Wyss Center
for Bio and Neuroengineering` to `msix_config` — the manifest `Publisher` must
match the certificate subject character for character or Windows rejects the
package. Keep the `.pfx` out of git; `*.pfx`/`*.cer`/`*.p12` are gitignored. In
CI, store it base64-encoded as the `WINDOWS_CERT_BASE64` secret with
`WINDOWS_CERT_PASSWORD`; the windows job decodes it, signs, and shreds it
afterwards even if the build fails.

Note there is **no separate `.cer` file** to distribute: the certificate travels
inside the signed `.msix`, and recipients trust it from the file's *Properties →
Digital Signatures* tab. The documentation's Installation page has that procedure
and the warning that goes with it.

None of this applies to the Store: Microsoft re-signs, so a Store build is
produced unsigned with `--store` and needs no certificate at all.
### What to do in Partner Center

Steps 1 and 2 are what unblock the Store identity, so they gate everything else.

1. **Reserve the app name** — *Apps and games → New product → App*. Pick the final
   name here; the reservation is what `identity_name` is derived from.
2. **Copy the identity values** — *Product management → View app identity
   details*, which gives `Package/Identity/Name`, `Publisher` (the `CN=…` string)
   and `Publisher display name`. These are **case-sensitive, punctuation
   included** — Microsoft's own warning is that *"Spaces and other punctuation
   must also match"*, and a mismatch is the most common submission rejection.
   They are **not committed**. Set them as GitHub repository *variables* (not
   secrets — they are public identifiers):
   `MSIX_IDENTITY_NAME`, `MSIX_PUBLISHER`, `MSIX_PUBLISHER_DISPLAY_NAME`.
   For a local Store build, pass them on the command line instead:

   ```bash
   dart run msix:create --store \
     --identity-name "<Package/Identity/Name>" \
     --publisher "<CN=...>" \
     --publisher-display-name "<Publisher display name>"
   ```

   `--store` produces an **unsigned** package, which is correct — Microsoft signs
   it. It fails loudly if any of the three is missing rather than quietly
   emitting a self-signed one.
3. **Business verification** — must complete before anything publishes. It is
   independent of the code and can take days; start it early.
4. **Age rating** — the IARC questionnaire. Required for every submission.
5. **Privacy policy URL** — the docs carry the statement: the *Privacy* page,
   `docs/privacy.rst`. Point the submission at its published URL.
6. **Set the audience to private** while evaluating — *Pricing and availability →
   Audience → Private audience*, listing tester email addresses. The listing is
   then not publicly discoverable. A **package flight** is the alternative when
   you want a separate tester build stream alongside a public listing.
7. **Run the Windows App Certification Kit** against the package before
   uploading. It catches most certification failures locally, without spending a
   review cycle.

### Versioning

MSIX needs four components and Microsoft reserves the fourth: *"the last (fourth)
section of the version number is reserved for Store use and must be left as 0"*.
`msix_version` in `pubspec.yaml` is therefore `<pubspec version>.0`, enforced by
`test/version_parity_test.dart`. On a tag, CI derives it from the tag instead
(`app-v0.5.1` → `0.5.1.0`), so the release artifact matches what you tagged.

One caveat to expect: the same Microsoft page says the first section *"cannot be
0"*. That sentence sits in a section about UWP packages and it is not established
that Partner Center enforces it for a packaged desktop app — but if a `0.x`
package is rejected at upload, that is why, and the fix is a major-version bump.
Package validation runs before review, so finding out costs nothing.

## 5. Cut a release

```bash
# bump pubspec.yaml version (e.g. 0.5.0+1 -> 0.5.1+2), then the three literals
# that restate it — lib/app_info.dart, CITATION.cff, msix_config — and commit.
# `flutter test` fails if you miss one (test/version_parity_test.dart).
git tag app-v0.5.1 && git push origin app-v0.5.1
```

CI then: runs tests → builds+signs the APK (attached to the GitHub Release) →
builds the Windows MSIX → uploads the iOS build to TestFlight. Link the
TestFlight invite from the Release notes. Do a `app-v0.5.1-rc` tag first as a
dry run.

## Scale-up later (same artifacts, no rebuild)

`.aab` → Google Play track · TestFlight build → App Store · `.ipa`/`.aab` → MDM
(Apple Business Manager / Android Enterprise).
