/// DIRECTION (D-045) — one primary destination holding Goals
/// and Progress as internal tabs.
///
/// Both screens are hosted exactly as they were built: their
/// own Scaffold, PageTop and titles are untouched (their
/// standalone tests depend on them). This host adds only the
/// tab strip — hairline-ruled text tabs in the D-039 language,
/// no pills — and applies PageTop once for the strip; the
/// hosted screens' own PageTop then sees the inset already
/// stripped and adds nothing.
///
/// The tab choice is ordinary screen state: leaving the
/// destination disposes it (the shell's standing behaviour),
/// so re-entry shows [initialTab]. The shell passes a
/// non-default initial tab only through its one-shot request
/// (Today's streak chip → Progress).
library;

import 'package:flutter/material.dart';

import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../goals/goals_screen.dart';
import '../goals/goals_store.dart';
import '../progress/progress_screen.dart';
import '../progress/progress_store.dart';
import '../review/review_store.dart';
import '../today/today_store.dart';

enum DirectionTab { goals, progress }

class DirectionScreen extends StatefulWidget {
  const DirectionScreen({
    super.key,
    required this.goalsStore,
    required this.progressStore,
    required this.todayStore,
    required this.reviewStore,
    this.initialTab = DirectionTab.goals,
  });

  final GoalsStore goalsStore;
  final ProgressStore progressStore;
  final TodayStore todayStore;
  final ReviewStore reviewStore;

  /// Where the tabs open. Goals by default; the shell's
  /// one-shot request passes Progress for the streak chip.
  final DirectionTab initialTab;

  @override
  State<DirectionScreen> createState() => _DirectionScreenState();
}

class _DirectionScreenState extends State<DirectionScreen> {
  late DirectionTab _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageTop(
        child: Column(
          children: [
            _tabStrip(context),
            Expanded(
              child: switch (_tab) {
                DirectionTab.goals =>
                  GoalsScreen(goalsStore: widget.goalsStore),
                DirectionTab.progress => ProgressScreen(
                    progressStore: widget.progressStore,
                    todayStore: widget.todayStore,
                    reviewStore: widget.reviewStore,
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }

  /// The tab strip: two text tabs on a hairline, the selected
  /// one in ink with a short mint rule beneath it.
  Widget _tabStrip(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget tab(DirectionTab value, String label) {
      final selected = _tab == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          child: InkWell(
            onTap: () => setState(() => _tab = value),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: Space.s3),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected ? scheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: selected
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          tab(DirectionTab.goals, 'Goals'),
          tab(DirectionTab.progress, 'Progress'),
        ],
      ),
    );
  }
}
