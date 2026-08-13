import 'package:flutter/foundation.dart';

/// childcareモードで「現在操作中の施設名」を全画面共通ヘッダー(SessionBanner)へ伝えるための共有状態。
///
/// Ohana Kids は端末が初期施設に登録されているため、SessionBanner既定の
/// 「端末の施設 / 所属施設」だけでは施設プルダウンの切替に追随できない(Y4)。
/// childcareホームの施設選択でこの値を更新し、SessionBannerが優先参照することで
/// 黒帯の施設名を現在操作中の施設に一致させる。
/// Ohana Staff等 非childcareでは null のまま(既定の端末/所属施設表示にフォールバック)。
final ValueNotifier<String?> childcareActiveOfficeName = ValueNotifier<String?>(null);
