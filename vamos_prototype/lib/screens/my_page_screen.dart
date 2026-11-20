import 'package:flutter/material.dart';

import '../config.dart';
import '../data/api_client.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services/push_service.dart';
import '../theme/vamos_theme.dart';
import '../widgets/adaptive.dart';
import '../widgets/common.dart';
import 'auth_screens.dart';
import 'interview_screens.dart';

/// マイページ（ゲスト／ログイン中で表示を切り替える）
class MyPageScreen extends StatelessWidget {
  const MyPageScreen({super.key, required this.feed});

  final Feed feed;

  @override
  Widget build(BuildContext context) {
    final repository = VamosRepository.instance;
    return CustomScrollView(
      slivers: [
        const VamosSliverAppBar(),
        SliverPadding(
          padding: Adaptive.horizontal(context, maxWidth: 640).copyWith(top: 24, bottom: 40),
          sliver: SliverList.list(
            children: [
              ValueListenableBuilder<Session?>(
                valueListenable: repository.session,
                builder: (context, session, _) =>
                    session == null ? const _GuestCard() : _ProfileCard(user: session.user),
              ),
              const SizedBox(height: 20),
              const _NotificationCard(),
              const SizedBox(height: 28),
              const SectionKicker('Saved'),
              const SizedBox(height: 8),
              const Text('保存したインタビュー', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              ValueListenableBuilder<Set<String>>(
                valueListenable: repository.saved,
                builder: (context, saved, _) => _SavedList(
                  interviews: feed.interviews.where((i) => saved.contains(i.slug)).toList(),
                ),
              ),
            ],
          ),
        ),
        const BottomBarSpacer(),
      ],
    );
  }
}

class _GuestCard extends StatelessWidget {
  const _GuestCard();

  void _openAuth(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AuthEmailScreen()),
      );

  @override
  Widget build(BuildContext context) {
    return VamosCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              InitialAvatar('ゲスト', size: 44),
              SizedBox(width: 12),
              Text('ゲストさん', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '無料登録すると、気になる企業をフォローして、説明会やインターンの最新情報を受け取れます。',
            style: TextStyle(fontSize: 13.5, height: 1.8, color: VamosColors.textMuted),
          ),
          const SizedBox(height: 16),
          GradientButton(label: '無料で新規登録', onPressed: () => _openAuth(context), expand: true),
          const SizedBox(height: 10),
          OutlinePillButton(label: 'ログイン', onPressed: () => _openAuth(context), expand: true),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.user});

  final UserAccount user;

  @override
  Widget build(BuildContext context) {
    final name = user.displayName.isEmpty ? '（未設定）' : user.displayName;
    final tags = [...user.statuses, ...user.interests, ...user.areas];
    return VamosCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialAvatar(user.displayName.isEmpty ? user.email : user.displayName, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$nameさん', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    Text(user.email, style: const TextStyle(fontSize: 12, color: VamosColors.textLight)),
                  ],
                ),
              ),
            ],
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final tag in tags) CategoryChip(tag)]),
          ],
          if (!user.profileCompleted) ...[
            const SizedBox(height: 14),
            const Text(
              'プロフィールを設定すると、あなたに合う企業・記事をおすすめできます。',
              style: TextStyle(fontSize: 12.5, color: VamosColors.textMuted),
            ),
          ],
          const SizedBox(height: 16),
          OutlinePillButton(
            label: user.profileCompleted ? 'プロフィールを編集' : 'プロフィールを設定',
            expand: true,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => OnboardingScreen(editing: user.profileCompleted),
            )),
          ),
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: () async {
                await VamosRepository.instance.logout();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ログアウトしました')));
                }
              },
              child: const Text('ログアウト', style: TextStyle(color: VamosColors.textMuted)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 通知の設定（試作では iOS の通知の仕組みをそのまま使う）
class _NotificationCard extends StatefulWidget {
  const _NotificationCard();

  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard> {
  bool _busy = false;

  Future<void> _enable() async {
    final repository = VamosRepository.instance;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final registration = await PushService.enable();
      if (!registration.granted) {
        messenger.showSnackBar(const SnackBar(content: Text('通知が許可されませんでした。「設定」アプリから変更できます。')));
        return;
      }
      await repository.registerDevice(platform: registration.platform, token: registration.token);
      repository.notificationsEnabled.value = true;
      messenger.showSnackBar(const SnackBar(content: Text('通知をオンにしました')));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('通知先を登録できませんでした：${error.message}')));
    } on UnsupportedError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message ?? 'この端末では通知に対応していません')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: VamosRepository.instance.notificationsEnabled,
      builder: (context, enabled, _) => VamosCard(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: VamosColors.primaryLight,
                    borderRadius: BorderRadius.circular(VamosRadius.medium),
                  ),
                  child: const Icon(Icons.notifications_active_outlined, color: VamosColors.primary),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('新着のお知らせ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      Text(
                        '新しいインタビューの公開をお知らせします',
                        style: TextStyle(fontSize: 12, color: VamosColors.textMuted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: enabled,
                  onChanged: _busy || enabled ? null : (_) => _enable(),
                ),
              ],
            ),
            if (enabled)
              Padding(
                padding: const EdgeInsets.only(top: 10, right: 8),
                child: Text(
                  '試作：パソコンのブラウザで ${AppConfig.adminUrl} を開くと、通知の配信を試せます。',
                  style: const TextStyle(fontSize: 11.5, height: 1.6, color: VamosColors.textLight),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SavedList extends StatelessWidget {
  const _SavedList({required this.interviews});

  final List<Interview> interviews;

  @override
  Widget build(BuildContext context) {
    if (interviews.isEmpty) {
      return const VamosCard(
        padding: EdgeInsets.all(20),
        child: Text(
          'まだありません。インタビューの右上にある保存ボタンで、ここに追加できます。',
          style: TextStyle(fontSize: 13.5, height: 1.8, color: VamosColors.textMuted),
        ),
      );
    }
    return Column(
      children: [
        for (final interview in interviews)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: VamosCard(
              onTap: () => openInterview(context, interview),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(VamosRadius.medium),
                    child: SizedBox(width: 96, height: 54, child: AssetPhoto(interview.thumbnail)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      interview.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
