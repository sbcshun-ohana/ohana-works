import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/role_display.dart';
import '../models/childcare.dart';
import '../services/childcare_active_office.dart';
import '../services/push_service.dart';
import '../services/secure_device_store.dart';
import '../services/session_identity.dart';
import '../theme/app_theme.dart';

/// 全画面の最上部に常時表示する「ログイン中: 氏名(役職)」バナー＋ログアウト導線。
/// MaterialApp の builder で Navigator の上に差し込み、どの画面でも見えるようにする。
/// 未ログイン時は何も表示しない(ログイン画面ではバナーを出さない)。
class SessionBanner extends StatefulWidget {
  const SessionBanner({super.key});

  @override
  State<SessionBanner> createState() => _SessionBannerState();
}

class _SessionBannerState extends State<SessionBanner> {
  SessionIdentity? _identity;
  String? _officeName;
  StreamSubscription<AuthState>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((_) => _load());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final identity = await fetchMySessionIdentity();
    // 施設名: 登録端末(Ohana Kids)なら端末の施設、なければ(Ohana Staff等)所属施設。
    final device = await SecureDeviceStore().load();
    if (mounted) {
      setState(() {
        _identity = identity;
        _officeName = device?.officeName ?? identity?.homeOfficeName;
      });
    }
  }

  /// 黒帯の施設表示。childcareで複数施設+管理者以上のときだけ小さなプルダウン(施設切替)、
  /// それ以外は従来どおりテキスト表示(操作中施設→端末/所属施設の順でフォールバック)。
  /// 切替は childcareActiveOfficeId を更新し、各画面(デイリーボード等)が listen して追随する。
  Widget _officeArea() {
    return ValueListenableBuilder<List<ChildcareOffice>>(
      valueListenable: childcareOfficeList,
      builder: (context, offices, _) {
        // 施設切替は管理者以上のみ(一般職員は施設を変更しない運用)。
        final canSwitch = offices.length > 1 && offices.any((o) => o.isManager);
        if (!canSwitch) {
          return ValueListenableBuilder<String?>(
            valueListenable: childcareActiveOfficeName,
            builder: (context, activeOffice, _) {
              final officeName = activeOffice ?? _officeName;
              if (officeName == null) return const SizedBox.shrink();
              return Text(
                ' / $officeName',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              );
            },
          );
        }
        return ValueListenableBuilder<String?>(
          valueListenable: childcareActiveOfficeId,
          builder: (context, selectedId, _) {
            final valid = offices.any((o) => o.officeId == selectedId) ? selectedId : offices.first.officeId;
            return Padding(
              padding: const EdgeInsets.only(left: 6),
              child: DropdownButton<String>(
                value: valid,
                isDense: true,
                underline: const SizedBox.shrink(),
                dropdownColor: AppColors.textPrimary,
                iconEnabledColor: Colors.white70,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                items: [
                  for (final o in offices)
                    DropdownMenuItem(value: o.officeId, child: Text(o.officeName)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  final office = offices.firstWhere((o) => o.officeId == v);
                  childcareActiveOfficeId.value = office.officeId;
                  childcareActiveOfficeName.value = office.officeName;
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _signOut() async {
    // signOut 後は my_employee_id() が null になり RLS で削除できないため、必ず前に実行。
    // staff以外(Firebase未初期化)では PushService 側が例外を握りつぶす no-op。
    await PushService(Supabase.instance.client).unregisterCurrentDevice();
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final identity = _identity;
    if (Supabase.instance.client.auth.currentUser == null || identity == null) {
      return const SizedBox.shrink();
    }
    return Material(
      color: AppColors.textPrimary,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.account_circle_rounded, size: 20, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      'ログイン中: ${identity.name}(${roleDisplayName(identity.roleCode)})',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _officeArea(),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout_rounded, size: 16, color: Colors.white),
              label: const Text('ログアウト', style: TextStyle(color: Colors.white, fontSize: 13)),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
            ),
          ],
        ),
      ),
    );
  }
}
