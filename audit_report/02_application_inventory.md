# Complete Application Inventory

A code-verified inventory of every screen, route, dialog, modal sheet, and flow in Nimo.

---

## 1. Top-Level Destinations (App Shell)

| Destination ID | Screen Class | File Path | Purpose | Available Actions | Data Dependencies | Implementation Status |
|---|---|---|---|---|---|---|
| `today` | `TodayScreen` | `lib/features/today/today_screen.dart` | The daily execution dashboard ("Hub Home"). | Toggle plan items, switch Today/This week, tap quick-add pills, open routine editor, open Day Close, open linked resources, launch learning session, open Settings, customize home sections, open weekly summary. | `todayStore`, `reviewStore`, `goalsStore`, `store`, `learn`, `progressStore` | Fully Implemented (2,139 lines) |
| `learn` | `LearnScreen` | `lib/features/learn/learn_screen.dart` | The deliberate learning landing page. | Start review/episode/boss session, open all topics (`TopicsScreen`), open single topic, import pack (`.quizpack`), open image verify list. | `learnStore`, `learnEngineStore`, `store` | Fully Implemented (469 lines) |
| `spaces` | `WorkspacesScreen` | `lib/features/workspaces/workspaces_screen.dart` | Personal workspace and project hierarchy ("Workbench"). | Open workspace (`ProjectsScreen`), open recent project (`ItemsScreen`), create workspace, long-press actions (rename, pin/unpin, delete). | `store` (`workspaces`, `projects`, `recentProjectVisits`) | Fully Implemented (319 lines) |
| `direction` | `DirectionScreen` | `lib/features/direction/direction_screen.dart` | Combined container hosting Goals and Progress. | Switch between Goals tab and Progress tab. Streak chip jumps to Progress. | `goalsStore`, `progressStore`, `todayStore`, `reviewStore` | Fully Implemented (135 lines) |

---

## 2. Nested Screens & Full-Page Routes

| Screen Class | File Path | Parent / Entry Route | Purpose | Available Actions | Exit / Return Path | Implementation Status |
|---|---|---|---|---|---|---|
| `RoutineScreen` | `lib/features/today/routine_screen.dart` | `TodayScreen` ("Edit routine →") | Define daily recurring habit templates and the If-Then intention line. | Add routine template, toggle active/inactive, reorder/edit habit details (tiny version, anchor, track, core flag), schedule weekdays, link Spaces item or URL, add to today's plan, delete template, edit If-Then line. | Back AppBar button → returns to Today and refreshes plan. | Fully Implemented (535 lines) |
| `DayCloseScreen` | `lib/features/review/day_close_screen.dart` | `TodayScreen` (Day Close card/banner) | Evening 4-step reflection flow (Recap → Major Point → Self Score → Dual Reveal). | Toggle missed/completed items, type 1-line major win, link point to a topic, select 1–10 Self Score chips, view auto Done Score vs Self Score, close day. | "Close the day" / "Done" → pops to Today; updates streak. | Fully Implemented (434 lines) |
| `TopicsScreen` | `lib/features/learn/topics_screen.dart` | `LearnScreen` ("All topics →") / `TodayScreen` (Inbox topic card) | Central knowledge hub with 2 tabs: Topics & Library. | Search topics, filter status chips (All, Inbox, Active, Parked, Done), open topic detail, import file to library, open library source, create new topic. | Back button → returns to Learn/Today. | Fully Implemented (519 lines) |
| `TopicDetailScreen` | `lib/features/learn/topic_detail_screen.dart` | `TopicsScreen` / `LearnScreen` / `ItemsScreen` | Manage sources, reading, and marked points for a single topic. | Open source in viewer, mark points on reading cards, add source (PDF/TXT/Link/HTML via modal), 3-dot menu (rename, move project, delete), mint questions. | Back button → returns to caller. | Fully Implemented (538 lines) |
| `ReadingScreen` | `lib/features/learn/reading_screen.dart` | `TopicDetailScreen` (tap TXT or extracted PDF source) | Reading card interface with text selection for marking points. | Read card by card, highlight text to mark key point (cloze blank), unmark point. | Back button → updates marked points count. | Fully Implemented (367 lines) |
| `PdfSourceScreen` | `lib/features/learn/pdf_source_screen.dart` | `TopicDetailScreen` (tap PDF source) | Embedded PDF reader via `pdfrx`. | Scroll pages, zoom, view extraction status banner, open text reading cards. | Back button → returns to Topic Detail. | Fully Implemented (214 lines) |
| `SessionScreen` | `lib/features/learn/session_screen.dart` | `LearnScreen` ("Begin short session") | Active spaced-repetition and deliberate practice feed (12–20 cards). | Answer cards (MCQ, cloze, myth-fact, roleplay, boss level, image point), rate enjoyment (1–5 stars), view session stats. | Finish / Abandon → updates review log and scheduler. | Fully Implemented (612 lines) |
| `ImageVerifyListScreen` | `lib/features/learn/image_verify_screen.dart` | `LearnScreen` ("image targets to check") | Gate to verify tap-on-image coordinates for imported quiz packs. | Tap target areas, verify coordinate accuracy, approve question for session queue. | Back button → returns to Learn. | Fully Implemented (280 lines) |
| `ProjectsScreen` | `lib/features/projects/projects_screen.dart` | `WorkspacesScreen` (tap Workspace row) | Lists all projects inside a selected workspace. | Open project (`ItemsScreen`), create project, long-press/3-dot (rename, delete). | Back button → returns to Spaces. | Fully Implemented (245 lines) |
| `ItemsScreen` | `lib/features/items/items_screen.dart` | `ProjectsScreen` (tap Project row) | Project view listing all items (Notes, Checklists, Links, HTML) and project topics. | Open item detail, create note/checklist/link/HTML item, 3-dot menu (rename, delete), open topic. | Back button → returns to Projects. | Fully Implemented (467 lines) |
| `ItemDetailScreen` | `lib/features/items/item_detail_screen.dart` | `ItemsScreen` / `TodayScreen` (recent/pinned) | Multi-type document editor (Note markdown editor, Checklist editor, Link card preview, embedded HTML document). | Edit title, type body with formatting toolbar (Bold, Italic, Heading, Bullet, Numbered, Checkbox), autosave, toggle checklist items, fetch/attach link thumbnails, toggle fullscreen HTML. | Back button → flushes autosave, returns to caller. | Fully Implemented (1,025 lines) |
| `HtmlQuizPlayerScreen` | `lib/features/items/html_quiz/html_quiz_player_screen.dart` | `ItemDetailScreen` (fullscreen mode) / `TopicsScreen` | Hardened WebView sandbox for interactive HTML files. | Interactive JavaScript runtime, reload, toggle fullscreen. | Back button → returns to item detail. | Fully Implemented (215 lines) |
| `WeeklySummaryScreen` | `lib/features/progress/weekly_summary_screen.dart` | `TodayScreen` (Sunday card) / `ProgressScreen` | Weekly reflection report for a Mon–Sun cycle. | View total tasks done, core habit consistency, learning enjoyment average, dual score averages, past weeks archive. | Back button → returns to caller. | Fully Implemented (310 lines) |
| `SettingsScreen` | `lib/features/settings/settings_screen.dart` | `TodayScreen` (top-right gear icon) | App settings, reminders, appearance, backup and LAN sync. | Switch theme (Dark / Light), toggle morning/evening reminders, pick reminder times, backup now, restore backup, external SAF backup folder, LAN sync export/import. | Back button → returns to Today. | Fully Implemented (337 lines) |
| `OnboardingScreen` | `lib/features/onboarding/onboarding_screen.dart` | `OnboardingGate` (first fresh launch) | 3-step introduction to Nimo philosophy. | Walkthrough cards, pick initial starter routine, complete onboarding. | Finish → sets onboarding complete flag in `app_settings`, lands on Today. | Fully Implemented (290 lines) |

---

## 3. Modals, Sheets & Dialogs

| Modal / Dialog Name | Invoked From | Purpose | Form Inputs & Controls | Destructive / Dismissible |
|---|---|---|---|---|
| `QuickAddSheet` (`quick_add_sheet.dart`) | Global FAB / Today quick-add row | Capture anything into Nimo in 1–2 taps. | Tabs: Task (title, today toggle), Note (title, body), Link (URL, auto-fetch), Topic (title, track). | Safe dismiss on tap outside. |
| `Customize Home` Dialog | `TodayScreen` ("Customize Home") | Show/hide sections on the Hub Home screen. | SwitchListTiles for Header Greeting, Date, Eyebrow, Heading, Tagline, Week Strip, Day Close, Pinned, Recent, Goals. | Cancel / Save buttons. Persists to `app_settings`. |
| `PlanTaskSheet` | `TodayScreen` (tap ⋯ or long-press task) | Task actions for today's plan. | Edit title, attach/remove linked resource (note/link/quiz), delete task (confirmed). | Warns on deleting core habit. |
| `ScheduleLinkDialog` | `RoutineScreen` ("Schedule & link") | Routine recurrence rules. | Checkboxes for Mon–Sun, linked item picker, bare URL textfield. | Cancel / Save. |
| `HabitDetailsDialog` | `RoutineScreen` ("Habit details") | Tiny habit fields (§R5.5). | TextFields for Tiny version, Anchor moment, Track choice chips, Counts Core switch. | Cancel / Save. |
| `AddSourceSheet` | `TopicDetailScreen` ("+ Add source") | Attach study material to topic. | 4 options: Import File (PDF/TXT), Add Link (URL), Add Text Note, Import HTML. | Dismissible bottom sheet. |
| `WorkspaceActionsSheet` | `WorkspacesScreen` (long press) | Quick workspace management. | Rename, Pin/Unpin from Home, Delete (confirmed). | Delete is red & guarded. |
| `RestoreConfirmDialog` | `SettingsScreen` (Restore Backup) | Guards against accidental data overwrites (D-011). | Type confirmation or tap explicit "Replace local data" warning. Automatically takes pre-restore backup. | High-safety destructive guard. |

---

## 4. Partially Implemented & Planned Features

| Feature ID | Description | Current Status in Code | Gaps & Missing Links |
|---|---|---|---|
| `SYNC-Stage-B` | Automatic mDNS / TLS peer LAN synchronization | **Planned (S8)**. Not implemented. | Only Stage A (manual file export/import) exists. |
| `WIDGET` | Android home-screen Today widget | **Backlog (S8)**. Not implemented. | No native Glance/AppWidget provider code. |
| `AUDIO` | Audio notes and audio playback linked to tasks | **Deferred**. | Database supports generic files, but audio recorder/player is not built. |
| `SEARCH` | Universal full-text search across notes, topics, and tasks | **Partially Implemented**. | Local search exists inside `TopicsScreen` and `ProjectsScreen`, but no global search bar across all entities. |
| `RICH-TEXT` | Rich text formatting in notebook | **Partially Implemented (D-049)**. | Plain-text markdown syntax toolbar exists (`**`, `#`, `- [ ]`), but markdown preview / WYSIWYG rendering is not implemented. |
