# DELIVERABLE 5 — PRIORITISED ROADMAP

A pragmatic, multi-phase implementation roadmap ranked by user impact, implementation cost, and technical risk.

---

## Prioritisation Matrix (Value × Confidence ÷ Cost)

```
        HIGH VALUE
            │   [P0] Fast Note Capture
            │   [P0] Today Decluttering
            │   [P0] Autosave Pop Safety
            │   [P1] Direct Topic Practice
            │   [P1] Routine Auto-Add Today
            │
            │   [P2] Multi-Structure Image Practice
            │   [P2] Note Markdown Preview Toggle
            │   [P2] Global Search
            │
────────────┼─────────────────────────────► HIGH COST
            │   [P3] Peer-to-Peer LAN Sync
            │   [P3] Home Screen Widget
            │
        LOW VALUE
```

---

## Phase 1: Core Usability & Reliability (Completed / Verified)
*Zero schema migrations required. 100% backward compatible.*

- [x] **P0-1: Streamline Today Screen Defaults**
  - Default duplicated sections (`Pinned Spaces`, `Recent Items`, `Goals`) to disabled on Today so the plan sits above the fold.
- [x] **P0-2: Inbox-First Fast Note & Checklist Capture**
  - Eliminate multi-step workspace/project pickers on quick-add. Insert directly into built-in `Inbox` project.
- [x] **P0-3: Autosave Pop Protection**
  - Wrap `ItemDetailScreen` in `PopScope` to guarantee that asynchronous SQLite writes complete before route pops.
- [x] **P0-4: Direct Practice Trigger on Topic Detail**
  - Expose `SessionScreen(..., topicId: topic.id)` via a "Practice (N)" button on `TopicDetailScreen`.
- [x] **P0-5: Immediate Routine Generation for Today**
  - When creating a recurring habit template that matches today's weekday, automatically add it into today's active plan.

---

## Phase 2: Navigation Refinement & Workspace Efficiency (Upcoming)
*Focus: Clear mental models, reducing navigation friction.*

- [ ] **P1-1: Rename & Focus 4th Tab to "Progress"**
  - Rename bottom bar destination from `Direction` to `Progress`.
  - Present Progress as the primary analytical surface with Goals integrated as milestones.
- [ ] **P1-2: Compact Responsive Mobile Headers**
  - Implement collapsible SliverAppBars across Today, Learn, and Spaces to recover 60–80dp of vertical viewport on mobile.
- [ ] **P1-3: Workspace Content Indicators**
  - Add quiet project count badges (e.g. "4 projects") to workspace rows in `WorkspacesScreen`.
- [ ] **P1-4: Settings Grouped Card Architecture**
  - Structure `SettingsScreen` into clear `NeoPanel` cards (Appearance, Reminders, Storage & Backup, Sync, About).

---

## Phase 3: Visual Learning & Knowledge Enhancements
*Focus: Deepening learning capabilities for visual disciplines.*

- [ ] **P2-1: Interactive Multi-Structure Image Exploration (Atlas Mode)**
  - Expand `ImagePointCard` to support viewing multiple labelled regions on medical, anatomical, or technical diagrams.
  - Tapping a structure displays its identification callout and clinical notes.
- [ ] **P2-2: Read-Only Markdown Preview Toggle**
  - Add a view/edit toggle in `ItemDetailScreen` allowing clean typography preview of markdown headings, bold text, and checklists.
- [ ] **P2-3: Universal Cross-Entity Search**
  - Implement an in-memory or SQLite FTS search bar querying across Notes, Checklists, Topics, and Tasks.

---

## Phase 4: Long-Term Platform Features (Backlog)
- [ ] **P3-1: Automatic Peer LAN Sync (Stage B)**
  - mDNS device discovery and TLS sync between desktop and phone.
- [ ] **P3-2: Android Glance Home-Screen Widget**
  - Quick-view daily plan widget for Android launcher.
