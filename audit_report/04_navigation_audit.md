# Complete Navigation Audit & User Journey Analysis

## 1. Evaluation of Core Navigation Mechanisms

### A. Bottom Navigation Bar vs. NavigationRail
- **Current Mobile State:** 4 destinations (`Today`, `Learn`, `Spaces`, `Direction`) via Material 3 `NavigationBar`.
- **Large Screen State:** `NavigationRail` is supported in `lib/main.dart` with a leading `+` action button.
- **Identified Issues:**
  1. The label "Direction" is vague and unfamiliar.
  2. The icon for Direction (`Icons.explore_outlined`) conveys map exploration or web browsing rather than self-development and goal tracking.
  3. Four destinations create dense bottom bar targets on small phone screens (320px width), with label text truncating or wrapping awkwardly.

### B. Back Button Behavior & Stack Integrity
- **Current State:** Most nested screens push standard `MaterialPageRoute`. Back arrow in AppBar and Android system back gesture (`KEYCODE_BACK`) pop the stack.
- **Identified Failure Points:**
  1. **Autosave Flush Interception in Note Editor:** In [`lib/features/items/item_detail_screen.dart`](file:///home/Asif/Downloads/Nomi%202/nimo-os-test/lib/features/items/item_detail_screen.dart#L106-L122), `dispose()` flushes pending edits asynchronously via `unawaited(_flushPending())`. If a user types and immediately presses Back, the popped screen (`ItemsScreen`) triggers `_reload()` *before* the asynchronous write finishes on SQLite, leading to a visible flicker or stale note title.
  2. **Direction Tab Memory:** When navigating from Today's streak chip to Direction (Progress tab), switching to another tab and returning to Direction unexpectedly resets to Goals because `DirectionScreen` disposes its internal state.

### C. The Floating Action Button & Quick Add
- **Redundancy Analysis:**
  - `AppShell` renders a floating action button `+` in the bottom right.
  - `TodayScreen` simultaneously renders a 4-pill horizontal row ("Task", "Goal", "Note", "Checklist") directly above the plan.
  - Tapping `+` on Today opens `QuickAddSheet`, which duplicates the exact same options as the quick-add row.
- **Friction in Note Capture:**
  - Using the Quick Add row for "Note" runs `_quickAddItem('note')` in `TodayScreen`.
  - This prompts the user with `_pickFrom<Workspace>` ("Choose workspace").
  - Then prompts with `_pickFrom<Project>` ("Choose project").
  - Then prompts with a title dialog.
  - *Result:* Quick note capture requires **4 separate modal steps and 5 taps** before the keyboard opens. This violates the core promise of quick capture.

---

## 2. Realistic User Journey Tests (Code-Verified)

### Journey 1: Open Nimo and Create a Daily Task
- **Starting Point:** App launch on `TodayScreen`.
- **Interaction Sequence:**
  1. Tap `+` FAB or tap "Task" pill in Quick Add row (1 tap).
  2. `QuickAddSheet` opens with "Task" tab selected.
  3. Type task title (e.g., "Review Q3 financials").
  4. Tap "Add task" button (1 tap).
- **Result:** Task appears at the bottom of Today's plan.
- **Metrics:** **2 taps** + typing.
- **Verdict:** **Smooth & Effective.**

---

### Journey 2: Complete a Routine Habit
- **Starting Point:** `TodayScreen`.
- **Interaction Sequence:**
  1. Locate routine item under "Daily To-do" section.
  2. Tap checkbox square (1 tap).
- **Result:**
  - Checkbox toggles to checked with immediate visual feedback.
  - Done Score updates dynamically.
  - Core habit signal triggers recalculation of streak eligibility.
- **Metrics:** **1 tap.**
- **Verdict:** **Excellent.** Immediate tactile feedback.

---

### Journey 3: Create a Goal and Connect It to Actionable Work
- **Starting Point:** `TodayScreen`.
- **Interaction Sequence:**
  1. Tap Direction tab in bottom navigation (1 tap).
  2. `DirectionScreen` displays Goals tab.
  3. Tap `+ New Goal` button (1 tap).
  4. Type Title, Target (e.g. 50), Unit (e.g. "km") in dialog.
  5. Tap "Save" (1 tap).
  6. Return to Today to link a daily task to this goal.
  7. *Failure:* Daily tasks have NO concept of connecting to a Goal! A task can link to a Note, Link, or HTML quiz, but cannot reference a Goal.
- **Metrics:** **3 taps to create**, **impossible to connect**.
- **Verdict:** **Broken Connection.** Goals exist in complete isolation from daily planning.

---

### Journey 4: Open a Learning Resource and Start Deliberate Practice
- **Starting Point:** `TodayScreen`.
- **Interaction Sequence:**
  1. Tap Learn tab in bottom navigation (1 tap).
  2. Tap "Begin a short session →" button on the pulse panel (1 tap).
  3. `SessionScreen` launches with 12–20 interleaved questions (MCQ, Cloze, Myth-Fact).
  4. Complete questions with immediate grading feedback.
  5. Rate enjoyment 1–5 stars.
  6. Tap "Done" (1 tap).
  7. Returns to Learn.
- **Metrics:** **3 taps to complete session.**
- **Verdict:** **Strong.** Spaced repetition loop is responsive and pleasant.

---

### Journey 5: Create a Study Note Inside a Project
- **Starting Point:** `TodayScreen`.
- **Interaction Sequence:**
  1. Tap Spaces tab in bottom bar (1 tap).
  2. Tap Workspace (e.g., "Work") (1 tap).
  3. Tap Project (e.g., "Architecture") (1 tap).
  4. Tap `+` button on `ItemsScreen` (1 tap).
  5. Select "Note" (1 tap).
  6. Document editor (`ItemDetailScreen`) opens instantly with cursor focused on title.
  7. Type title and markdown body using formatting bar.
  8. Back arrow auto-flushes edits to SQLite.
- **Metrics:** **5 taps to begin writing.**
- **Verdict:** **Good structure, but high entry friction.** An Inbox-first fast note option is needed.

---

### Journey 6: Find a Previously Visited Project
- **Starting Point:** `TodayScreen`.
- **Interaction Sequence:**
  1. Tap Spaces tab in bottom bar (1 tap).
  2. Under "Recent projects", view the last visited projects.
  3. Tap project row (1 tap).
- **Result:** Directly opens `ItemsScreen` for that project.
- **Metrics:** **2 taps.**
- **Verdict:** **Excellent.** D-048's real visit tracking works reliably.

---

### Journey 7: Save a Web Resource Through Quick Add
- **Starting Point:** Any screen.
- **Interaction Sequence:**
  1. Tap `+` FAB (1 tap).
  2. Switch to "Link" tab (1 tap).
  3. Paste URL and tap "Save Link" (1 tap).
- **Result:**
  - Auto-fetches OpenGraph thumbnail in background.
  - Creates Link Card in the built-in Inbox project.
  - Automatically creates a linked Topic in Learn.
- **Metrics:** **3 taps.**
- **Verdict:** **Flawless.** One of Nimo's best designed workflows.

---

### Journey 8: Import an HTML Document & Play It
- **Starting Point:** `TopicsScreen` (Library tab).
- **Interaction Sequence:**
  1. Tap document row (e.g. "Sample HTML Widget") (1 tap).
  2. Directly renders interactive JavaScript in-place.
  3. Tap "Fullscreen" toggle (1 tap).
  4. Experience immersive quiz / interactive diagram.
- **Metrics:** **2 taps.**
- **Verdict:** **Fixed in D-051.** Previous empty dark box is resolved.

---

### Journey 9: Find and Revise Weak Topics
- **Starting Point:** `TodayScreen`.
- **Interaction Sequence:**
  1. Tap Learn tab (1 tap).
  2. Look for "Weak topics" or "Needs review" filter.
  3. *Failure:* There is no weak topics indicator or filter. Topics only have statuses (`inbox`, `active`, `parked`, `done`). Scheduler retains ease factor and lapse counts in `questions`, but never bubbles up a "weak topic" summary to the user.
- **Metrics:** **Unsupported journey.**
- **Verdict:** **Feature Gap.** Users cannot self-diagnose where they are struggling.

---

### Journey 10: Check Streak & Score History
- **Starting Point:** `TodayScreen`.
- **Interaction Sequence:**
  1. Tap the streak pill (`🔥 7 · 🛡️ 1`) in the top-right of Today's AppBar (1 tap).
  2. Shell triggers `_openDirectionProgress()` and navigates directly to `ProgressScreen`.
  3. View Journey path, streak explanation, dual score trend charts, and calendar history.
- **Metrics:** **1 tap.**
- **Verdict:** **Excellent.** The streak chip shortcut bypasses the Direction tab confusion.

---

### Journey 11: Export an External Backup
- **Starting Point:** `TodayScreen`.
- **Interaction Sequence:**
  1. Tap Settings gear in AppBar (1 tap).
  2. Scroll down to "Backup outside the app" (1 scroll).
  3. Tap "Back Up Now" (1 tap).
  4. App streams SQLite snapshot + library files into Android SAF folder with SHA-256 validation.
  5. SnackBar confirms backup timestamp and file size.
- **Metrics:** **2 taps.**
- **Verdict:** **Rock Solid.** Complete data safety without cloud dependencies.
