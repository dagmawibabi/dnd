import 'package:flutter/material.dart';

import '../../theme/ui.dart';

/// Full-screen, zoomable viewer for portraits, scenes and maps.
Future<void> openImageViewer(
  BuildContext context, {
  required WidgetBuilder builder,
  required String title,
  String? subtitle,
  double aspectRatio = 1,
  List<Widget> actions = const [],
}) {
  return Navigator.of(context).push(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, a, b) => _Viewer(builder: builder, title: title, subtitle: subtitle, aspectRatio: aspectRatio, actions: actions),
    transitionsBuilder: (ctx, a, b, child) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(a), child: child)),
  ));
}

class _Viewer extends StatefulWidget {
  const _Viewer({required this.builder, required this.title, this.subtitle, required this.aspectRatio, required this.actions});
  final WidgetBuilder builder;
  final String title;
  final String? subtitle;
  final double aspectRatio;
  final List<Widget> actions;

  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  final _ctrl = TransformationController();
  bool _chrome = true;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => setState(() => _chrome = !_chrome),
            onDoubleTap: () => _ctrl.value = _ctrl.value.getMaxScaleOnAxis() > 1.1 ? Matrix4.identity() : (Matrix4.identity()..scaleByDouble(2.2, 2.2, 1, 1)),
            child: InteractiveViewer(
              transformationController: _ctrl,
              minScale: 1,
              maxScale: 6,
              child: Center(
                child: LayoutBuilder(builder: (ctx, box) {
                  var w = box.maxWidth;
                  var h = w / widget.aspectRatio;
                  if (h > box.maxHeight) {
                    h = box.maxHeight;
                    w = h * widget.aspectRatio;
                  }
                  return SizedBox(width: w, height: h, child: widget.builder(context));
                }),
              ),
            ),
          ),
        ),
        AnimatedOpacity(
          opacity: _chrome ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: IgnorePointer(
            ignoring: !_chrome,
            child: Column(children: [
              Container(
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xCC000000), Colors.transparent])),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
                    child: Row(children: [
                      IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(widget.title, style: T.h3(color: Colors.white), overflow: TextOverflow.ellipsis),
                          if (widget.subtitle != null) Text(widget.subtitle!, style: T.caption(color: Colors.white70), overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                      ...widget.actions,
                    ]),
                  ),
                ),
              ),
              const Spacer(),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text('Pinch or double-tap to zoom', style: T.caption(color: Colors.white54)),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
