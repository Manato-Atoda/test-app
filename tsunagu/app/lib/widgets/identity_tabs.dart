import 'package:material_ui/material_ui.dart';

import '../api/models.dart';
import '../screens/profile_edit_screen.dart';
import '../state/app_scope.dart';
import '../theme.dart';

/// 発信者の切り替え（実名 / 部署 / 匿名）。使えないものは理由つきで無効にする。
class IdentityTabs extends StatelessWidget {
  const IdentityTabs({super.key, required this.value, required this.onChanged, this.enabled = true});

  final Identity value;
  final ValueChanged<Identity> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = context.m;
    final features = state.company?.features ?? const CompanyFeatures();
    // 管理者がどちらもオフにしているときは、切り替え自体を出さない
    if (!features.identityDepartment && !features.identityAnonymous) return const SizedBox.shrink();

    Widget tab(Identity identity) {
      final reason = state.identityUnavailableReason(identity);
      final selected = value == identity;
      final available = reason == null;
      final name = state.identityPreview(identity);
      return Expanded(
        child: Tooltip(
          message: reason ?? '「$name」として表示されます',
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: !enabled
                ? null
                : () {
                    if (available) {
                      onChanged(identity);
                    } else {
                      _explain(context, identity, reason);
                    }
                  },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
              decoration: BoxDecoration(
                color: selected ? p.surfaceElevated : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                boxShadow: selected
                    ? const [BoxShadow(color: Color(0x140F172A), blurRadius: 6, offset: Offset(0, 1))]
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    identity.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: !available ? p.muted.withValues(alpha: 0.5) : (selected ? p.accent : p.muted),
                    ),
                  ),
                  Text(
                    available ? name : '未設定',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: p.muted.withValues(alpha: available ? 1 : 0.5)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.borderSoft, borderRadius: BorderRadius.circular(999)),
      child: Row(
        children: [
          tab(Identity.real),
          if (features.identityDepartment) tab(Identity.department),
          if (features.identityAnonymous) tab(Identity.anonymous),
        ],
      ),
    );
  }

  void _explain(BuildContext context, Identity identity, String reason) {
    final canFix = identity == Identity.anonymous && reason.contains('あだ名');
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${identity.label}では投稿できません'),
        content: Text(reason),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる')),
          if (canFix)
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProfileEditScreen()));
              },
              child: const Text('あだ名を設定する'),
            ),
        ],
      ),
    );
  }
}
