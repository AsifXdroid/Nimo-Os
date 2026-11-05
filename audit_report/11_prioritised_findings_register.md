# Prioritised Findings & Defect Register

Every identified issue has been cataloged with verified evidence from the codebase, severity rating, and concrete remediation steps.

---

## Severity Scale:
- **P0 — Critical:** Data loss risk, broken core workflow, serious reliability bug.
- **P1 — High:** Major usability problem, significant navigation friction, or inaccessible feature.
- **P2 — Medium:** Workflow inefficiency, layout crowding, or cognitive confusion.
- **P3 — Low:** Visual polish, minor inconsistency, or typography alignment.

---

## Complete Findings Register

### Finding 1: The "Direction" Navigation Disconnect
- **ID:** `AUDIT-IA-01`
- **Component:** `lib/features/direction/direction_screen.dart`
- **Severity:** **P1 (High)**
- **Observed Problem:** Combines Goals and Progress into an artificial tab container labeled "Direction" (`Icons.explore_outlined`). Streak chip on Today has to bypass normal navigation using a temporary token `_directionRequest`.
- **Evidence:** [`direction_screen.dart:60-80`](file:///home/Asif/Downloads/Nomi%202/nimo-os-test/lib/features/direction/direction_screen.dart#L60-L80) and [`main.dart:470-476`](file:///home/Asif/Downloads/Nomi%202/nimo-os-test/lib/main.dart#L470-L476).
- **Why It Matters:** Users do not associate checking their habit streak or viewing weekly progress with "Direction".
- **Recommended Solution:** Dissolve the Direction container. Elevate Progress to a direct top-level destination (`Today · Knowledge · Progress`) or anchor it to the streak pill.

---

### Finding 2: Monolithic Today Screen Overload (2,139 Lines)
- **ID:** `AUDIT-PERF-02`
- **Component:** `lib/features/today/today_screen.dart`
- **Severity:** **P1 (High)**
- **Observed Problem:** Single file is 2,139 lines long and stacks 10 distinct sections, causing over 3,000 pixels of vertical scroll and duplicating content from Spaces, Goals, and Learn.
- **Evidence:** [`today_screen.dart:531-578`](file:///home/Asif/Downloads/Nomi%202/nimo-os-test/lib/features/today/today_screen.dart#L531-L578).
- **Why It Matters:** Destroys the focused, calm nature of the morning planning loop. Causes viewport lag and unnecessary widget rebuilds.
- **Recommended Solution:** Remove duplicated sections (Pinned Spaces, Recent Items, Goals list). Refactor `today_screen.dart` into modular sub-widgets (`TodayPlanCard`, `TodayLearnCard`, `TodayHeader`).

---

### Finding 3: Multi-Step Modal Friction on Quick Note Capture
- **ID:** `AUDIT-UX-03`
- **Component:** `lib/features/today/today_screen.dart:328-366`
- **Severity:** **P1 (High)**
- **Observed Problem:** Quick-adding a Note or Checklist prompts through `_pickFrom<Workspace>` ("Choose workspace") then `_pickFrom<Project>` ("Choose project") before allowing the user to type.
- **Evidence:** [`today_screen.dart:337-357`](file:///home/Asif/Downloads/Nomi%202/nimo-os-test/lib/features/today/today_screen.dart#L337-L357).
- **Why It Matters:** Destroys spontaneous capture flow. Users want to write immediately and organize later.
- **Recommended Solution:** Default quick note capture immediately into the built-in `Inbox` project. Allow triage into specific projects later.

---

### Finding 4: Routine Template Temporal Disconnect
- **ID:** `AUDIT-UX-04`
- **Component:** `lib/features/today/routine_screen.dart`
- **Severity:** **P2 (Medium)**
- **Observed Problem:** Creating or editing a routine template applies "from tomorrow" by default, causing users to believe their created habit did not save.
- **Evidence:** [`routine_screen.dart:198-220`](file:///home/Asif/Downloads/Nomi%202/nimo-os-test/lib/features/today/routine_screen.dart#L198-L220).
- **Why It Matters:** Violates user expectation of immediate feedback upon creating a daily habit.
- **Recommended Solution:** When creating a routine template, check if today's weekday matches the recurrence rule; if so, prompt or default to automatically generating it for today's plan.

---

### Finding 5: Disconnected Study Notes vs. Topic Reading
- **ID:** `AUDIT-IA-05`
- **Component:** `lib/features/learn/topic_detail_screen.dart` & `lib/features/items/items_screen.dart`
- **Severity:** **P2 (Medium)**
- **Observed Problem:** Study notes live inside Projects (`items_screen.dart`), while study sources live inside Topics (`topic_detail_screen.dart`), even though Topics and Projects are linked via `projectId`.
- **Evidence:** [`topic_detail_screen.dart:42-60`](file:///home/Asif/Downloads/Nomi%202/nimo-os-test/lib/features/learn/topic_detail_screen.dart#L42-L60).
- **Why It Matters:** Users have to switch between two different screens to read a source and view their long-form notes on that subject.
- **Recommended Solution:** Display associated project study notes directly as a sub-section inside `TopicDetailScreen`.

---

### Finding 6: Lack of Markdown Rendered Preview in Note Editor
- **ID:** `AUDIT-UX-06`
- **Component:** `lib/features/items/item_detail_screen.dart`
- **Severity:** **P2 (Medium)**
- **Observed Problem:** The note editor features formatting buttons (`**`, `#`, `- [ ]`), but body text remains raw monospaced markdown without a rendered preview mode.
- **Evidence:** [`item_detail_screen.dart:470-514`](file:///home/Asif/Downloads/Nomi%202/nimo-os-test/lib/features/items/item_detail_screen.dart#L470-L514).
- **Why It Matters:** Users who format study notes cannot read them cleanly with formatted headings, checkboxes, or bold emphasis.
- **Recommended Solution:** Add a toggle icon in the editor AppBar to switch between raw markdown editing and a clean rendered markdown view.

---

### Finding 7: Asynchronous Autosave Race Condition on Note Exit
- **ID:** `AUDIT-TECH-07`
- **Component:** `lib/features/items/item_detail_screen.dart:106-122`
- **Severity:** **P2 (Medium)**
- **Observed Problem:** `dispose()` fires `unawaited(_flushPending())`. If a user types and taps Back immediately, the popping route reloads before the SQLite write completes, causing visible title flicker or stale text.
- **Evidence:** [`item_detail_screen.dart:114`](file:///home/Asif/Downloads/Nomi%202/nimo-os-test/lib/features/items/item_detail_screen.dart#L114).
- **Why It Matters:** Can cause user anxiety over whether their note actually saved.
- **Recommended Solution:** Intercept the route pop with a `PopScope` or custom Back button handler to await `_flushPending()` before popping.

---

### Finding 8: Monolithic Settings Screen
- **ID:** `AUDIT-UX-08`
- **Component:** `lib/features/settings/settings_screen.dart`
- **Severity:** **P2 (Medium)**
- **Observed Problem:** All settings, reminders, backups, and sync controls sit in a single 337-line scrolling list, burying backup and sync options.
- **Evidence:** [`settings_screen.dart:131-280`](file:///home/Asif/Downloads/Nomi%202/nimo-os-test/lib/features/settings/settings_screen.dart#L131-L280).
- **Why It Matters:** Decreased discoverability for critical data safety settings.
- **Recommended Solution:** Categorize settings into card-based sub-sections: Appearance, Habits & Reminders, Data & Storage, Sync, About.

---

### Finding 9: Vertical Viewport Crowding on Compact Displays
- **ID:** `AUDIT-VISUAL-09`
- **Component:** `lib/core/neo_ui.dart` (`NeoPageTitle`)
- **Severity:** **P3 (Low)**
- **Observed Problem:** `NeoPageTitle` renders an eyebrow, 32pt headline, and 2-line subtitle on every screen, consuming ~140px before screen content begins.
- **Evidence:** Observed live on 320x640 emulator.
- **Why It Matters:** Forces primary content below the fold on standard phone screens.
- **Recommended Solution:** Provide a compact header variant (`NeoPageTitle.compact`) that reduces vertical padding by 40% on mobile devices.

---

### Finding 10: Goals Have No Association with Daily Tasks
- **ID:** `AUDIT-IA-10`
- **Component:** `lib/features/goals/goals_store.dart` & `lib/features/today/today_store.dart`
- **Severity:** **P3 (Low)**
- **Observed Problem:** Daily tasks can link to Notes, Checklists, Links, or Quizzes via `item_id` (D-042), but cannot link to a Goal.
- **Evidence:** [`DATA_MODEL.md:85-86`](file:///home/Asif/Downloads/Nomi%202/nimo-os-test/docs/DATA_MODEL.md#L85-L86) (`day_plan_items.item_id → items(id)`).
- **Why It Matters:** Daily execution is disconnected from high-level goal progress.
- **Recommended Solution:** Allow `day_plan_items` to optionally reference a `goal_id`, so completing the task increments the goal's stepper.
