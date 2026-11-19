import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../theme/vamos_theme.dart';
import 'glass.dart';

/// 画面上部のヘッダー（ロゴ＋水色グラデーションの細線）。
/// iOS 26 以降はリキッドグラス、それ以外は白地で表示する。
class VamosSliverAppBar extends StatelessWidget {
  const VamosSliverAppBar({super.key, this.actions = const []});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      toolbarHeight: 56,
      titleSpacing: 20,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      title: Image.asset('assets/vamos/images/logo.png', height: 30, semanticLabel: 'VAMOS'),
      actions: actions,
      flexibleSpace: const Stack(
        children: [
          Positioned.fill(child: ScrollEdgeBackground()),
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 3,
              width: double.infinity,
              child: DecoratedBox(decoration: BoxDecoration(gradient: VamosColors.gradient)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 浮いたタブバーの下に隠れないよう、一覧の最後に入れる余白
class BottomBarSpacer extends StatelessWidget {
  const BottomBarSpacer({super.key});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 12));
  }
}

/// 字間を広げた小さな英字ラベル（例：INTERVIEW）。
class SectionKicker extends StatelessWidget {
  const SectionKicker(this.text, {super.key, this.withRule = false});

  final String text;
  final bool withRule;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 2.4,
        color: VamosColors.primary,
      ),
    );
    if (!withRule) return label;
    return Row(
      children: [
        Container(width: 28, height: 2, color: VamosColors.primary),
        const SizedBox(width: 10),
        label,
      ],
    );
  }
}

/// 一覧ページの冒頭（英字ラベル・見出し・説明・件数）。
class PageIntro extends StatelessWidget {
  const PageIntro({
    super.key,
    required this.kicker,
    required this.title,
    required this.description,
    this.count,
  });

  final String kicker;
  final String title;
  final String description;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionKicker(kicker),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.3)),
          const SizedBox(height: 12),
          Text(description, style: const TextStyle(fontSize: 14, height: 1.8, color: VamosColors.textMuted)),
          if (count != null) ...[
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 13, color: VamosColors.textMuted),
                children: [
                  const TextSpan(text: '全 '),
                  TextSpan(
                    text: '$count',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: VamosColors.primary,
                    ),
                  ),
                  const TextSpan(text: ' 件'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum ChipStyle { soft, outline, filled }

/// カテゴリーの丸いラベル。
class CategoryChip extends StatelessWidget {
  const CategoryChip(this.label, {super.key, this.style = ChipStyle.soft});

  final String label;
  final ChipStyle style;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, border) = switch (style) {
      ChipStyle.soft => (VamosColors.primaryLight, VamosColors.primary, Colors.transparent),
      ChipStyle.outline => (VamosColors.surface, VamosColors.primary, VamosColors.primary),
      ChipStyle.filled => (VamosColors.primary, Colors.white, Colors.transparent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: foreground)),
    );
  }
}

/// 白地・角丸・細い枠線のカード。
class VamosCard extends StatelessWidget {
  const VamosCard({super.key, required this.child, this.onTap, this.padding = EdgeInsets.zero});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: VamosColors.surface,
        borderRadius: BorderRadius.circular(VamosRadius.large),
        border: Border.all(color: VamosColors.borderLight),
        boxShadow: VamosShadows.card,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(VamosRadius.large),
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(VamosRadius.large),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// イニシャルの丸いアイコン（例：Vamos編集部 → V）。
class InitialAvatar extends StatelessWidget {
  const InitialAvatar(this.name, {super.key, this.size = 28});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: VamosColors.primaryLight, shape: BoxShape.circle),
      child: Text(
        initial,
        style: TextStyle(fontSize: size * 0.45, fontWeight: FontWeight.w700, color: VamosColors.primary),
      ),
    );
  }
}

/// 水色グラデーションの丸いボタン（ふんわり光る影つき）。
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, required this.onPressed, this.expand = false});

  final String label;
  final VoidCallback? onPressed;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: VamosColors.buttonGradient,
          borderRadius: BorderRadius.circular(999),
          boxShadow: enabled ? VamosShadows.glow : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 白地に細い枠線の丸いボタン。
class OutlinePillButton extends StatelessWidget {
  const OutlinePillButton({super.key, required this.label, required this.onPressed, this.expand = false});

  final String label;
  final VoidCallback? onPressed;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: VamosColors.surface,
        foregroundColor: VamosColors.text,
        side: const BorderSide(color: VamosColors.border),
        shape: const StadiumBorder(),
        minimumSize: expand ? const Size.fromHeight(50) : const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}

/// 著者・日付などの1行メタ情報。
class AuthorLine extends StatelessWidget {
  const AuthorLine({super.key, required this.author, required this.date});

  final String author;
  final String date;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InitialAvatar(author),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
        Text(date, style: const TextStyle(fontSize: 12, color: VamosColors.textLight)),
      ],
    );
  }
}

/// 記事の画像。API の URL（http…）とアプリ同梱の画像（assets/…）のどちらにも対応する。
class AssetPhoto extends StatelessWidget {
  const AssetPhoto(this.path, {super.key, this.fit = BoxFit.cover});

  final String? path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: VamosColors.surfaceMuted,
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, color: VamosColors.textLight),
    );
    final p = path;
    if (p == null || p.isEmpty) return placeholder;
    if (p.startsWith('http')) {
      // オフラインで読み込めない場合は、同じ画像がアプリに同梱されていればそれを使う
      final bundled = p.contains('/media/') ? 'assets/vamos/images/${p.split('/media/').last}' : null;
      return Image.network(
        p,
        fit: fit,
        errorBuilder: (_, _, _) =>
            bundled == null ? placeholder : Image.asset(bundled, fit: fit, errorBuilder: (_, _, _) => placeholder),
        frameBuilder: (context, child, frame, loadedSync) => AnimatedOpacity(
          opacity: loadedSync || frame != null ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          child: frame == null && !loadedSync ? ColoredBox(color: VamosColors.surfaceMuted, child: child) : child,
        ),
      );
    }
    return Image.asset(p, fit: fit, errorBuilder: (_, _, _) => placeholder);
  }
}

/// API に接続できず、前回のデータや同梱データを表示していることを知らせる帯。
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.message, required this.onRetry});

  /// 表示中のデータに合わせた案内文を作る
  factory OfflineBanner.forFeed(Feed feed, {required VoidCallback onRetry}) {
    final at = feed.updatedAt;
    String two(int n) => n.toString().padLeft(2, '0');
    final message = feed.source == DataSource.cached
        ? 'オフライン表示中：${at.month}/${at.day} ${two(at.hour)}:${two(at.minute)} に取得した内容です'
        : 'オフライン表示中：アプリ内のデータを表示しています';
    return OfflineBanner(message: message, onRetry: onRetry);
  }

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(VamosRadius.large),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 18, color: Color(0xFFC2410C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF9A3412), fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('再接続')),
        ],
      ),
    );
  }
}

/// 読み込みに失敗したときの表示。
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 40, color: VamosColors.textLight),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: VamosColors.textMuted)),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinePillButton(label: 'もう一度読み込む', onPressed: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}
