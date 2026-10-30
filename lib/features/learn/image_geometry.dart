/// LEARN engine — the letterbox-safe image surface (S5 step
/// C2a, §R8.5).
///
/// §R8.5's #1 image-point bug is letterbox offset: with
/// BoxFit.contain the rendered image does not fill its widget
/// box, so widget-normalised tap coordinates are NOT
/// image-normalised coordinates. [containRect] computes the rect
/// the image actually occupies inside the box; [toNormalised]
/// converts a tap in box space into image space through that
/// rect, returning null for taps in the letterbox bands (they
/// are ignored, never graded as misses at the image edge).
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The rect an image of [imageSize] occupies when rendered with
/// BoxFit.contain inside a box of [box]: scaled by the smaller
/// of the two axis scales and centred on both axes.
Rect containRect(Size box, Size imageSize) {
  if (box.isEmpty || imageSize.isEmpty) return Rect.zero;
  final scale = math.min(
    box.width / imageSize.width,
    box.height / imageSize.height,
  );
  final w = imageSize.width * scale;
  final h = imageSize.height * scale;
  return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
}

/// Convert a tap at [local] (box space) into image-normalised
/// 0–1 coordinates through [displayed] (the rect from
/// [containRect]). Returns null when the tap lands outside the
/// displayed image — i.e. in the letterbox area. Edge taps count
/// as inside (a tap exactly on the border is 0.0 / 1.0).
Offset? toNormalised(Offset local, Rect displayed) {
  if (displayed.isEmpty) return null;
  if (local.dx < displayed.left ||
      local.dx > displayed.right ||
      local.dy < displayed.top ||
      local.dy > displayed.bottom) {
    return null;
  }
  return Offset(
    (local.dx - displayed.left) / displayed.width,
    (local.dy - displayed.top) / displayed.height,
  );
}

/// A tappable image that is letterbox-safe by construction.
///
/// Discovers the image's pixel size, renders it with
/// BoxFit.contain inside a LayoutBuilder, and forwards taps as
/// image-normalised coordinates via [onTapNormalised] — taps in
/// the letterbox area produce NO callback. When [marker] (a
/// normalised offset) is given it is drawn as a circle centred
/// on that point of the DISPLAYED image; its pixel radius is
/// [markerRadius] × the shorter side of the displayed rect when
/// [markerRadius] is given (the same shorter-side unit grading
/// uses, §R4.1), else a fixed small radius. [markerColor]
/// overrides the ring colour (theme primary by default) — the
/// image-point card uses it to tint the ring by correctness.
///
/// Needs a bounded height from its parent (it fills the space
/// it is given). Shows a neutral placeholder while the image
/// size is being discovered, and on load error.
class ImagePointSurface extends StatefulWidget {
  const ImagePointSurface({
    super.key,
    required this.file,
    this.onTapNormalised,
    this.marker,
    this.markerRadius,
    this.markerColor,
    this.interactive = true,
  });

  final File file;
  final ValueChanged<Offset>? onTapNormalised;
  final Offset? marker;
  final double? markerRadius;
  final Color? markerColor;
  final bool interactive;

  @override
  State<ImagePointSurface> createState() => _ImagePointSurfaceState();
}

class _ImagePointSurfaceState extends State<ImagePointSurface> {
  Size? _imageSize;
  bool _failed = false;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(ImagePointSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _imageSize = null;
      _failed = false;
      _resolve();
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  void _resolve() {
    _detach();
    final stream = FileImage(widget.file).resolve(
      createLocalImageConfiguration(context),
    );
    _stream = stream;
    _listener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        setState(() {
          _imageSize = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          );
          _failed = false;
        });
      },
      onError: (_, _) {
        if (!mounted) return;
        setState(() => _failed = true);
      },
    );
    stream.addListener(_listener!);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_failed) {
      return ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final imageSize = _imageSize;
    if (imageSize == null) {
      return ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = Size(constraints.maxWidth, constraints.maxHeight);
        final displayed = containRect(box, imageSize);
        final markerColor = widget.markerColor ?? scheme.primary;
        return ColoredBox(
          color: scheme.surfaceContainerLow,
          child: Stack(
            children: [
              // The image fills exactly the contain rect (same
              // aspect, so BoxFit.fill does not distort) — what
              // containRect computes IS where the pixels are.
              Positioned.fromRect(
                rect: displayed,
                child: Image.file(widget.file, fit: BoxFit.fill),
              ),
              if (widget.marker != null)
                _marker(displayed, markerColor),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    if (!widget.interactive) return;
                    final callback = widget.onTapNormalised;
                    if (callback == null) return;
                    final n = toNormalised(details.localPosition, displayed);
                    if (n != null) callback(n);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _marker(Rect displayed, Color color) {
    final marker = widget.marker!;
    final radiusPx = widget.markerRadius != null
        ? widget.markerRadius! *
              math.min(displayed.width, displayed.height)
        : 14.0;
    return Positioned(
      left: displayed.left + marker.dx * displayed.width - radiusPx,
      top: displayed.top + marker.dy * displayed.height - radiusPx,
      width: radiusPx * 2,
      height: radiusPx * 2,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.25),
            border: Border.all(color: color, width: 3),
          ),
        ),
      ),
    );
  }
}
