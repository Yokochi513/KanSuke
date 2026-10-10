# iOS リリースの GitHub Actions 設定

`upload-testflight.yml` は `main` への push で `pubspec.yaml` が変更されたとき、
署名済み IPA をビルドして App Store Connect（TestFlight）へアップロードします。
Actions の **Run workflow** からも実行できます（ブランチは `main`）。
バージョンとビルド番号は `pubspec.yaml` を使用します。
アップロード済みのビルドを再実行する場合は、先に `+` 以降のビルド番号を増やしてください。

## 初回準備

1. Apple Developer Program に登録し、App Store Connect に Bundle ID
   `com.kansuke.kansuke` のアプリを作成します。
2. App ID の **Push Notifications** と **Sign in with Apple** を有効化します。
3. Apple Distribution 証明書を秘密鍵付き `.p12` として書き出し、
   この証明書を含む **App Store Connect 配布用 Provisioning Profile** を作成します。
4. App Store Connect の「ユーザとアクセス → 統合」で、対象アプリのビルドを
   アップロードできる API キー（App Manager 等）を作成します。
5. 次の Repository Secrets を GitHub の Settings → Secrets and variables → Actions に登録します。

| Secret | 値 |
| --- | --- |
| `IOS_DISTRIBUTION_CERTIFICATE_BASE64` | 秘密鍵付き `.p12` の Base64（改行なし） |
| `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | `.p12` 書き出し時のパスワード（空パスワードなら省略可） |
| `IOS_PROVISIONING_PROFILE_BASE64` | `.mobileprovision` の Base64（改行なし） |
| `IOS_GOOGLE_SERVICE_INFO_PLIST` | Firebase の iOS アプリ用 `GoogleService-Info.plist` の内容そのまま |
| `APP_STORE_CONNECT_API_KEY_ID` | API キーの Key ID |
| `APP_STORE_CONNECT_API_ISSUER_ID` | API キーの Issuer ID |
| `APP_STORE_CONNECT_API_PRIVATE_KEY` | API キーの `.p8` の内容そのまま（改行を保持） |

証明書、プロファイル、API キーは Git にコミットしません。
CI は一時キーチェーンを使い、成功・失敗にかかわらず秘密ファイルを削除します。
Firebase リソース、Google サインインの URL スキームと通知設定は CI 内で適用します。
APNs キーの Firebase 登録は別途必要です（[既存の手順](../docs/運用/iOSデプロイ手順.md)）。

## 配布の確認

Actions 成功後、App Store Connect の TestFlight でビルドの処理完了を確認します。
輸出コンプライアンスの質問に回答し、内部テストグループにビルドを追加します。
自動配信を使う場合は App Store Connect 側でグループの自動配信を設定します。
App Store への審査提出・公開はこのワークフローでは行いません。
証明書やプロファイルが期限切れになったら対応する Secrets を更新してください。

参考: [GitHub の署名設定](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)、
[Flutter の iOS リリース手順](https://docs.flutter.dev/deployment/ios)。
