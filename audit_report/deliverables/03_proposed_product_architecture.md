# DELIVERABLE 3 — PROPOSED PRODUCT ARCHITECTURE

A clean, coherent structural blueprint retaining the **Four Main Destinations** while eliminating duplication, reducing navigation depth, and establishing clear mental models.

---

## 1. Top-Level Hierarchy: The Four Pillars

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           APP SHELL (4 TABS)                             │
├─────────────────┬──────────────────┬──────────────────┬──────────────────┤
│     TODAY       │      SPACES      │      LEARN       │     PROGRESS     │
│  Daily Focus    │ Personal Library │ Active Practice  │  Self Reflection │
│ & Execution     │   & Workbench    │    & Recall      │   & Trajectory   │
└─────────────────┴──────────────────┴──────────────────┴──────────────────┘
```

| Destination | Single Governing Purpose | What Belongs Here | What MUST NOT Belong Here |
|---|---|---|---|
| **Today** | What do I need to execute and finish *today*? | Active plan tasks, daily recurring routines, If-Then intention, Quick Add pill row, Evening Day Close trigger, Sunday weekly summary. | Permanent workspace browsing, full goal backlogs, entire topic libraries, raw notes archive. |
| **Spaces** | Where do I store, organize, and read my notes and projects? | High-level Workspaces, Project folders, Pages (Notes, Checklists, Link bookmarks, interactive HTML documents), Recent Projects list. | Daily task lists, spaced repetition flashcard sessions, habit streak counters. |
| **Learn** | How do I master knowledge through deliberate practice and reading? | Spaced repetition practice queue (16-card sessions), Topics directory, Study Sources (PDFs/TXT/ePub), Marked Points (cloze generators), Visual/Image quiz packs. | Generic non-study tasks, random meeting notes, long-term life outcome goals. |
| **Progress** | How am I evolving over time? | Habit streak continuity (2-signal fold), Done vs. Self score analytics, Weekly retrospective archives, Weak topic retention radar, Outcome Goals & milestones. | Ephemeral daily check-in buttons, document drafting, flashcard practice feeds. |

---

## 2. Destination 1: TODAY — Streamlined Execution Dashboard

### Key Structural Changes:
1. **Eliminate Duplicated Sections:**
   - **Remove Pinned Spaces:** Space navigation belongs in the Spaces tab.
   - **Remove Recently Touched Items:** Recent notes are accessible from Spaces.
   - **Remove Goals Section:** Goals live in Progress alongside long-term trajectory.
2. **Above-the-Fold Optimization:**
   - Compact editorial brand bar to 48dp on mobile.
   - Ensure the user's **First Task / Routine** is 100% visible immediately upon app boot without scrolling.
3. **Structured Daily Stack:**
   - **Header:** Nimo logo + current date chip + compact streak flame (`🔥 12`).
   - **Quick Add Row:** 4 direct pill buttons (`Task`, `Goal`, `Note`, `Checklist`). Note & Checklist route instantly into the default `Inbox` project.
   - **Today's Plan:**
     - Non-negotiable Daily Routines (Core Habits).
     - Carried-Over & New One-Off Tasks.
   - **Daily Deliberate Practice Cue:** A compact 72dp card indicating due review cards (`"12 cards ready for review →"`).
   - **Evening Day Close (Adaptive):** Activates after 19:00 or when all core items are ticked.

---

## 3. Destination 2: SPACES — The Personal Workbench

### Key Structural Changes:
1. **Model:** Retain `Workspace → Projects → Pages/Items`.
2. **Flattened Fast Access:**
   - **Top Row:** Quick-access chip for the default **`Inbox`** project (`📥 Inbox (3)`), allowing 1-tap capture review.
   - **Recent Section:** Direct access to the last 3 modified notes/pages without having to drill through workspace folders.
3. **Information Density on Workspace Rows:**
   - Display project count and last active date quietly beneath the workspace title (e.g. `"Work · 4 projects · active yesterday"`).
4. **Document Editor Refinement:**
   - Plain-text drafting with D-049 formatting bar.
   - Add a clean read-only **Preview Mode** toggle for markdown notes.
   - 100% protected autosave via `PopScope`.

---

## 4. Destination 3: LEARN — Dedicated Deliberate Practice

### Key Structural Changes:
1. **Unified Study Flow:**
   $$\text{Attach/Import Material} \longrightarrow \text{Read \& Mark Sentences} \longrightarrow \text{Direct Practice} \longrightarrow \text{Spaced Review Queue}$$
2. **Direct Topic Practice:**
   - Expose the **"Practice (N)"** button directly on `TopicDetailScreen` so studying material immediately flows into active recall.
3. **Visual & Image-Based Practice Architecture:**
   - Enhance `ImagePointCard` to support **Multi-Structure Exploration Mode**:
     - *Mode A (Identification / Test):* "Tap the Left Ventricle" $\rightarrow$ Tap image $\rightarrow$ Pin feedback.
     - *Mode B (Interactive Atlas / Study):* User taps any anatomical structure on an image $\rightarrow$ Callout bubble reveals its name, role, and linked notes.
4. **Weak-Topic Revision Indicator:**
   - Topics with high lapse rates (>30% incorrect recall) receive a subtle `"Needs revision"` tag on both the Learn screen and Topic list.

---

## 5. Destination 4: PROGRESS — Reflection & Trajectory

### Key Structural Changes:
1. **Rename Tab:** From ambiguous `"Direction"` to clear **`Progress`** (or **`Trajectory`**).
2. **Section Hierarchy:**
   - **Hero Summary:** Current Streak status (`🔥 14 Days Active`) + Held Shields (`🛡️ 2`).
   - **Dual Score Reflection Trends:** Side-by-side graphs of Done Score (auto-calculated daily tasks) vs. Self Score (personal 1–10 evening evaluation).
   - **Milestones & Outcome Goals:**
     - Scalar outcome goals moved here from Direction.
     - Displays progress bars and `−`/`+` steppers.
   - **Topic Retention Radar:** Displays retention stability across study topics, highlighting strong vs. decaying knowledge.
   - **Weekly Retrospective Archive:** Access past Mon–Sun weekly wrapped reports.
