# Android デプロイ手順（ストア非公開・直接配布）

> KanSuke は Google Play には公開しない（[要件定義.md](../要件定義.md) 1.3 スコープ外）。
> 家族の Android 端末へ **APK を直接配布してインストール**する運用とする。
> iOS 側は [iOSデプロイ手順.md](iOSデプロイ手順.md)。将来ストア公開する場合の検討事項は [ストア公開手順.md](ストア公開手順.md)。

## 全体の流れ

```
1. (初回のみ) リリース用署名鍵を作成
2. (初回のみ) 署名設定を android/ に追加
3. リリース APK をビルド
4. 家族の端末に配布・インストール
5. バージョンアップ時は再ビルド→再配布
```

現状 `android/app/build.gradle.kts` はデバッグ鍵で署名する暫定設定（`signingConfig = signingConfigs.getByName("debug")`）になっている。初回のみ 1〜2 の対応が必要。

## 1. リリース用署名鍵の作成（初回のみ）

```bash
keytool -genkey -v -keystore kansuke-release-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias kansuke
```

- 対話式でパスワードと氏名等（適当でよい）の入力を求められる。
- **`.jks` ファイルとパスワードは絶対に Git にコミットしない**。安全な場所（パスワードマネージャー等）に保管する。
- **紛失注意**: この鍵を失うと同じ applicationId (`com.kansuke.kansuke`) での署名更新ができなくなり、以後は家族全員が一度アンインストールしてから入れ直す必要がある。バックアップを取ること。

## 2. 署名設定（初回のみ）

`android/key.properties` を作成する（**Git 管理外**。後述の通り `.gitignore` に追加すること）。

```properties
storePassword=<keystore作成時に設定したパスワード>
keyPassword=<keystore作成時に設定したパスワード>
keyAlias=kansuke
storeFile=/absolute/path/to/kansuke-release-key.jks
```

`.gitignore` に追記:

```
android/key.properties
```

`android/app/build.gradle.kts` を編集し、`key.properties` を読み込んで署名に使うようにする。

```kotlin
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // ...(既存設定はそのまま)

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
```

> `key.properties` が存在しない環境（CI など）でもビルドが壊れないよう、存在チェックを入れている。

## 3. リリース APK のビルド

```bash
flutter build apk --release
```

出力先: `build/app/outputs/flutter-apk/app-release.apk`

- 端末アーキテクチャ別に分割してファイルサイズを小さくしたい場合は `--split-per-abi`（この場合 `app-armeabi-v7a-release.apk` 等が複数出力されるので、配布時にどれを渡すか注意）。
- ビルド前に `pubspec.yaml` の `version:`（例 `1.0.0+1`）を必要に応じて更新する。

## 4. 家族の端末への配布・インストール

1. 生成した APK ファイルを家族に共有する（Google Drive / メール添付など、ファイルを送れる手段でよい）。
2. 端末側で「提供元不明のアプリ」のインストールを許可する。
   - Android 8 以降: APK を開こうとした際に表示される確認ダイアログから、使用したアプリ（ブラウザ / ファイルマネージャー等）ごとに許可する。
   - 設定画面からの事前許可: 設定 → アプリ → 特別なアプリアクセス → 不明なアプリのインストール
3. APK ファイルをタップしてインストール。

## 5. バージョンアップ時の再配布

1. `pubspec.yaml` の `version` を更新（例 `1.0.0+1` → `1.0.1+2`）。
2. 手順3 と同じ方法で再ビルド。
3. 新しい APK を配布し、既存アプリの上に上書きインストールしてもらう（**同じ署名鍵で署名している限り**アンインストール不要）。

補足: `develop` → `main` マージ時に Cloud Functions が Firestore `meta/release` を更新し、アプリ起動時に「新しいバージョンがあります」という通知が出る（[要件定義.md](../要件定義.md) FR-7）。ただしこれは通知のみで、ストア経由の自動更新ではないため、実際の APK 配布は本手順に従って手動で行う必要がある。

## トラブルシューティング

| 症状 | 原因・対処 |
| --- | --- |
| 「パッケージの解析エラー」でインストールできない | 端末の Android バージョンが `minSdk` 未満の可能性。`flutter build apk` 時の minSdk 設定を確認 |
| 「インストールがブロックされました」と表示される | 「提供元不明のアプリ」の許可がされていない（手順4-2を参照） |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` エラーで更新できない | 以前デバッグ署名版をインストールしていた等、署名が異なるビルドが端末に残っている。一度アンインストールしてから新しいAPKを入れ直す |
