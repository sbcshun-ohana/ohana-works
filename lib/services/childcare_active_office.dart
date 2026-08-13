import 'package:flutter/foundation.dart';

import '../models/childcare.dart';

/// childcareモードで「現在操作中の施設」を全画面共通ヘッダー(SessionBanner)と共有するための状態。
///
/// Ohana Kids は端末が初期施設に登録されているため、SessionBanner既定の
/// 「端末の施設 / 所属施設」だけでは施設切替に追随できない(Y4)。
/// さらに施設切替UIは黒帯(SessionBanner)へ集約する(俊指示 2026-08-13):
///  - childcareOfficeList: アクセス可能な保育施設一覧(ホーム/デイリーボードのロード時に設定)。
///  - childcareActiveOfficeId: 現在操作中の施設ID。黒帯のプルダウンが更新し、各画面が listen して追随。
///  - childcareActiveOfficeName: 表示用の施設名(従来どおり)。
/// 施設切替は管理者以上のみ(一般職員は変更しない運用)。黒帯側で
/// 「一覧に isManager=true の施設がある」ことをゲートに使う。
/// Ohana Staff等 非childcareでは全て初期値のまま(黒帯は既定の端末/所属施設表示)。
final ValueNotifier<String?> childcareActiveOfficeName = ValueNotifier<String?>(null);
final ValueNotifier<String?> childcareActiveOfficeId = ValueNotifier<String?>(null);
final ValueNotifier<List<ChildcareOffice>> childcareOfficeList = ValueNotifier<List<ChildcareOffice>>(const []);
