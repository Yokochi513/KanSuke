# iOS デプロイ手順（ストア非公開・家庭内配布）

> KanSuke は App Store には公開しない（[要件定義.md](../要件定義.md) 1.3 スコープ外）。
> 家族の iPhone に **TestFlight もしくは開発証明書で直接インストール**する運用とする（[基本設計.md](../基本設計.md) 9. 配布方法）。
> Android 側の手順は [Androidデプロイ手順.md](Androidデプロイ手順.md) を参照。
> 将来ストア公開する場合の検討事項は [ストア公開手順.md](ストア公開手順.md)。

## 大前提: Mac が必要

iOS アプリのビルド・署名には **macOS + Xcode が必須**（Apple の制約であり Flutter の制約ではない）。現在の開発環境は Windows のため、以下のいずれかを用意する。

| 手段 | 費用感 | 備考 |
| --- | --- | --- |
| 実機の Mac | 高いが確実 | 一度用意すれば以降の運用が最も楽 |
| クラウド Mac（MacinCloud / MacStadium 等） | 月額課金 | GUI で Xcode を触れる。実機接続が必要な手順（直接インストール）には使えない |
| GitHub Actions の macOS ランナー | パブリックリポジトリなら無料枠あり | 署名鍵を Secrets に置く必要あり。TestFlight 配信の自動化向き |

> **実機を USB 接続してのインストール**（後述の方法 B）は物理的な Mac がないと実施できない。クラウド Mac では TestFlight / Ad Hoc 配布を選ぶことになる。

## 配布方法の比較

| | A. TestFlight | B. 開発証明書で直接インストール | C. Ad Hoc 配布 |
| --- | --- | --- | --- |
| Apple Developer Program（年 $99） | **必要** | 不要（無料 Apple ID で可） | **必要** |
| インストール時に必要なもの | 招待メール + TestFlight アプリ | Mac と USB ケーブル、対象端末を手元に | `.ipa` + 端末 UDID の事前登録 |
| アプリの有効期限 | 90 日（新ビルド配信で延長） | **7 日**（無料アカウント） / 1 年（有料） | 1 年 |
| 同時にインストールできるアプリ数 | 制限なし | 無料アカウントは 3 個まで | 制限なし |
| 登録できる端末数 | 内部テスター 100 名 | 制限なし | 100 台/年（UDID 登録制） |
| 遠隔の家族に配れるか | **できる** | できない（端末が手元に必要） | できる（OTA 配信の準備が必要） |
| 審査 | 内部テスターのみなら**不要** | 不要 | 不要 |

**推奨は A（TestFlight）**。年 $99 かかるが、家族が離れて住んでいても配れ、7 日で失効する煩わしさがない。Android 側の APK 配布と同じ「送るだけ」の運用になる。

Mac を触れる家族が同居していて、かつ年額を払いたくない場合のみ B を選ぶ。ただし **7 日ごとに全端末を Mac に繋ぎ直す**必要があり、実質的に運用が回らないことは覚悟する（[AltStore / SideStore](https://altstore.io/) を使うと更新を自動化できるが、それ自体の維持が必要）。

C（Ad Hoc）は TestFlight と同じ有料プログラムが要る割に UDID 収集と OTA 配信の手間が増えるため、TestFlight が使える状況でこれを選ぶ理由はほぼない。

---

## 1. 共通の事前準備

方法 A / B / C のいずれでも必要になる作業。**このリポジトリの現状ではまだ未実施の項目が含まれる**ので、初回は順に対応すること。

### 1-1. Apple Developer への登録（方法 A / C のみ）

<https://developer.apple.com/programs/> から Apple Developer Program に登録（年額 $99）。個人アカウントで問題ない。

### 1-2. `GoogleService-Info.plist` の配置

このファイルは秘密情報として `.gitignore` されている（[AGENTS.md](../../AGENTS.md) 作業ルール 5）ため、リポジトリには入っていない。**Firebase コンソールから取得して手動で配置する。**

1. [Firebase コンソール](https://console.firebase.google.com/project/kansuke-b6d32/settings/general) を開く。
2. iOS アプリ（bundle ID `com.kansuke.kansuke`）の `GoogleService-Info.plist` をダウンロード。
   - iOS アプリは登録済み（`lib/firebase_options.dart` の `ios` エントリに `appId` がある）。もし未登録なら「アプリを追加」→ iOS を選び、bundle ID に `com.kansuke.kansuke` を指定する。
3. `ios/Runner/GoogleService-Info.plist` に置く。
4. **Xcode で Runner ターゲットに追加する**（Finder でファイルを置くだけでは Xcode プロジェクトに含まれず、実行時に Firebase 初期化が失敗する）。Xcode 左ペインの `Runner` グループに **ドラッグ&ドロップ** し、"Copy items if needed" と Runner ターゲットのチェックを入れる。

### 1-3. Google サインイン用の URL スキームを `Info.plist` に追加

`ios/Runner/Info.plist` には現状 `CFBundleURLTypes` が無い。このままだと Google サインインがコールバックで戻ってこられず失敗する。

`GoogleService-Info.plist` を開き、`CLIENT_ID` と `REVERSED_CLIENT_ID` の値を確認したうえで、`Info.plist` の `<dict>` 直下に以下を追記する。

```xml
<key>GIDClientID</key>
<string>【GoogleService-Info.plist の CLIENT_ID の値】</string>
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>【GoogleService-Info.plist の REVERSED_CLIENT_ID の値】</string>
        </array>
    </dict>
</array>
```

> `lib/features/auth/data/firebase_auth_repository.dart` は `GoogleSignIn.instance.initialize()` を引数なしで呼んでいるため、クライアント ID は `Info.plist` の `GIDClientID` から読まれる。

### 1-4. プッシュ通知（FCM）の設定

FR-5 のリマインド通知は FCM 経由で APNs に中継される（[要件定義.md](../要件定義.md) 技術的決定事項 3）。iOS では以下がすべて揃わないとトークンが取得できない。

**(a) Push Notifications capability の追加**

`ios/Runner/Runner.entitlements` には現状 Sign in with Apple の entitlement しか無い。Xcode で Runner ターゲット → Signing & Capabilities → `+ Capability` → **Push Notifications** を追加する。これにより `aps-environment` キーが entitlements に追記される。

同じ画面で **Background Modes** を追加し、`Remote notifications` にチェックを入れる（バックグラウンドで通知を受け取るため）。

**(b) APNs 認証鍵の作成と Firebase への登録**

1. [Apple Developer → Certificates, Identifiers & Profiles → Keys](https://developer.apple.com/account/resources/authkeys/list) で新しいキーを作成し、**Apple Push Notifications service (APNs)** にチェック。
2. ダウンロードした `.p8` ファイルを保管する（**再ダウンロード不可・Git にコミットしない**）。Key ID と、アカウント右上の Team ID を控える。
3. Firebase コンソール → プロジェクトの設定 → **Cloud Messaging** タブ → iOS アプリの「APNs 認証キー」に `.p8` / Key ID / Team ID をアップロード。

> 無料の Apple ID（方法 B）では APNs 認証鍵を作成できない。**プッシュ通知を試すには有料プログラムが必要**。

### 1-5. Sign in with Apple の有効化

`Runner.entitlements` に `com.apple.developer.applesignin` は既にあるが、Apple Developer 側の App ID でも capability を有効化する必要がある。

1. Apple Developer → Identifiers → `com.kansuke.kansuke` → **Sign in with Apple** にチェック。
2. Firebase コンソール → Authentication → Sign-in method → **Apple** を有効化。
   - iOS ネイティブのサインインだけであれば、Service ID や秘密鍵の設定は不要。

### 1-6. Xcode で署名設定

1. `open ios/Runner.xcworkspace`（`.xcodeproj` ではなく **`.xcworkspace`** を開くこと。CocoaPods を使っているため）
2. Runner ターゲット → Signing & Capabilities → **Automatically manage signing** にチェック。
3. Team に自分の Apple ID / Developer アカウントを選択。
4. Bundle Identifier が `com.kansuke.kansuke` になっていることを確認。
   - **他人が同じ bundle ID で登録済みだと通らない**。その場合は自分のドメイン等に変えて（例 `com.example.kansuke`）、Firebase 側の iOS アプリも同じ ID で登録し直し、`flutterfire configure` で `firebase_options.dart` を再生成する。

---

## 2. 方法 A: TestFlight で配布（推奨）

### 2-1. App Store Connect にアプリを登録

1. [App Store Connect](https://appstoreconnect.apple.com/) → マイ App → **+** → 新規 App。
2. プラットフォーム iOS、名前（例 `KanSuke`）、バンドル ID `com.kansuke.kansuke`、SKU（任意の一意な文字列）を入力。
   - **公開はしない**ので、App Store 用の審査提出やスクリーンショット登録は不要。TestFlight のみを使う。

### 2-2. ビルドとアップロード

Mac 上で:

```bash
flutter pub get
cd ios && pod install && cd ..
flutter build ipa --release
```

出力: `build/ios/archive/Runner.xcarchive` と `build/ios/ipa/kansuke.ipa`

アップロードは次のいずれか。

```bash
# CLI（App Store Connect の API キー、または Apple ID とアプリ用パスワードが必要）
xcrun altool --upload-app --type ios \
  -f build/ios/ipa/kansuke.ipa \
  --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
```

GUI なら `build/ios/archive/Runner.xcarchive` を Xcode の Organizer（Window → Organizer）で開き、**Distribute App → TestFlight & App Store** を選ぶ。

### 2-3. 家族を内部テスターとして招待

1. App Store Connect → 対象 App → **TestFlight** タブ。
2. 「内部テスト」グループを作成し、家族の Apple ID（App Store Connect の**ユーザー**として招待済みのもの）を追加する。
   - 内部テスターは最大 100 名。**Beta App Review は不要**で、アップロード後の処理が終わり次第すぐ配信できる。
   - 家族を App Store Connect のユーザーに追加する手間を避けたい場合は「外部テスト」でメールアドレス指定の招待もできるが、初回に Beta App Review（通常 1 日程度）が入る。
3. 家族は招待メールのリンクから **TestFlight アプリ**をインストールし、その中から KanSuke を入れる。

### 2-4. バージョンアップ時

1. `pubspec.yaml` の `version` を更新（現在 `1.1.0+2` → 例 `1.1.1+3`）。
   - **ビルド番号（`+` 以降）は毎回インクリメント必須**。同じビルド番号は App Store Connect が受け付けない。
2. 2-2 を再実行してアップロード。
3. TestFlight が家族の端末に自動で更新通知を出す。

> ビルドの有効期限は 90 日。切れる前に新しいビルドを上げれば、家族側は入れ直し不要。

---

## 3. 方法 B: 開発証明書で直接インストール（無料・端末が手元にある場合）

Mac に iPhone を USB 接続して、その場でインストールする。

```bash
flutter devices          # 接続した iPhone が出るか確認
flutter run --release -d <デバイスID>
```

初回は以下でつまずきやすい。

- **証明書の信頼**: iPhone 側で 設定 → 一般 → VPN とデバイス管理 → 自分の Apple ID を「信頼」する必要がある。
- **7 日で失効**: 無料 Apple ID で署名したアプリは 7 日後に起動できなくなる。再度 Mac に繋いで `flutter run` し直す。
- **3 アプリまで**: 無料アカウントで同時に署名できるアプリは 3 個まで。
- **プッシュ通知は使えない**: 1-4 の通り APNs 認証鍵を作れないため、リマインド通知（FR-5）は動作しない。

---

## 4. 方法 C: Ad Hoc 配布（有料・TestFlight を使わない場合）

1. 家族の端末の **UDID** を集める（Finder に接続する / [udid.tech](https://udid.tech) 等）。
2. Apple Developer → Devices に UDID を登録（年 100 台まで）。
3. Ad Hoc 用の Provisioning Profile を作成。
4. ビルド:

   ```bash
   flutter build ipa --release --export-method ad-hoc
   ```

5. `.ipa` を配る。ただし iOS は APK のように「ファイルをタップして入れる」ことができない。次のどちらかが要る。
   - Mac の **Apple Configurator** で端末に流し込む
   - `manifest.plist` を用意して HTTPS サーバに置き、`itms-services://` リンクから OTA インストールさせる

TestFlight より明確に手間が多い。**特別な理由がなければ方法 A を選ぶこと。**

---

## トラブルシューティング

| 症状 | 原因・対処 |
| --- | --- |
| ビルド時に `GoogleService-Info.plist` が無いと怒られる / 起動直後に Firebase 初期化でクラッシュ | 1-2 を実施。Finder で置くだけでなく **Xcode の Runner ターゲットに追加**されているか確認 |
| Google サインインでブラウザから戻ってこない・即座に失敗する | 1-3 の `GIDClientID` / `CFBundleURLTypes` が未設定 |
| `getToken()` が null を返す / 通知が届かない | 1-4 の Push Notifications capability か APNs 認証鍵が未設定。無料アカウントでは APNs 自体が使えない |
| Apple サインインで `AuthorizationErrorCode.unknown` | 1-5 の App ID 側 capability か Firebase の Apple プロバイダが未有効化 |
| `No profiles for 'com.kansuke.kansuke' were found` | Signing & Capabilities で Team が未選択、または bundle ID が他者に取得済み。1-6 を参照 |
| `pod install` が失敗する | `cd ios && pod repo update && pod install`。Podfile は `platform :ios, '16.0'`（`IPHONEOS_DEPLOYMENT_TARGET` も 16.0） |
| App Store Connect が「このビルド番号は既に使用されています」と拒否する | `pubspec.yaml` の `+N` をインクリメントして再ビルド |
| アプリが 7 日で起動しなくなる | 無料 Apple ID での署名の仕様（方法 B）。方法 A に移行するのが根本解決 |

## 秘密情報の取り扱い

以下は **絶対に Git にコミットしない**（[AGENTS.md](../../AGENTS.md) 作業ルール 5）。`.gitignore` 済みであることを前提に扱う。

- `ios/Runner/GoogleService-Info.plist`
- APNs 認証鍵（`AuthKey_XXXXXXXXXX.p8`）— 再ダウンロード不可なので必ずバックアップ
- App Store Connect API キー（`.p8`）
- 配布用証明書・Provisioning Profile
