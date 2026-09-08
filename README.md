# Qwallet Scanner

The counter app. Shop staff and owners sign in, scan a customer's loyalty card,
stamp or redeem it, and read the day's scans. Three card types are supported —
reward, points and membership — and the scan log covers the whole business, not
just the person holding the phone.

It talks to `loyalty-pass-api` and does nothing offline: an action either
reaches the server or reports that it did not.

## Running it

```
fvm flutter run
```

The API defaults to `https://app.qwallet.me`. Point it somewhere else with:

```
fvm flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5599
```

`10.0.2.2` is how the Android emulator reaches the host machine. Plain http is
allowed in debug builds only; release builds block it.

```
fvm flutter test        # unit and widget
fvm flutter analyze
```

`integration_test/walkthrough_test.dart` drives every screen on a real device
against a real API, printing `SHOT-READY:` markers for screenshotting.

## Release signing

The Play Store rejects an upload signed with debug keys, and the key you first
publish with is the only key that can ever ship an update. Generate it once,
back it up, and keep it out of the repository.

`flutter build apk --release` works without any of this — it falls back to
debug keys so the app can be put on a device. `flutter build appbundle`, which
is what gets uploaded, refuses to build until the steps below are done.

1. Generate the upload key into the root of this checkout. Answer the prompts;
   the passwords are yours to choose and to keep. `keytool` ships with Android
   Studio's bundled JDK if it is not on your PATH:

   ```
   keytool -genkey -v -keystore qwallet-upload-key.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

2. Create `android/key.properties`, pointing at it:

   ```
   storePassword=<the store password from step 1>
   keyPassword=<the key password from step 1>
   keyAlias=upload
   storeFile=../../qwallet-upload-key.jks
   ```

   The path is relative to `android/app/`, which is where Gradle resolves it
   from, so it works on any machine that has the key in the same place.

   Both files are excluded by `.gitignore` — `*.jks` and `key.properties` at
   the root, and again under `android/`. Keep it that way: whoever holds these
   two can publish updates as you, and a key committed once has to be rotated,
   which for a published app means a new application id and stranded installs.

3. Build the bundle:

   ```
   fvm flutter build appbundle --release
   ```

**Back the keystore up somewhere durable, off this machine.** Losing it means
the app can never be updated again — the listing has to be republished under a
new application id, and existing installs never see another update. A password
manager's secure-file store or an encrypted backup both work; a folder on one
laptop does not.
