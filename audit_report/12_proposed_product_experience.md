# Proposed Product Experience & Implementation Roadmap

## 1. The Unified Nimo Vision

Nimo should feel like a **calm, intelligent personal compass** — an app you open in the morning to find clarity, check during the day without friction, and close in under two minutes at night with genuine satisfaction.

### Architectural Transformation Overview:

```
[ Current (4 Fragmented Tabs) ]           [ Proposed (3 Cohesive Pillars) ]
  • Today (2,139 lines, 10 sections)        • Today (Focused Daily Cockpit)
  • Learn (Spaced practice + library)  ──►   • Knowledge (Spaces & Learn Unified)
  • Spaces (Workspaces & recent)             • Progress (Trajectory, Streak & Goals)
  • Direction (Goals + Progress tabs)        • Global Quick Add (Instant Inbox Note)
```

---

## 2. Screen-by-Screen Transformation Specifications

### A. TODAY — The Focused Daily Cockpit
- **Header:** Date, greeting, streak pill (`🔥 7 · 🛡️ 1`), and Settings gear.
- **Top Plan View:**
  - Daily To-do (habits scheduled for today).
  - Tasks (one-offs and carried-over items).
  - Tapping a task toggles completion with immediate Done Score animation.
  - Tapping a task's resource icon directly opens the note, video, or HTML study widget.
- **Mid-Screen Deliberate Practice Card:**
  - Shows cards due for review (`12 due to revisit`).
  - Single tap begins the daily study session.
- **Evening Reflection (Adaptive):**
  - In the evening (≥ 19:00) or after completing the plan, a calm banner invites the user to close the day.
  - Recap, Major Point, Self Score (1–10), and the dual score reveal (Done auto vs Self mine).
- **Eliminated from Today:**
  - Pinned spaces, recent items, and goals are removed, freeing up over 2,000 pixels of unnecessary vertical scrolling.

### B. KNOWLEDGE — Spaces & Learn Unified
- **Tab 1: Notebook & Projects (Spaces):**
  - Workspaces list with project counts.
  - Recent Projects carousel for instant resumption of work.
  - Projects view (`ItemsScreen`) listing Notes, Checklists, Links, and Quizzes.
  - Fast note creation immediately defaults to the `Inbox` project.
- **Tab 2: Topics & Study Library (Learn):**
  - Searchable topics with status filter chips (`All`, `Inbox`, `Active`, `Parked`, `Done`).
  - Dedicated storage card summarizing local files (PDFs, TXT notes, HTML files, links).
  - One-tap access to reading cards, PDF viewer (`pdfrx`), and active cloze card minting.

### C. PROGRESS — Trajectory, Streak & Goals
- **Habit Streak & Shield Defense:**
  - Current streak, best streak, total days active.
  - Shields held (up to 2) and transparent refill meter.
- **Active Outcome Goals:**
  - Target vs. Current with tactile `−` / `+` steppers.
  - Optional link to daily plan tasks.
- **Dual-Score Analytics:**
  - Separate trend lines for objective Done Score (0–100) and subjective Self Score (1–10). Never merged.
- **Calendar & History:**
  - Interactive month grid and Sunday weekly reflection archive.

### D. SETTINGS — Modular & Discoverable
- Organized into clean, discoverable cards:
  1. **Appearance:** Dark / Light theme switch, font scaling, Home section customization.
  2. **Habits & Reminders:** Morning plan time, Evening close time, inactivity self-watch.
  3. **Data & Storage:** Storage footprint inspection, cache cleaner, External SAF backup, snapshot backup & restore (guarded).
  4. **Device Sync:** LAN Stage A package export/import, sync conflict inspector.
  5. **About & Health:** Version, SQLite schema version, database integrity check.

---

## 3. Four-Phase Implementation Roadmap

```
┌────────────────────────────────────────────────────────────────────────┐
│ PHASE 1: IMMEDIATE HIGH-VALUE FIXES (Days 1–3)                        │
├────────────────────────────────────────────────────────────────────────┤
│ • Fast Note Capture: Quick Add Note directly creates row in Inbox      │
│ • Note Autosave Flush Fix: Await _flushPending on route pop             │
│ • Routine Today-Generation: Offer immediate today-add on routine create │
│ • Header Viewport Optimization: Implement compact NeoPageTitle on mobile│
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ PHASE 2: TODAY STREAMLINING & CODE DECOMPOSITION (Days 4–7)           │
├────────────────────────────────────────────────────────────────────────┤
│ • Decompose TodayScreen (2,139 lines) into modular sub-widgets         │
│ • Remove duplicate Pinned Spaces, Recent Items, and Goals from Today   │
│ • Elevate streak chip interaction to open Progress cleanly             │
│ • Verify Done Score animation and streak fold reactivity               │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ PHASE 3: IA REALIGNMENT & DESTINATION UNIFICATION (Days 8–14)          │
├────────────────────────────────────────────────────────────────────────┤
│ • Unify Spaces and Learn into Knowledge Hub (2 clean tabs)             │
│ • Elevate Direction into dedicated Progress & Goals destination        │
│ • Update AppShell bottom navigation to 3 core pillars                  │
│ • Link Project Notes into Topic Detail screens                         │
└────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ PHASE 4: POLISH & ADVANCED WORKFLOWS (Days 15–21)                      │
├────────────────────────────────────────────────────────────────────────┤
│ • Note Editor Markdown Preview Mode: Toggle raw edit vs formatted read│
│ • Settings Modular Redesign: Card-based categories with diagnostics    │
│ • Goal-to-Task linkage in daily plan items                             │
│ • Stage B LAN synchronization discovery preparation                    │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Architectural Safeguards & Risk Controls

1. **Zero Database Breakage:** All proposed improvements preserve existing SQLite schemas (v1–v8) without requiring destructive table migrations.
2. **Backward Compatibility:** All existing notes, routines, day plans, streak records, and quiz packs remain 100% compatible.
3. **Safety Rails Preserved:** D-011 / D-016 backup guards, D-013 routine snapshot integrity, and the two-signals streak fold remain untouchable.
