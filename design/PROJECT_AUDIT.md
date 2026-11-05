# PROJECT AUDIT: NIMO ARCHITECTURE & UI INVENTORY
Generated: November 4, 2026
Author: Principal Product Design & Architecture Engineering Team

## 1. Executive Summary
Nimo is a private, offline-first personal digital environment designed for comprehensive self-development and structured life organization. It operates on an internal continuous daily rhythm:
`Plan (Morning) -> Track / Capture (Daytime) -> Learn / Spaced Repetition -> Day Close (Evening Reflection) -> Progress & Review`.

The application currently has a solid operational backend (SQLite via `sqflite` on Android and `sqflite_common_ffi` on Linux desktop, hybrid logical clocks `hlc.dart` for offline CRDT sync readiness, local file and PDF storage, and deterministic unit-tested business stores). 

However, its visual surface has been divided between traditional Material 3 containers, neo-brutalist experimental strokes, and early spatial widgets. This master redesign replaces the existing visual shell with a cohesive **Soft Neutral Spatial — Architectural Minimalism** design system while preserving 100% of the underlying business logic, models, and 647 test assertions.

---

## 2. Screen & Feature Inventory

| Area | Primary Screen | Store / Service | Current State & Redesign Plan |
|---|---|---|---|
| **Today / Home** | `TodayScreen` (`lib/features/today/today_screen.dart`) | `TodayStore`, `ReviewStore`, `Store`, `GoalsStore`, `LearnStore` | Core hub. Needs full spatial reorganization: floating capsule nav, tactile 4-action hub, living timeline, score wells, daily routine cards, and integrated mascot branding. |
| **Workspaces / Projects** | `WorkspacesScreen`, `ProjectsScreen` (`lib/features/workspaces/`, `lib/features/projects/`) | `Store` | Workspace -> Project hierarchy. Currently heavy with plain list tiles; needs spatial project cards with progress gauges, status rings, and tactile cards. |
| **Goals** | `GoalsScreen` (`lib/features/goals/goals_screen.dart`) | `GoalsStore` | Active/completed goals, milestones, deadline tracking. Needs spatial progress rings, milestone breadcrumbs, and restrained status plates. |
| **Notes / Items** | `ItemsScreen`, `ItemDetailScreen` (`lib/features/items/`) | `Store` | Editorial reading and note-taking environment. Needs quiet editorial serif headers, clean porcelain reading plates, and spatial tag pills. |
| **Insights & Progress** | `ProgressScreen`, `WeeklySummaryScreen` (`lib/features/progress/`) | `ProgressStore`, `ReviewStore` | Done score trends, self-reflection scores, streak journey. Needs premium Oura/Bevel inspired score geometry, restrained metric cards, and clean visual charts. |
| **Learn / Spaced Repetition** | `LearnScreen`, `SessionScreen` (`lib/features/learn/`) | `LearnStore`, `LearnEngineStore` | Card reviews, PDF mark-a-point reader, quiz flows. Needs refined spatial study cards, depth-elevated question plates, and fluid transitions. |
| **Quick Capture** | `QuickAddSheet` (`lib/features/quick_add/quick_add_sheet.dart`) | `QuickAddService` | Contextual creation modal. Needs spatial frosted modal lens ($Z = +44\text{dp}$), tactile item type selector, and haptic spring animations. |
| **Daily Routines** | `RoutineScreen` (`lib/features/today/routine_screen.dart`) | `TodayStore` | Template editor for recurring habits and tasks. Needs clean spatial group cards and schedule chips. |
| **Day Close** | `DayCloseScreen` (`lib/features/review/day_close_screen.dart`) | `ReviewStore` | Evening reflection, completion score review, journaling. Needs serene atmospheric twilight plates and tactile slider controls. |
| **Settings & Sync** | `SettingsScreen`, `SyncSection`, `BackupSection` (`lib/features/settings/`, `lib/features/sync/`) | `BackupStore`, `SyncStore` | Offline backup/restore, LAN sync. Needs clean architectural grouped cards and clear status indicators. |

---

## 3. Architecture & Technical Constraints

1. **State & Persistence**:
   - `sqflite` (Android) and `sqflite_common_ffi` (Desktop) storing workspaces, projects, items, plan items, goals, review entries, questions, and sync logs.
   - All stores (`TodayStore`, `Store`, `GoalsStore`, `ReviewStore`, `LearnStore`, `ProgressStore`) are instantiated once in `main.dart` and passed cleanly down the widget tree.
   - Pure offline-first architecture: No runtime network dependencies are required for core features.

2. **Typography & Assets**:
   - Bundled offline Google Fonts in `assets/fonts/`:
     - **Playfair Display** (Medium 500, SemiBold 600, MediumItalic 500)
     - **DM Sans** (Regular 400, Medium 500, Bold 700)
     - **DM Mono** (Regular 400, Medium 500)
   - Mascot Branding:
     - `NimoMark` in `lib/core/brand.dart` drawn via vector `CustomPainter` (sprout hood, peaceful eyes).

3. **Current UI Deficiencies Identified**:
   - Spacing inconsistency across feature tabs (varying margins from 12 to 24dp).
   - Abrupt elevation drops between dialogs and main cards.
   - Heavy borders in neo-brutalist remnants that conflict with the soft neutral spatial aesthetic.
   - Non-uniform tactile response when tapping tiles.

4. **Risk Assessment & Mitigation Strategy**:
   - **Risk**: Breaking any of the 647 automated regression tests.
   - **Mitigation**: Retain exact widget keys, semantics, store signatures, and callback interfaces while completely re-skinning and replacing visual presentations. Run `flutter test` after every major phase.
