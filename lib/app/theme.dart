import 'package:flutter/material.dart';

/// 和色（日本の伝統色）パレット。
///
/// アプリアイコン（和紙の幟・紺の家紋・墨絵の武者・朱の房）から抽出した色を
/// 名前付きで持つ。画面側は原則 [ColorScheme] / [KanSukeColors] 経由で参照し、
/// ここを直接参照するのはテーマ定義とメンバー色パレットだけにとどめる。
abstract final class WashiColors {
  /// 紺 — アイコンの家紋・外周円・墨書きの色。アプリの基調色。
  static const kon = Color(0xFF1B2B4B);

  /// 藍白 — 紺を夜間の暗い地に載せるための明るい藍。
  static const aijiro = Color(0xFF9FB2D2);

  /// 生成り — 晒していない和紙の地色。ライトテーマの背景。
  static const kinari = Color(0xFFF7F3E8);

  /// 鳥の子 — 幟に使われている、生成りより一段濃い紙色。
  static const torinoko = Color(0xFFEDE4D1);

  /// 墨 — 濃墨。ライトテーマの文字色、ダークテーマの背景。
  static const sumi = Color(0xFF23211E);

  /// 薄墨 — 補助的な文字・罫線。
  static const usuzumi = Color(0xFF6E6960);

  /// 朱 — 房・落款の差し色。日曜と祝日に使う。
  static const shu = Color(0xFFB7412E);

  /// 洗朱 — 朱を暗い地に載せるための明るい朱。
  static const araishu = Color(0xFFDD7B65);

  /// 臙脂 — 朱より沈んだ赤。エラー表示に使う。
  static const enji = Color(0xFF8C2A2A);

  /// 縹 — 藍系の青。土曜に使う。
  static const hanada = Color(0xFF2B5A7E);

  /// 空 — 縹を暗い地に載せるための明るい青。
  static const sora = Color(0xFF7FA6C4);

  /// 松葉 — 深い緑。
  static const matsuba = Color(0xFF3F6B3A);

  /// 紫紺 — 赤みを帯びた紫。
  static const shikon = Color(0xFF5B3E7E);

  /// 紅梅 — くすんだ桃色。
  static const kobai = Color(0xFFB4506E);

  /// 山吹 — 金色がかった黄。
  static const yamabuki = Color(0xFFD9A62E);
}

/// メンバーの識別色（FR-2）。和色から、隣り合っても混同しない 6 色を選ぶ。
abstract final class MemberColors {
  static const palette = <Color>[
    Color(0xFF1B4B72), // 藍
    WashiColors.shu, // 朱
    WashiColors.matsuba, // 松葉
    WashiColors.shikon, // 紫紺
    WashiColors.kobai, // 紅梅
    WashiColors.yamabuki, // 山吹
  ];
}

/// 明朝体のフォント候補。
///
/// 和風の見た目は書体の寄与が大きいため、見出しには明朝体を当てる。
/// フォントを同梱するとアプリサイズが数 MB 増えるので、各 OS に標準で入って
/// いる明朝体を優先順に指定し、見つからなければ既定のゴシックへ落ちるに任せる。
const _minchoFallback = <String>[
  'Hiragino Mincho ProN', // iOS / macOS
  'YuMincho', // Windows
  'Noto Serif CJK JP', // Android / Linux
  'Noto Serif JP',
  'serif',
];

/// テーマ由来では表現できない、和風スタイル固有の色。
///
/// [ColorScheme] に該当する役割がない曜日色・和紙の地色などを持たせる。
/// テーマ未登録の [BuildContext]（素の `MaterialApp` を使うウィジェットテスト等）
/// でも壊れないよう、[of] はライトテーマの値へフォールバックする。
@immutable
class KanSukeColors extends ThemeExtension<KanSukeColors> {
  const KanSukeColors({
    required this.sunday,
    required this.saturday,
    required this.holiday,
    required this.washiBase,
    required this.washiFiber,
  });

  /// 日曜の日付色（朱）。
  final Color sunday;

  /// 土曜の日付色（縹）。
  final Color saturday;

  /// 祝日の日付・祝日名の色。
  final Color holiday;

  /// 和紙テクスチャの地色。
  final Color washiBase;

  /// 和紙テクスチャに漉き込まれた繊維の色。
  final Color washiFiber;

  static const light = KanSukeColors(
    sunday: WashiColors.shu,
    saturday: WashiColors.hanada,
    holiday: WashiColors.shu,
    washiBase: WashiColors.kinari,
    washiFiber: Color(0x0D231E14),
  );

  static const dark = KanSukeColors(
    sunday: WashiColors.araishu,
    saturday: WashiColors.sora,
    holiday: WashiColors.araishu,
    washiBase: WashiColors.sumi,
    washiFiber: Color(0x0BF7F3E8),
  );

  static KanSukeColors of(BuildContext context) =>
      Theme.of(context).extension<KanSukeColors>() ?? light;

  @override
  KanSukeColors copyWith({
    Color? sunday,
    Color? saturday,
    Color? holiday,
    Color? washiBase,
    Color? washiFiber,
  }) {
    return KanSukeColors(
      sunday: sunday ?? this.sunday,
      saturday: saturday ?? this.saturday,
      holiday: holiday ?? this.holiday,
      washiBase: washiBase ?? this.washiBase,
      washiFiber: washiFiber ?? this.washiFiber,
    );
  }

  @override
  KanSukeColors lerp(KanSukeColors? other, double t) {
    if (other == null) return this;
    return KanSukeColors(
      sunday: Color.lerp(sunday, other.sunday, t)!,
      saturday: Color.lerp(saturday, other.saturday, t)!,
      holiday: Color.lerp(holiday, other.holiday, t)!,
      washiBase: Color.lerp(washiBase, other.washiBase, t)!,
      washiFiber: Color.lerp(washiFiber, other.washiFiber, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KanSukeColors &&
          other.sunday == sunday &&
          other.saturday == saturday &&
          other.holiday == holiday &&
          other.washiBase == washiBase &&
          other.washiFiber == washiFiber;

  @override
  int get hashCode =>
      Object.hash(sunday, saturday, holiday, washiBase, washiFiber);
}

/// 和紙の生成り地に紺・墨・朱を載せたライトテーマの配色。
const _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: WashiColors.kon,
  onPrimary: WashiColors.kinari,
  primaryContainer: Color(0xFFD7DCE7),
  onPrimaryContainer: WashiColors.kon,
  secondary: WashiColors.shu,
  onSecondary: WashiColors.kinari,
  secondaryContainer: Color(0xFFF1DED8),
  onSecondaryContainer: Color(0xFF4E1710),
  tertiary: WashiColors.matsuba,
  onTertiary: WashiColors.kinari,
  tertiaryContainer: Color(0xFFDCE5D8),
  onTertiaryContainer: Color(0xFF1E3319),
  error: WashiColors.enji,
  onError: WashiColors.kinari,
  errorContainer: Color(0xFFF2DBD9),
  onErrorContainer: Color(0xFF4A1212),
  surface: WashiColors.kinari,
  onSurface: WashiColors.sumi,
  surfaceDim: Color(0xFFE3DBC9),
  surfaceBright: Color(0xFFFDFBF4),
  surfaceContainerLowest: Color(0xFFFFFDF8),
  surfaceContainerLow: Color(0xFFF4EFE2),
  surfaceContainer: WashiColors.torinoko,
  surfaceContainerHigh: Color(0xFFE6DDC9),
  surfaceContainerHighest: Color(0xFFDFD5BE),
  onSurfaceVariant: WashiColors.usuzumi,
  outline: Color(0xFFA69C89),
  outlineVariant: Color(0xFFCBC1AC),
  inverseSurface: WashiColors.sumi,
  onInverseSurface: WashiColors.kinari,
  inversePrimary: WashiColors.aijiro,
);

/// 墨色の地に生成りを載せた夜間の配色。
const _darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: WashiColors.aijiro,
  onPrimary: Color(0xFF12203A),
  primaryContainer: Color(0xFF2C3E60),
  onPrimaryContainer: Color(0xFFD7DCE7),
  secondary: WashiColors.araishu,
  onSecondary: Color(0xFF3D1109),
  secondaryContainer: Color(0xFF5C2418),
  onSecondaryContainer: Color(0xFFF1DED8),
  tertiary: Color(0xFF9FBE97),
  onTertiary: Color(0xFF16290F),
  tertiaryContainer: Color(0xFF2E4A28),
  onTertiaryContainer: Color(0xFFDCE5D8),
  error: Color(0xFFE28A82),
  onError: Color(0xFF3F0D0D),
  errorContainer: Color(0xFF5E1D1D),
  onErrorContainer: Color(0xFFF2DBD9),
  surface: WashiColors.sumi,
  onSurface: Color(0xFFEBE4D5),
  surfaceDim: Color(0xFF191815),
  surfaceBright: Color(0xFF413E38),
  surfaceContainerLowest: Color(0xFF13120F),
  surfaceContainerLow: Color(0xFF2B2925),
  surfaceContainer: Color(0xFF2F2D28),
  surfaceContainerHigh: Color(0xFF3A3833),
  surfaceContainerHighest: Color(0xFF45423C),
  onSurfaceVariant: Color(0xFFB6AE9E),
  outline: Color(0xFF827B6E),
  outlineVariant: Color(0xFF4A463F),
  inverseSurface: WashiColors.kinari,
  onInverseSurface: WashiColors.sumi,
  inversePrimary: WashiColors.kon,
);

ThemeData buildKanSukeTheme() => _buildTheme(_lightScheme, KanSukeColors.light);

ThemeData buildKanSukeDarkTheme() =>
    _buildTheme(_darkScheme, KanSukeColors.dark);

ThemeData _buildTheme(ColorScheme scheme, KanSukeColors kanSukeColors) {
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  // 罫線は墨で引いた細線に見せたいので、Material 既定より細く薄くする。
  const hairline = 0.5;

  return base.copyWith(
    // 和紙テクスチャ（WashiBackground）を全画面の背後に敷くため、Scaffold と
    // AppBar の地は透過させてそれを透かす。
    scaffoldBackgroundColor: Colors.transparent,
    extensions: [kanSukeColors],
    textTheme: _applyMincho(base.textTheme),
    primaryTextTheme: _applyMincho(base.primaryTextTheme),
    appBarTheme: AppBarTheme(
      centerTitle: true,
      // 幟のように、地は和紙のまま・文字は紺で墨書き風にする。
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.primary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: scheme.primary,
        fontFamily: _minchoFallback.first,
        fontFamilyFallback: _minchoFallback.skip(1).toList(),
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: hairline,
      space: hairline,
    ),
    // 和風の意匠は直線基調なので、Material 既定の大きな角丸を落とす。
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    // shape は指定しない。FloatingActionButton.extended にも効いてしまい、
    // ラベル付き FAB のレイアウトが崩れるため（既定の形状で十分収まる）。
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: scheme.outline),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        side: BorderSide(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
    ),
  );
}

/// 見出し（display / headline / title）に明朝体を当てる。
///
/// 本文・ラベルは可読性を優先して既定のゴシックのままにする。小さい字を
/// 明朝で組むと、iPhone の画面では線が細く読みづらくなるため。
TextTheme _applyMincho(TextTheme textTheme) {
  TextStyle? mincho(TextStyle? style) => style?.copyWith(
    fontFamily: _minchoFallback.first,
    fontFamilyFallback: _minchoFallback.skip(1).toList(),
  );

  return textTheme.copyWith(
    displayLarge: mincho(textTheme.displayLarge),
    displayMedium: mincho(textTheme.displayMedium),
    displaySmall: mincho(textTheme.displaySmall),
    headlineLarge: mincho(textTheme.headlineLarge),
    headlineMedium: mincho(textTheme.headlineMedium),
    headlineSmall: mincho(textTheme.headlineSmall),
    titleLarge: mincho(textTheme.titleLarge),
    titleMedium: mincho(textTheme.titleMedium),
  );
}
