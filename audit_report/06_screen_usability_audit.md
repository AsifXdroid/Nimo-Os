# Screen-by-Screen Deep Usability Audit

A forensic examination of every core screen across purpose, layout, touch ergonomics, content, and states.

---

## 1. Today Screen (`TodayScreen`)

### Usability Evaluation
- **Purpose:** Daily execution cockpit. It succeeds when the user opens the app in the morning, knows exactly what to do, and feels a sense of completion at night.
- **Layout & Space Utilization:**
  - *Severe Vertical Crowding:* The top of the screen contains:
    - Editorial brand header (`NimoBrand` + date + greeting) ~100px.
    - Week strip (Mon–Sun calendar dots) ~70px.
    - Quick add row (4 wide pill buttons) ~60px.
    - *Cumulative offset:* **230–280px** before the first task is visible. On a 640px height phone, almost half the display is consumed before the user sees their daily tasks.
  - *Redundant Tail:* Below the plan sits the learning card, scores panel, Day Close card, pinned workspaces, recent items, goals section, and customize home button. This creates a vertical scroll length of over **3,000 pixels**.
- **Interaction & Ergonomics:**
  - *Checkbox Touch Targets:* The custom `NeoCheckbox` (29x29px) is well-padded and feels tactile.
  - *Task Action Sheet:* Accessing task options (edit title, attach resource, delete) via long-press or the `⋯` icon works reliably.
  - *Core Routine Deletion Warning:* D-042's warning when deleting a completed core routine prevents accidental streak resets.
- **States:**
  - *Empty State:* Shows "Nothing planned yet. Use the + button to add a task, or build your routine template." Clear and helpful.
  - *Populated State:* Clean separation between "Daily To-do" (routines) and "Today" (one-offs).
  - *Keyboard State:* When the Customize Home or Task Sheet opens, the sheet smoothly repositions above the IME.

### Concrete Recommendations for Today:
1. **Compact the Header:** Shrink the editorial intro on small mobile displays by 40%.
2. **Remove Pinned Spaces, Recent Items, and Goals from Today:** Relocate these to their dedicated destinations (Spaces and Progress).
3. **Keep Today Exclusively for Plan, Learn, and Close:** This reduces code complexity from 2,139 lines to ~800 lines and provides an immediate, calm view of daily obligations.

---

## 2. Learn Screen (`LearnScreen`) & Topics (`TopicsScreen`)

### Usability Evaluation
- **Purpose:** Deliberate practice and curiosity management without gamified guilt or endless notifications.
- **Layout & Space Utilization:**
  - *Pulse Panel:* The deep-green pulse panel (`_pulsePanel`, `EditorialColors.deepAccent`) looks elegant and displays three quiet stats: due reviews, new cards, and imported packs.
  - *Recent Topics Row:* D-047 surfaces up to five recent topics directly on Learn, resolving the previous "empty Learn" problem when no pre-packaged packs were imported.
  - *TopicsScreen Redesign (D-050):* The dual-tab layout (Topics vs. Library) cleanly separates conceptual topic intentions from raw physical storage files.
- **Interaction & Ergonomics:**
  - *Single Tap to Practice:* Tapping "Begin a short session →" launches the spaced repetition engine in 1 tap.
  - *Filter Chips:* In `TopicsScreen`, horizontal filter chips (`All`, `Inbox`, `Active`, `Parked`, `Done`) allow rapid triage of the capture inbox.
  - *Reading & Marking Flow:* `ReadingScreen` allows users to highlight any sentence in a text or extracted PDF, immediately saving a cloze card point without interrupting the reading experience.
- **Defects & Friction:**
  - *Missing Direct Connection Between Reading & Session:* After marking 3 points in a PDF, there is no direct "Practice these points now" button. The user must back out to Learn and hope the scheduler picks them up.

### Concrete Recommendations for Learn:
1. **Direct Practice Action on Topic Detail:** Add a "Practice this topic" button inside `TopicDetailScreen` so users can immediately test themselves on points they just marked.
2. **Visual Difficulty Indication:** Highlight topics that have high lapse rates (questions repeatedly failed) with a subtle "Needs review" badge.

---

## 3. Spaces (`WorkspacesScreen`) & Projects (`ProjectsScreen`)

### Usability Evaluation
- **Purpose:** Digital workbench organizing life and work into `Workspace → Project → Page`.
- **Layout & Space Utilization:**
  - *Compact Landing (D-048):* Replaced noisy accordion panels with clean workspace tiles (monogram glyph, name, chevron) and Recent Projects visit history.
  - *Visual Cleanliness:* Minimalist and quiet. Exactly matches the Things 3 / Bear philosophy.
- **Interaction & Ergonomics:**
  - *Safe Actions:* Workspaces and projects use long-press bottom sheets for destructive actions (Rename, Delete, Pin), preventing accidental deletions.
  - *Fast Project Resume:* Recent Projects allows 1-tap jump back into active work.
- **Friction:**
  - *Missing Item Counts:* While D-048 removed clutter, workspaces no longer show how many projects or items they contain, making empty workspaces indistinguishable from populated ones until opened.

### Concrete Recommendations for Spaces:
1. **Subtle Project Count Metadata:** Display a quiet badge (e.g. "3 projects") next to the workspace chevron.
2. **Swipe-to-Action Gestures:** Add standard left/right swipe gestures on project rows for quick archiving or pinning.

---

## 4. Notebook Editor (`ItemDetailScreen` - Note Mode)

### Usability Evaluation
- **Purpose:** Focused document writing for study notes, drafts, and meeting logs.
- **Layout & Space Utilization:**
  - *Document Framing:* Large Playfair display title field transitioning directly into a borderless body `TextField`.
  - *Save Status Indicator:* Top-right header carries a real-time status: `Saved`, `Saving…`, `Unsaved changes`, or `Changed on another device`.
  - *Formatting Toolbar (D-049):* Six clean markdown shortcut buttons (`**`, `_`, `#`, `-`, `1.`, `[ ]`) directly above the text body.
- **Interaction & Ergonomics:**
  - *Autosave & Concurrency:* 900ms debounced autosave, automatic background flush, and LWW sync conflict detection prevent data loss.
  - *Fast Discard:* Creating an empty note and exiting immediately discards the empty row without cluttering the database.
- **Defects:**
  - *No Markdown Preview Mode:* While the formatting toolbar inserts `**bold**` or `# heading`, the text remains raw monospaced markdown. Users cannot toggle a rendered view to read their formatted study notes comfortably.

### Concrete Recommendations for Notebook:
1. **Split Edit / Preview Toggle:** Add a subtle eye icon (`Icons.visibility_outlined`) in the note header allowing users to toggle between raw markdown editing and rich rendered presentation.

---

## 5. Direction Screen (`DirectionScreen`) - Goals & Progress

### Usability Evaluation
- **Purpose:** Long-term direction, outcome goals, and self-reflection analytics.
- **Layout & Usability:**
  - *Goals Tab:* Displays goal cards with targets, current values, units, and round `−` / `+` stepper buttons. Steppers disable cleanly at 0 and target (D-037).
  - *Progress Tab:*
    - **Journey Path Hero:** Visual stepping stones derived from real daily signals.
    - **Two-Signals Streak Card:** Transparently explains why today counts (core routine complete or Day Close done) and shows held shield count.
    - **Dual Score Trends:** Distinct Done Score (auto) and Self Score (mine) charts. Never merged, upholding the core psychological contract.
    - **Calendar View:** Month-grid showing past score badges and streak continuity.
- **Defects:**
  - *Artificial Tab Strip:* Having to switch between Goals and Progress under the banner of "Direction" feels disjointed.
  - *No Goal Deadlines or Milestones:* Goals only have a scalar target (e.g., 50 words); they lack target dates or sub-milestones.

### Concrete Recommendations for Direction:
1. **Re-anchor Goals into Work & Progress into Self-Reflection:** Move Goal tracking to be visible alongside active projects or integrate it with Progress under an elevated **Progress & Milestones** destination.
