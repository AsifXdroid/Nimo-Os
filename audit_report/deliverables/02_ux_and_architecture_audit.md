# DELIVERABLE 2 — UX & ARCHITECTURE AUDIT

A rigorous forensic audit of usability, information architecture, and technical friction across the application.

---

## 1. Top-Level Architectural Problems

### Issue IA-01: The "Direction" Navigation Misnomer
- **Severity:** High (P1)
- **Location:** [`lib/features/direction/direction_screen.dart`](file:///home/Asif/Downloads/Nomi%202/nimo-os-test/lib/features/direction/direction_screen.dart) & Navigation Shell ([`main.dart`](file:///home/Asif/Downloads/Nomi%202/nimo-os-test/lib/main.dart#L445-L450))
- **Evidence:** `DirectionScreen` functions solely as a tab wrapper holding **Goals** and **Progress**. The bottom bar icon (`Icons.explore_outlined`) and label "Direction" obscure the fact that habit streaks, reflection calendars, and score trends live inside it. To open Progress from the streak chip on Today, the app is forced to pass an out-of-band callback `_directionRequest = 1`.
- **Root Cause:** Artificial bundling of two different mental modes: active project milestone tracking (Goals) vs. retrospective evaluation and analytics (Progress).
- **User Impact:** Users looking for their learning history, reflection charts, or streak details cannot intuitively find them under "Direction".

### Issue IA-02: Screen Bloat & Destination Duplication on Today
- **Severity:** High (P1)
- **Location:** [`lib/features/today/today_screen.dart:530-575`](file:///home/Asif/Downloads/Nomi%202/nimo-os-test/lib/features/today/today_screen.dart#L530-L575)
- **Evidence:** Physical vertical scroll capture on Android emulator (`ct_avd`, 320x640) proved that Today spans **3,200 vertical pixels (5–6 viewports)**.
- **Root Cause:** Today tries to act as a universal dashboard rather than an execution focus surface. It stacks 10 distinct sections, including **Pinned Spaces** (duplicating Spaces), **Recently Touched Items** (duplicating Spaces), and **Goals** (duplicating Direction).
- **User Impact:** Cognitive overload. On opening the app in the morning, the user is confronted with a massive backlog rather than a calm, actionable daily plan.

---

## 2. Destination-by-Destination Usability Audit

### A. Today (Daily Execution)
1. **Vertical Space Above the Fold:**
   - *Evidence:* The top of Today renders the Brand header (~110px), Quick Add pill row (~60px), Plan header (~80px), and Week tab switcher before the first task is reached.
   - *Impact:* On compact mobile devices, nearly half the screen is occupied before the user sees what they need to execute.
2. **Unticked Tasks vs. Routines Clarity:**
   - *Evidence:* While D-002 cleanly carries forward unticked one-offs, the visual distinction between a recurring daily routine and a carried-over one-off task relies solely on a small `routine` / `one-off` subtitle.
   - *Impact:* Users cannot instantly distinguish non-negotiable daily core habits from opportunistic to-dos.

### B. Spaces (Personal Knowledge Base)
1. **Friction in Deep Workspace Hierarchy:**
   - *Evidence:* [`WorkspacesScreen`](file:///home/Asif/Downloads/Nomi%202/nimo-os-test/lib/features/workspaces/workspaces_screen.dart) → [`ProjectsScreen`](file:///home/Asif/Downloads/Nomi%202/nimo-os-test/lib/features/projects/projects_screen.dart) → [`ItemsScreen`](file:///home/Asif/Downloads/Nomi%202/nimo-os-test/lib/features/items/items_screen.dart) → [`ItemDetailScreen`](file:///home/Asif/Downloads/Nomi%202/nimo-os-test/lib/features/items/item_detail_screen.dart).
   - *Impact:* Accessing a specific note requires **4 taps and 3 page transitions**. While "Recent Projects" helps, there is no quick-jump to "Recent Notes" within Spaces.
2. **Missing Workspace Content Metadata:**
   - *Evidence:* In `WorkspacesScreen`, workspace rows show only the monogram avatar and name. They do not display how many projects or notes live inside.
   - *Impact:* Empty workspaces look identical to actively populated ones.

### C. Learn (Deliberate Practice)
1. **Disconnection Between Reading and Active Recall:**
   - *Evidence:* In [`TopicDetailScreen`](file:///home/Asif/Downloads/Nomi%202/nimo-os-test/lib/features/learn/topic_detail_screen.dart), users attach reading sources (PDF/TXT) and highlight sentences to extract cloze points. Once minted, there was previously no way to practice that topic directly from the reading view.
   - *Impact:* The user had to leave their study material, switch to the main Learn screen, and hope the spaced repetition algorithm queued those specific cards.
2. **Visual Learning / Image-Based Practice Bottlenecks:**
   - *Evidence:* [`question_cards.dart:546-720`](file:///home/Asif/Downloads/Nomi%202/nimo-os-test/lib/features/learn/question_cards.dart#L546-L720) implements `ImagePointCard` with letterbox aspect-ratio math, but questions currently only support a **single target circle**.
   - *Impact:* Complex anatomical or radiological practice (identifying 10 structures on a single scan) requires importing 10 separate question records rather than providing a multi-structure inspection canvas.

### D. Progress (Reflection & Evaluation)
1. **Vanity Metric Risk vs. Actionable Insights:**
   - *Evidence:* [`progress_screen.dart`](file:///home/Asif/Downloads/Nomi%202/nimo-os-test/lib/features/progress/progress_screen.dart) shows total questions answered, current streak, and shield counts.
   - *Defect:* It does not clearly highlight **lapse rates by topic** (i.e. "Which specific topics am I consistently forgetting?").
   - *Impact:* Progress celebrates showing up, but does not guide the user on what to study next to repair weak knowledge.

---

## 3. Cross-Cutting Usability & Ergonomics Issues

1. **Destructive Delete Placement:**
   - *Evidence:* Historical feedback noted that delete buttons were placed directly adjacent to primary actions.
   - *Status:* Mostly remediated via 3-dot overflow menus and two-step confirmation dialogs (`confirmDelete`), but requires ongoing vigilance.
2. **Editor Autosave Pop Race Condition:**
   - *Evidence:* [`item_detail_screen.dart:114`](file:///home/Asif/Downloads/Nomi%202/nimo-os-test/lib/features/items/item_detail_screen.dart#L114) previously used unawaited flushes on dispose.
   - *Remediation:* Protected with `PopScope` to guarantee that SQLite writes complete before the parent route refreshes.
3. **Absence of Markdown Preview Toggle:**
   - *Evidence:* Notes are edited with raw markdown characters (`**`, `#`, `- [ ]`).
   - *Impact:* Once a study note is finished, it remains in raw editing mode. There is no clean, calm "Reading/Preview" mode for formatted notes.
