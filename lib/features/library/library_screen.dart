/// LIBRARY — the merged destination (owner decision
/// 2026-11-12): Learn and Organise live under one bottom-nav
/// destination, following the Goals + Progress precedent
/// (DirectionScreen). One deliberate difference from that
/// precedent: an IndexedStack keeps both screens ALIVE, so
/// switching tabs never loses scroll position or state —
/// Direction's switch-rebuild was judged a defect for these
/// two screens, not copied. Learn is the default tab (the
/// daily, session-first surface); Organise is the lookup.
/// The hosted screens keep their own Scaffold, PageTop and
/// titles, untouched.
library;

import 'package:flutter/material.dart';

import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../items/link_card/thumbnail_service.dart';
import '../learn/learn_screen.dart';
import '../learn/learn_services.dart';
import '../review/review_store.dart';
import '../store.dart';
import '../workspaces/workspaces_screen.dart';

enum LibraryTab { learn, organise }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.learn,
    required this.reviewStore,
    required this.store,
    this.onOpenTopics,
    this.thumbnails,
    this.initialTab = LibraryTab.learn,
  });

  final LearnServices learn;
  final ReviewStore reviewStore;
  final Store store;

  /// Learn's one shell callback, threaded through the host
  /// (the shell owns the Topics route).
  final void Function()? onOpenTopics;
  final ThumbnailService? thumbnails;

  /// Where the tabs open. Learn by default; the parameter
  /// exists so tests can land on Organise directly.
  final LibraryTab initialTab;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late LibraryTab _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageTop(
        // D-052: solid canvas, same as the Direction host.
        child: Column(
          children: [
            _tabStrip(context),
            Expanded(
              child: IndexedStack(
                index: _tab.index,
                children: [
                  LearnScreen(
                    learn: widget.learn,
                    reviewStore: widget.reviewStore,
                    store: widget.store,
                    onOpenTopics: widget.onOpenTopics,
                  ),
                  WorkspacesScreen(
                    store: widget.store,
                    learn: widget.learn,
                    thumbnails: widget.thumbnails,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The tab strip (redesign R3, B system): a segmented
  /// capsule in the nav bar's language — a raised track,
  /// the selected segment a light pill. Both labels stay
  /// plain text so the strip reads at a glance.
  Widget _tabStrip(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    Widget tab(LibraryTab value, String label) {
      final selected = _tab == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          child: InkWell(
            onTap: () => setState(() => _tab = value),
            borderRadius: BorderRadius.circular(RadiusToken.round),
            child: Container(
              constraints: const BoxConstraints(minHeight: Space.touch),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: Space.s2),
              decoration: BoxDecoration(
                color: selected
                    ? (dark
                          ? Colors.white.withValues(alpha: 0.14)
                          : scheme.surface)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(RadiusToken.round),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.page, Space.s3, Space.page, 0),
      child: Container(
        padding: const EdgeInsets.all(Space.s1),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(RadiusToken.round),
        ),
        child: Row(
          children: [
            tab(LibraryTab.learn, 'Learn'),
            tab(LibraryTab.organise, 'Organise'),
          ],
        ),
      ),
    );
  }
}
