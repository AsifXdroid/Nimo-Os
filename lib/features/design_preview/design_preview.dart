/// Design plates preview (owner review for DECISIONS.md D-008).
///
/// Pure-UI prototypes of the S2 Today dashboard, the S3 reel board and
/// the S1 workspaces list, rendered in the three theme plates from
/// `core/theme.dart`. Sample data only — nothing here touches the
/// database, so the Widget Previewer (web environment, no dart:io/ffi)
/// can render every plate. The composition the owner picks is what the
/// real TODAY / LINK screens get built from in their stages.
///
/// View: Android Studio / VS Code "Flutter Widget Preview" tab, or
/// `flutter widget-preview start` in the project root.
library;

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../core/theme.dart';

// ---------------------------------------------------------------------------
// Preview wrappers — one per plate. Must stay top-level and public so the
// @Preview annotations can reference them as constants.
// ---------------------------------------------------------------------------

Widget calmPlateWrapper(Widget child) => MaterialApp(
      theme: AppTheme.forPlate(AppPlate.calm),
      home: Scaffold(
        appBar: AppBar(title: const Text('Daily Life')),
        body: SafeArea(child: child),
      ),
    );

Widget midnightPlateWrapper(Widget child) => MaterialApp(
      theme: AppTheme.forPlate(AppPlate.midnight),
      home: Scaffold(
        appBar: AppBar(title: const Text('Daily Life')),
        body: SafeArea(child: child),
      ),
    );

Widget warmPlateWrapper(Widget child) => MaterialApp(
      theme: AppTheme.forPlate(AppPlate.warm),
      home: Scaffold(
        appBar: AppBar(title: const Text('Daily Life')),
        body: SafeArea(child: child),
      ),
    );

// ---------------------------------------------------------------------------
// TODAY — prototype of the S2 home dashboard.
// ---------------------------------------------------------------------------

class TodayPreviewBody extends StatelessWidget {
  const TodayPreviewBody({super.key});

  static const _plan = [
    (label: 'Morning workout', done: true),
    (label: 'Review Arabic flashcards', done: true),
    (label: 'Water the plants', done: true),
    (label: 'Build the app UI', done: false),
    (label: 'Read 20 minutes', done: false),
    (label: 'Plan tomorrow', done: false),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = _plan.where((t) => t.done).length;
    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: [
        Text('Thu, 29 Oct', style: theme.textTheme.labelLarge),
        Text('Good evening', style: theme.textTheme.headlineMedium),
        const SizedBox(height: Gap.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text("Today's plan",
                          style: theme.textTheme.titleMedium),
                    ),
                    Text('$done of ${_plan.length} done'),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                LinearProgressIndicator(value: done / _plan.length),
                const SizedBox(height: Gap.sm),
                for (final task in _plan)
                  Row(
                    children: [
                      Icon(
                        task.done
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: task.done
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                      const SizedBox(width: Gap.sm),
                      Text(
                        task.label,
                        style: task.done
                            ? const TextStyle(
                                decoration: TextDecoration.lineThrough)
                            : null,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Gap.md),
        Text('This week', style: theme.textTheme.titleMedium),
        const SizedBox(height: Gap.sm),
        const Wrap(
          spacing: Gap.sm,
          children: [
            Chip(avatar: Icon(Icons.quiz_outlined, size: 18), label: Text('Finish quiz set')),
            Chip(avatar: Icon(Icons.shopping_basket_outlined, size: 18), label: Text('Groceries')),
          ],
        ),
        const SizedBox(height: Gap.md),
        Card(
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Short-term goal', style: theme.textTheme.labelLarge),
                Text('Learn 100 Arabic words',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: Gap.sm),
                const LinearProgressIndicator(value: 0.62),
                const SizedBox(height: Gap.sm),
                const Text('62 of 100 words'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// LINK — prototype of the S3 reel board (square cards, D-003 fallback).
// ---------------------------------------------------------------------------

class ReelsPreviewBody extends StatelessWidget {
  const ReelsPreviewBody({super.key});

  static const _reels = [
    'Flutter tips',
    'Desk setup',
    'Recipe in 15m',
    'Travel hack',
    'Workout form',
    'Design inspo',
    'Arabic verbs',
    'Photo walk',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tileColors = [
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
      scheme.primaryContainer,
      scheme.tertiaryContainer,
      scheme.secondaryContainer,
      scheme.primary,
      scheme.tertiary,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, 0),
          child: Row(
            children: [
              Expanded(
                child: Text('Watch Later',
                    style: theme.textTheme.headlineMedium),
              ),
              Text('${_reels.length + 1} reels',
                  style: theme.textTheme.labelLarge),
            ],
          ),
        ),
        Expanded(
          child: GridView.count(
            crossAxisCount: 3,
            padding: const EdgeInsets.all(Gap.md),
            mainAxisSpacing: Gap.sm,
            crossAxisSpacing: Gap.sm,
            children: [
              for (var i = 0; i < _reels.length; i++)
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        tileColors[i],
                        Color.alphaBlend(Colors.black26, tileColors[i]),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(Gap.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.play_circle_fill,
                          color: Colors.white70, size: 20),
                      const Spacer(),
                      Text(
                        _reels[i],
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              // D-003 designed fallback card: no thumbnail, never broken.
              Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(Gap.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.link, color: scheme.primary, size: 20),
                    const Spacer(),
                    Text('No preview yet',
                        style: theme.textTheme.labelSmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// WS — the S1 workspaces list, card-styled so plates show their character.
// ---------------------------------------------------------------------------

class WorkspacesPreviewBody extends StatelessWidget {
  const WorkspacesPreviewBody({super.key});

  static const _spaces = [
    (name: 'Watch Later', meta: '3 projects · 42 items', icon: Icons.play_circle_outline),
    (name: 'Study', meta: '2 projects · 18 items', icon: Icons.school_outlined),
    (name: 'Home', meta: '4 projects · 9 items', icon: Icons.home_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: [
        for (final space in _spaces)
          Card(
            child: ListTile(
              leading: Icon(space.icon),
              title: Text(space.name),
              subtitle: Text(space.meta),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Previews — every body in every plate (group: Design plates).
// ---------------------------------------------------------------------------

@Preview(
    name: 'Today — Calm Focus',
    group: 'Design plates',
    size: Size(390, 780),
    wrapper: calmPlateWrapper)
@Preview(
    name: 'Today — Midnight',
    group: 'Design plates',
    size: Size(390, 780),
    wrapper: midnightPlateWrapper)
@Preview(
    name: 'Today — Warm Paper',
    group: 'Design plates',
    size: Size(390, 780),
    wrapper: warmPlateWrapper)
Widget todayPlatePreview() => const TodayPreviewBody();

@Preview(
    name: 'Reels — Calm Focus',
    group: 'Design plates',
    size: Size(390, 780),
    wrapper: calmPlateWrapper)
@Preview(
    name: 'Reels — Midnight',
    group: 'Design plates',
    size: Size(390, 780),
    wrapper: midnightPlateWrapper)
@Preview(
    name: 'Reels — Warm Paper',
    group: 'Design plates',
    size: Size(390, 780),
    wrapper: warmPlateWrapper)
Widget reelsPlatePreview() => const ReelsPreviewBody();

@Preview(
    name: 'Workspaces — Calm Focus',
    group: 'Design plates',
    size: Size(390, 780),
    wrapper: calmPlateWrapper)
@Preview(
    name: 'Workspaces — Midnight',
    group: 'Design plates',
    size: Size(390, 780),
    wrapper: midnightPlateWrapper)
@Preview(
    name: 'Workspaces — Warm Paper',
    group: 'Design plates',
    size: Size(390, 780),
    wrapper: warmPlateWrapper)
Widget workspacesPlatePreview() => const WorkspacesPreviewBody();
