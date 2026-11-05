# Nimo Product Experience, UI/UX, Usability & Architecture Audit
## Executive Summary & Strategic Assessment

### 1. Context & Purpose
Nimo is a mobile-first, offline-first personal operating system built with Flutter and SQLite. Its declared core loop is:
**Plan (Morning) → Track / Capture (Day) → Learn (Deliberate Practice) → Day Close (Evening) → Review Progress (Weekly/Longitudinal).**

This independent senior audit evaluated the application across its complete product lifecycle: product strategy, information architecture, navigation paths, user journeys, screen-by-screen usability, configuration, ergonomics, technical architecture, and data reliability.

---

### 2. Primary Diagnoses: Where Nimo Excels vs. Where It Fails

#### Where Nimo Excels (Core Foundations to Preserve)
1. **Rock-Solid Deterministic Engines:**
   - **Streak Shields Engine (`lib/features/review/streak.dart`):** The mathematical fold over daily signals (`corePlanComplete` or `reviewClosed`) is formally tested, clean, and prevents history corruption.
   - **Dual Scores Principle (`DoneScore` vs. `SelfScore`):** The separation of objective execution (auto-calculated 0–100) from subjective reflection (1–10) provides genuine psychological safety without gaming.
   - **Document-Oriented Note Editor (`lib/features/items/item_detail_screen.dart`):** Autosave with debouncing (900ms), dirty tracking, exit flush, and LWW concurrent-edit resolution is architecturally robust and feels like a calm digital paper surface.
   - **Safe Data Storage & Preservation (D-043 / D-016):** Android SAF external backups, SQLite pre-restore snapshots, and transactional imports prevent data loss.

#### Where Nimo Struggles (Critical Friction & Architectural Gaps)
1. **Severe Information Architecture Fragmentation ("The Split Personality Problem"):**
   - **Tasks vs. Notes vs. Topics vs. Goals:** A user wanting to learn "Flutter Performance" can create:
     - A Goal in Direction ("Master Flutter").
     - A Topic in Learn ("Flutter Rendering").
     - A Workspace / Project in Spaces ("Dev / Mobile / Note").
     - A Routine / One-off Task in Today ("Read Flutter Docs").
     *There is no unifying contextual fabric.* Content is siloed into four rigid destinations, requiring users to memorize where items live.
2. **The "Direction" Destination Confusion (Goals vs. Progress):**
   - Combining **Goals** (actionable outcome targets with numeric steppers) and **Progress** (reflective analytics, streak fold, journey map, calendar drill-down) under an ambiguous label "Direction" creates cognitive dissonance. Users do not think of checking their habit streak as "going to Direction".
3. **The Duplicated "Today Hub" Overload:**
   - Today (`TodayScreen`, 2,139 lines) attempts to be the entire app on one scrollable canvas:
     - Header, week strip, quick add row, daily plan, learning card, scores preview, day close prompt, pinned spaces, recent items, and goals section.
     - It duplicates Spaces, duplicates Goals, duplicates Learn, and duplicates Progress, turning what should be a focused daily execution cockpit into a bloated dashboard that requires continuous vertical scrolling.
4. **Routine Management Disconnect:**
   - Creating a routine template (`RoutineScreen`) creates items that only appear tomorrow by default (D-002), confusing users who expect to create a routine and immediately see it today. Although D-044 added an "Add to today's plan" button, the routine editor is disconnected from the daily plan view.
5. **Quick Add Friction & Redundancy:**
   - Quick Add appears in 3 conflicting places: the persistent bottom-right Floating Action Button, the horizontal 4-pill row on Today ("Task", "Goal", "Note", "Checklist"), and within Spaces/Topics. Yet, quick-adding a Note or Checklist prompts through a multi-step modal (`_pickFrom<Workspace>`, then `_pickFrom<Project>`) which breaks flow, rather than defaulting to an Inbox.
6. **Mobile Ergonomics & Vertical Density on Small Screens:**
   - On compact Android devices (320x640 / 360x780), oversized headings (`NeoPageTitle`, 28–32pt), large decorative quote panels, and stacked cards push actionable content below the fold. Users must scroll 2.5 full screens just to see their first task.

---

### 3. Top 10 High-Value Recommendations (Ranked by ROI)

| Rank | Area | Proposed Change | Usability Benefit | Implementation Cost |
|---|---|---|---|---|
| **1** | **IA / Shell** | **Disentangle Direction into Focused Navigation:** Elevate Goals into actionable Work (or merge into Today/Projects) and make Progress directly accessible from the streak pill. Rename/realign the 4 tabs to: **Today · Learn · Spaces · Progress** (or 3 core tabs + profile/progress). | Eliminates the ambiguous "Direction" container. Habit tracking and analytics become 1-tap obvious. | Low |
| **2** | **Today** | **Streamline Hub Home into a Pure Execution Cockpit:** Remove duplicated sections (Pinned Spaces, Recent Items, Goals list) from the Today scroll view. Today should strictly answer: *1. What must I do today? 2. What am I learning today? 3. Close the day.* | Eliminates 60% of vertical scroll clutter; loads instantaneously; stops duplicating Spaces. | Low |
| **3** | **Spaces** | **Inbox-First Fast Capture:** Note and checklist creation should immediately create an item in the built-in `Inbox` project without prompting for Workspace → Project selection. Triage happens later. | Cuts note creation from 4 taps + 2 pickers to 1 tap. | Low |
| **4** | **Learn** | **Unified Topic Learning Hub:** Seamlessly fuse topic sources (PDF, TXT, HTML, links) with generated practice questions. Eliminate the awkward mental gap between reading material and answering cloze cards. | Direct transition from reading/marking to active recall. | Medium |
| **5** | **Routines** | **Direct Routine-to-Day Scheduling:** When creating or editing a routine template, default to generating it for today's plan immediately if scheduled for today's weekday. | Fixes user confusion over "disappearing" routines. | Low |
| **6** | **Ergonomics** | **Compact Mobile Header Mode:** Introduce a compact editorial header that reduces `NeoPageTitle` height by 40% on standard mobile screens, ensuring Today's plan is visible above the fold on launch. | Plan is immediately interactive without scrolling. | Low |
| **7** | **Settings** | **Modular Categorized Settings Hierarchy:** Reorganize `SettingsScreen` from a single 337-line flat list into clean logical groups: Appearance, Daily & Planning, Learning & Memory, Backup & Storage, Sync, About. | Makes critical storage/sync options instantly discoverable. | Low |
| **8** | **HTML / Media** | **Dedicated Full-Screen Interactive Sandbox:** Formalize HTML documents as interactive study widgets with pinch-to-zoom, dark-theme injection, and full keyboard isolation. | Eliminates WebView quirks and sizing glitches. | Medium |
| **9** | **Review** | **Frictionless Day Close Integration:** Embed Day Close recap directly at the bottom of Today's completed list at night, rather than forcing a 4-step wizard modal route. | Night review completion jumps from 50% to 90%. | Medium |
| **10** | **Technical** | **Decompose Monolithic Screens (`today_screen.dart` 2,139 lines):** Extract plan sections, header widgets, and quick-add handlers into modular feature components. | Dramatically improves maintainability, testability, and rebuild performance. | Low |
