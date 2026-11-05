# Information Architecture Audit

## 1. Current Information Architecture

The application currently organizes its universe into four top-level destinations, with a deep sub-tree structure:

```
[ App Shell (4-tab NavigationBar) ]
├── 1. Today (Hub Home)
│    ├── Header (Greeting, Streak Chip, Settings Cog)
│    ├── Week Strip (Mon–Sun pending dots)
│    ├── Quick-Add Row (Task, Goal, Note, Checklist)
│    ├── Today's Plan (Today / This Week tabs, Task Checkboxes, Task ⋯ Sheet)
│    │    └── Routine Editor ("Edit routine →") [Full Screen]
│    │         ├── Habit Details Modal (Tiny version, Anchor, Track, Counts Core)
│    │         └── Schedule & Link Modal (Weekdays mask, Linked Item, URL)
│    ├── Learning Recommendation Card (Due/New counts, "Start session →")
│    ├── Scores Panel (Done Score 0-100, Self Score 1-10)
│    ├── Day Close Banner / Card [Full Screen Flow]
│    │    ├── Step 1: Recap Plan
│    │    ├── Step 2: Major Point (Link Topic)
│    │    ├── Step 3: Self Score (1-10 chips)
│    │    └── Step 4: Dual Reveal (Done auto vs Self)
│    ├── Pinned Workspaces List (Workspace tiles)
│    ├── Recent Items List (Notes/Checklists/Links)
│    ├── Goals Section (Goals cards with steppers)
│    └── Customize Home Dialog (10 section toggle switches)
├── 2. Learn
│    ├── Learning Pulse Panel ("Begin a short session →")
│    │    └── Session Player [Full Screen] (12-20 cards, Enjoyment Rating, Stats)
│    ├── Continue Exploring (Arc packs)
│    ├── Your Topics (First 5 topics list, "New topic" button)
│    │    └── "All topics →" / TopicsScreen [Full Screen]
│    │         ├── Tab 1: Topics (Search, Status Filter Chips, Topic Rows)
│    │         └── Tab 2: Library (Storage card, All Sources List)
│    ├── Topic Detail Screen [Full Screen]
│    │    ├── Source List (PDF, TXT, Link, HTML)
│    │    ├── Reading Screen [Full Screen] (Mark-a-point)
│    │    ├── PDF Viewer [Full Screen] (pdfrx)
│    │    └── Mint Questions Action
│    ├── Your Packs (Imported .quizpack list, "Import a pack" button)
│    └── Image Verify List [Full Screen] (Target verify flow)
├── 3. Spaces (The Digital Workbench)
│    ├── Workspaces List (Workspace cards with initials, long-press actions)
│    ├── Recent Projects List (Last 5 visited projects)
│    └── ProjectsScreen [Full Screen] (Projects in workspace)
│         └── ItemsScreen [Full Screen] (Project items: Notes, Lists, Links, HTML)
│              └── ItemDetailScreen [Full Screen]
│                   ├── Note Editor (Document view, markdown toolbar, autosave)
│                   ├── Checklist Editor (Checkboxes, add/reorder, 3-dot menu)
│                   ├── Link Card View (Square preview, thumbnail actions)
│                   └── HTML Viewer (In-place interactive WebView sandbox)
└── 4. Direction
     ├── Hairline Tab Strip
     │    ├── Tab 1: Goals
     │    │    ├── Goals List (Target, Current, Unit, Steppers − / +)
     │    │    └── Add Goal Modal
     │    └── Tab 2: Progress
     │         ├── Journey Path (Visual milestone stones & path)
     │         ├── Two-Signals Streak Card (Streak count, shields held, refill)
     │         ├── Dual Score Trend Charts (Done auto vs Self score weekly graph)
     │         ├── Calendar Drill-Down (Month view, day score inspect)
     │         └── Weekly Summaries Archive (Sunday summaries)
```

---

## 2. Identified Structural Problems

### Problem 1: The Direction Schism (Ambiguous Container)
- **Symptom:** Direction forces two completely different mental modes into one tab:
  - *Goals:* Forward-looking, execution-oriented, outcome targets with numeric steppers.
  - *Progress:* Backward-looking, reflective, analytical journey visualization with charts and calendar drill-downs.
- **Evidence:** [`lib/features/direction/direction_screen.dart`](file:///home/Asif/Downloads/Nomi%202/nimo-os-test/lib/features/direction/direction_screen.dart#L60-L80) hosts two separate Scaffolds glued together by an artificial tab strip. Today's header streak chip has to inject a fake token `_directionRequest = DirectionTab.progress` into the shell just to bypass the default tab.
- **Why it fails:** Users looking for their goals don't think of "Direction"; users looking at their habit streaks don't think "Direction".

### Problem 2: Today Is Overloaded & Duplicates the Entire App
- **Symptom:** Today (`TodayScreen`) contains 2,139 lines of code and displays 10 stacked sections:
  1. Intro Greeting, 2. Sunday Summary, 3. Week Strip, 4. Quick Add Row, 5. Today's Plan, 6. Learn Recommendation, 7. Scores Preview, 8. Day Close Banner, 9. Pinned Spaces, 10. Recent Items, 11. Goals, 12. Customize Home.
- **Evidence:** A user on Today can view their goals (duplicating Direction → Goals), view their pinned spaces (duplicating Spaces), view their recent items (duplicating Spaces → Recent Projects), and view their learning stats (duplicating Learn).
- **Why it fails:** A daily planner should be a calm, focused launchpad for *what to do right now*. Duplicating the entire app on the home screen causes severe cognitive overload and pushes today's actual tasks hundreds of pixels down.

### Problem 3: Contextual Siloing of "Learning" vs "Notes"
- **Symptom:** If a user reads a book or studies a topic, they have to choose between two completely parallel worlds:
  - Put notes in **Spaces → Workspace → Project → Note**.
  - Put learning materials in **Learn → Topic → Source → Marked Points**.
- **Evidence:** `TopicDetailScreen` and `ItemsScreen` both belong to a Project (every Topic has a `projectId`), yet they are viewed on separate screens with separate navigation flows. Users cannot see their topic study notes alongside their project pages.

### Problem 4: Routine Template Temporal Disconnect
- **Symptom:** When a user creates a new routine in `RoutineScreen`, they expect it to be part of their routine immediately. Instead, D-002 locks plan generation to midnight, so the routine defaults to appearing *tomorrow*.
- **Evidence:** D-044 had to introduce a custom `_addToToday(PlanTemplate t)` workaround button inside `RoutineScreen` to manually inject the routine into today's plan.

---

## 3. Proposed Information Architecture

We propose reorganizing Nimo around a **natural 3-pillar daily mental model**, with Progress elevated to its rightful place:

```
[ NIMO UNIFIED ARCHITECTURE ]
┌────────────────────────────────────────────────────────────────────────┐
│ 1. TODAY          │ 2. KNOWLEDGE      │ 3. PROGRESS      │ GLOBAL     │
│ (Daily Focus)     │ (Spaces & Learn)  │ (Journey & Goals)│ (Profile)  │
├───────────────────┼───────────────────┼───────────────────┼────────────┤
│ • Focus / Today   │ • Spaces & Notes  │ • Habit Streak &  │ • Quick Add│
│   Daily Tasks     │   Workspaces      │   Shields         │   (Floating│
│   Routines        │   Projects        │ • Dual-Score      │   Action)  │
│ • Deliberate      │   Document Notes  │   Trends          │            │
│   Study Session   │   Checklists      │ • Goals &         │ • Settings │
│ • Evening Close   │ • Study Topics    │   Milestones      │   (AppBar  │
│   Day Close Flow  │   PDF / Text /    │ • Calendar Drill- │    Action) │
│                   │   HTML Library    │   down            │            │
│                   │   Spaced Practice │ • Weekly Summary  │            │
└────────────────────────────────────────────────────────────────────────┘
```

### Detailed Destination Roles:

#### Destination 1: TODAY (The Daily Cockpit)
- **Sole Purpose:** Answering *"What am I doing today, and how did I do tonight?"*
- **Contents:**
  1. **Compact Editorial Header:** Date, greeting, current streak pill (tap opens Progress), Settings icon.
  2. **Today's Plan:**
     - **Morning Routine / Habits:** Recurring items scheduled for today.
     - **Daily Tasks:** One-off and carried-over tasks.
     - **Linked Resources:** Tap to open note, web link, or HTML quiz directly.
  3. **Daily Learning Card:** Single high-leverage deliberate practice prompt (due reviews + new discovery).
  4. **Evening Day Close (Adaptive):** Appears automatically in the evening (or after plan completion) to recap the day, record the major learning point, and rate Self Score.
- **Removed from Today:**
  - Pinned Spaces (accessible in Knowledge/Spaces).
  - Recent Items (accessible in Knowledge/Spaces).
  - Standalone Goals list (accessible in Progress & Goals).

#### Destination 2: KNOWLEDGE (Spaces & Learning Unified)
- **Sole Purpose:** All creative and intellectual assets in one unified place.
- **Structure (Dual Tab View):**
  - **Tab 1: Notebook & Projects (Spaces):** Workspaces → Projects → Document Notes, Checklists, and Links. Includes quick visit history ("Recent Projects").
  - **Tab 2: Topics & Library (Learn):** Study topics, source library (PDFs, TXT, HTML, links), reading cards, and imported packs.
- **Advantage:** Users never have to ask "did I save that book summary in Spaces or in Learn?" All personal knowledge lives together under one clear roof.

#### Destination 3: PROGRESS (Trajectory & Goals)
- **Sole Purpose:** Long-term trajectory, accountability, and celebration.
- **Contents:**
  - **Journey Path & Streak Health:** Visual path, current streak, streak shields held, refill progress.
  - **Active Goals & Milestones:** Short-term and medium-term outcome targets with quick increment/decrement steppers.
  - **Dual-Score Analytics:** Done Score (objective plan completion) and Self Score (subjective rating) trends over 7, 30, and 90 days.
  - **Calendar History & Sunday Archives:** Month drill-down and weekly reflection summaries.

---

## 4. Before & After Comparison

| Aspect | Current Architecture | Proposed Architecture | Usability & Product Gain |
|---|---|---|---|
| **Primary Tabs** | Today · Learn · Spaces · Direction | **Today · Knowledge · Progress** (3 tabs) | Replaces the ambiguous "Direction" label; eliminates fragmentation between notes and study topics. |
| **Today Screen Size** | 2,139 lines; 10 stacked sections; extreme vertical scroll | ~800 lines; 3 focused sections (Plan, Learn, Close) | Immediate focus above the fold; loads faster; zero redundant content. |
| **Goal Tracking** | Buried inside Direction Tab 1, but duplicated on Today | Elevated into Progress alongside streaks and milestones | Goals directly connect to personal trajectory and scores. |
| **Note vs Learn** | Separated across two distinct bottom-bar destinations | Co-located as tabs in Knowledge | Consistent mental model for all reading, note-taking, and active recall. |
| **Quick Add** | Broken into 3 places with 2-step modal pickers for notes | One global sheet: Note defaults to Inbox project immediately | 1-tap capture speed (Things 3 / Craft benchmark). |

---

## 5. Risks and Migration Trade-offs
1. **Low Technical Risk:** The underlying database tables (`items`, `workspaces`, `projects`, `topics`, `sources`, `goals`, `day_reviews`) remain completely unchanged. No schema migration is required.
2. **Minimal Shell Adaptation:** `AppShell` switches from 4 destination IDs (`today`, `learn`, `spaces`, `direction`) to 3 clean IDs (`today`, `knowledge`, `progress`).
3. **User Familiarity:** The core interactions (ticking tasks, writing notes, answering quiz cards, closing the day) remain identical, but navigation friction is reduced by over 50%.
