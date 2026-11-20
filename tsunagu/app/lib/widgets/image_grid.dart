import 'package:material_ui/material_ui.dart';

import '../api/models.dart';
import 'auth_image.dart';

/// 投稿の画像（1〜4 枚）。タップで拡大表示。
class ImageGrid extends StatelessWidget {
  const ImageGrid({super.key, required this.images, this.maxHeight = 360});

  final List<ImageRef> images;
  final double maxHeight;

  void _open(BuildContext context, int index) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => ImageViewer(images: images, initialIndex: index),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  Widget _tile(BuildContext context, int i) => GestureDetector(
    onTap: () => _open(context, i),
    child: Hero(
      tag: 'img-${images[i].id}',
      child: AuthImage(images[i].url, fit: BoxFit.cover),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();
    const gap = 4.0;
    Widget grid;
    switch (images.length) {
      case 1:
        final ratio = images.first.aspectRatio.clamp(0.75, 2.0);
        grid = ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: AspectRatio(aspectRatio: ratio, child: _tile(context, 0)),
        );
      case 2:
        grid = AspectRatio(
          aspectRatio: 2,
          child: Row(
            children: [
              Expanded(child: _tile(context, 0)),
              const SizedBox(width: gap),
              Expanded(child: _tile(context, 1)),
            ],
          ),
        );
      case 3:
        grid = AspectRatio(
          aspectRatio: 16 / 10,
          child: Row(
            children: [
              Expanded(child: _tile(context, 0)),
              const SizedBox(width: gap),
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: _tile(context, 1)),
                    const SizedBox(height: gap),
                    Expanded(child: _tile(context, 2)),
                  ],
                ),
              ),
            ],
          ),
        );
      default:
        grid = AspectRatio(
          aspectRatio: 16 / 10,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _tile(context, 0)),
                    const SizedBox(width: gap),
                    Expanded(child: _tile(context, 1)),
                  ],
                ),
              ),
              const SizedBox(height: gap),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _tile(context, 2)),
                    const SizedBox(width: gap),
                    Expanded(child: _tile(context, 3)),
                  ],
                ),
              ),
            ],
          ),
        );
    }
    return ClipRRect(borderRadius: BorderRadius.circular(16), child: grid);
  }
}

/// 画像の拡大表示（左右にめくる・ピンチで拡大）。
class ImageViewer extends StatefulWidget {
  const ImageViewer({super.key, required this.images, this.initialIndex = 0});

  final List<ImageRef> images;
  final int initialIndex;

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => InteractiveViewer(
              maxScale: 5,
              child: Center(
                child: Hero(
                  tag: 'img-${widget.images[i].id}',
                  child: AuthImage(widget.images[i].url, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: Colors.white24, foregroundColor: Colors.white),
                    tooltip: '閉じる',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                  const Spacer(),
                  if (widget.images.length > 1)
                    Text(
                      '${_index + 1} / ${widget.images.length}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
