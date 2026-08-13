import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/childcare.dart';
import '../../services/childcare_active_office.dart';
import '../../services/childcare_service.dart';
import '../../services/pin_auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ohana_logo_home_button.dart';
import 'class_activities/class_activity_list_screen.dart';
import 'contacts/contact_copy_screen.dart';
import 'contacts/daily_contact_list_screen.dart';
import 'children/weekly_schedule_list_screen.dart';
import 'daily_board/daily_board_screen.dart';
import 'health/temperature_screen.dart';
import 'nap/nap_check_screen.dart';

/// Ohana Kids ホーム画面(childcare_home_enabled=ON時の初期画面)。
/// doc §1.2 の7区分をポップなタイルで表示。未実装区分は「準備中」(disabled)で置き、
/// 各実装フェーズ到達時に結線する。保護者管理はホームに置かない(admin_web側)。
class ChildcareHomeScreen extends StatefulWidget {
  const ChildcareHomeScreen({super.key, required this.service});

  final ChildcareService service;

  @override
  State<ChildcareHomeScreen> createState() => _ChildcareHomeScreenState();
}

class _ChildcareHomeScreenState extends State<ChildcareHomeScreen> {
  late Future<List<ChildcareOffice>> _officesFuture;
  List<ChildcareOffice> _officesCache = const [];
  ChildcareOffice? _selectedOffice;
  final DateTime _businessDate = DateTime.now();
  bool _internalNotesEnabled = false;

  @override
  void initState() {
    super.initState();
    _officesFuture = widget.service.fetchMyChildcareOffices();
    // 施設一覧を黒帯(SessionBanner)の施設プルダウンへ供給し、黒帯からの切替に追随する。
    _officesFuture.then((offices) {
      if (!mounted) return;
      _officesCache = offices;
      childcareOfficeList.value = offices;
    });
    childcareActiveOfficeId.addListener(_onSharedOfficeChanged);
  }

  // 黒帯の施設プルダウン変更に追随(ホームのタイル遷移先officeIdも切り替わる)。
  void _onSharedOfficeChanged() {
    final id = childcareActiveOfficeId.value;
    if (id == null || !mounted || _selectedOffice?.officeId == id) return;
    for (final o in _officesCache) {
      if (o.officeId == id) {
        setState(() => _selectedOffice = o);
        _loadInternalNotesFlag();
        return;
      }
    }
  }

  @override
  void dispose() {
    // childcareモードを離脱(ログアウト等)する際は共通ヘッダーの操作中施設・一覧をクリアする。
    childcareActiveOfficeId.removeListener(_onSharedOfficeChanged);
    childcareActiveOfficeName.value = null;
    childcareActiveOfficeId.value = null;
    childcareOfficeList.value = const [];
    super.dispose();
  }

  Future<void> _loadInternalNotesFlag() async {
    final office = _selectedOffice;
    if (office == null) return;
    final enabled = await widget.service.isChildInternalNotesEnabledForOffice(office.officeId);
    if (mounted) setState(() => _internalNotesEnabled = enabled);
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  void _comingSoon(String label) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label は準備中です')));
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const OhanaLogoHomeButton(),
        leadingWidth: 148,
        toolbarHeight: 48,
        title: const SizedBox.shrink(),
        actions: [
          IconButton(icon: const Icon(Icons.pin_rounded), tooltip: 'PIN設定', onPressed: _setPin),
          IconButton(icon: const Icon(Icons.logout_rounded), tooltip: 'ログアウト', onPressed: _signOut),
        ],
      ),
      body: FutureBuilder<List<ChildcareOffice>>(
        future: _officesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final offices = snapshot.data ?? const [];
          if (offices.isEmpty) {
            return const Center(child: Text('保育業務機能が有効な施設がありません'));
          }
          if (_selectedOffice == null) {
            _selectedOffice = offices.first;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              // build中のNotifier更新を避けフレーム後に反映(共通ヘッダーの操作中施設)。
              childcareActiveOfficeName.value = offices.first.officeName;
              childcareActiveOfficeId.value = offices.first.officeId;
              _loadInternalNotesFlag();
            });
          }
          final office = _selectedOffice!;

          // タイルは可変(園内記録は施設フラグ依存)。1画面に収めるため列数と縦横比を実寸から算出。
          final tiles = <Widget>[
            _HomeTile(
              icon: Icons.dashboard_customize_rounded,
              color: AppColors.skyBlue,
              label: 'デイリーボード',
              onTap: () => _push(DailyBoardScreen(
                service: widget.service,
                officeId: office.officeId,
                businessDate: _businessDate,
                isManager: office.isManager,
              )),
            ),
            _HomeTile(
              icon: Icons.chat_bubble_outline_rounded,
              color: AppColors.skyBlue,
              label: '連絡帳',
              onTap: () => _push(DailyContactListScreen(
                service: widget.service,
                officeId: office.officeId,
                businessDate: _businessDate,
                isManager: office.isManager,
              )),
            ),
            _HomeTile(
              icon: Icons.groups_rounded,
              color: AppColors.leafGreen,
              label: 'クラス活動',
              onTap: () => _push(ClassActivityListScreen(
                service: widget.service,
                officeId: office.officeId,
                businessDate: _businessDate,
                isManager: office.isManager,
              )),
            ),
            _HomeTile(
              icon: Icons.bedtime_rounded,
              color: AppColors.warmOrange,
              label: '午睡チェック',
              onTap: () => _push(NapCheckScreen(
                service: widget.service,
                officeId: office.officeId,
                businessDate: _businessDate,
                isManager: office.isManager,
              )),
            ),
            _HomeTile(
              icon: Icons.thermostat_rounded,
              color: AppColors.punchClockOut,
              label: '健康チェック',
              onTap: () => _push(TemperatureScreen(
                service: widget.service,
                officeId: office.officeId,
                businessDate: _businessDate,
                isManager: office.isManager,
              )),
            ),
            // 週次予定(標準保育時間・園児単位)。専用の園児一覧画面から直接シートを開く
            // (旧: デイリーボード経由の遠回り導線を俊指示で改善)。
            _HomeTile(
              icon: Icons.event_repeat_rounded,
              color: AppColors.leafGreen,
              label: '週次予定',
              onTap: () => _push(WeeklyScheduleListScreen(
                service: widget.service,
                officeId: office.officeId,
              )),
            ),
            _HomeTile(
              icon: Icons.mark_email_unread_rounded,
              color: AppColors.warmOrange,
              label: '保護者からの連絡',
              comingSoon: true,
              onTap: () => _comingSoon('保護者からの連絡'),
            ),
            // 園内記録: child_internal_notes_enabled がONの施設のみ表示。
            // 新規画面は作らず、園児詳細(デイリーボード→園児→園内記録タブ)の既存導線に乗せる。
            if (_internalNotesEnabled)
              _HomeTile(
                icon: Icons.edit_note_rounded,
                color: AppColors.leafGreen,
                label: '園内記録',
                onTap: () => _push(DailyBoardScreen(
                  service: widget.service,
                  officeId: office.officeId,
                  businessDate: _businessDate,
                  isManager: office.isManager,
                )),
              ),
            _HomeTile(
              icon: Icons.support_rounded,
              color: AppColors.skyBlue,
              label: '支援保育',
              comingSoon: true,
              onTap: () => _comingSoon('支援保育'),
            ),
            // 欠席選択(K5でデイリーボード行の欠席トグルへ集約・廃止)。コピーは連絡帳配下へ再編予定。
            _HomeTile(
              icon: Icons.copy_all_rounded,
              color: AppColors.skyBlue,
              label: 'コピー',
              onTap: () => _push(ContactCopyScreen(
                service: widget.service,
                officeId: office.officeId,
                businessDate: _businessDate,
              )),
            ),
          ];

          // 施設選択はホームから撤去(黒帯の施設切替に集約。管理者以上のみ変更可・俊指示)。
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // 画面幅に応じて列数を切替(スマホ=3 / iPad=6目安)。幅ベースのブレークポイントで判定し、
                      // 行数から縦横比を算出して縦スクロールを消す(いずれの幅でも1画面に収める)。
                      const spacing = 12.0;
                      final w = constraints.maxWidth;
                      final cols = w >= 1000
                          ? 6
                          : w >= 820
                              ? 5
                              : w >= 620
                                  ? 4
                                  : 3;
                      final rows = (tiles.length / cols).ceil();
                      final tileW = (constraints.maxWidth - (cols - 1) * spacing) / cols;
                      final tileH = (constraints.maxHeight - (rows - 1) * spacing) / rows;
                      return GridView.count(
                        crossAxisCount: cols,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: spacing,
                        crossAxisSpacing: spacing,
                        childAspectRatio: tileH > 0 ? tileW / tileH : 1.1,
                        children: tiles,
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 次回からのPIN簡易ログイン用に、本人の6桁PINを設定/変更する(要件3)。
  Future<void> _setPin() async {
    final controller = TextEditingController();
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('PIN(6桁)の設定'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('登録済みのiPadで、次回から氏名タップ+PINでログインできます。\n'
                  '全桁同じ・連番(000000/123456等)は使えません。', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                decoration: const InputDecoration(labelText: '6桁のPIN', counterText: ''),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(error!, style: const TextStyle(color: AppColors.punchClockOut, fontSize: 12)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('キャンセル')),
            ElevatedButton(
              onPressed: () async {
                final pin = controller.text.trim();
                if (!RegExp(r'^[0-9]{6}$').hasMatch(pin)) {
                  setDialog(() => error = 'PINは6桁の数字で入力してください');
                  return;
                }
                try {
                  await PinAuthService(Supabase.instance.client).setMyPin(pin);
                  if (ctx.mounted) Navigator.of(ctx).pop(true);
                } catch (e) {
                  setDialog(() => error = e.toString().contains('推測') ? '推測されやすいPINは使えません' : '設定に失敗しました');
                }
              },
              child: const Text('設定'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PINを設定しました')));
    }
  }
}

class _HomeTile extends StatelessWidget {
  const _HomeTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.comingSoon = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final bool comingSoon;

  @override
  Widget build(BuildContext context) {
    // コドモン風: 色付き丸角アイコンバッジ＋下にラベル。軽いカードで視覚的に把握しやすく。
    return Opacity(
      opacity: comingSoon ? 0.5 : 1,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        elevation: 0.5,
        shadowColor: Colors.black26,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: LayoutBuilder(
              builder: (context, c) {
                // タイルの実寸からアイコンバッジ径を決める(小さい画面でも崩れない)。
                final badge = (c.maxHeight * 0.5).clamp(44.0, 76.0);
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: badge,
                          height: badge,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(badge * 0.28),
                          ),
                          child: Icon(icon, color: color, size: badge * 0.52),
                        ),
                        if (comingSoon)
                          Positioned(
                            right: -4,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.warmOrange,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('準備中',
                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
