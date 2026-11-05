# DELIVERABLE 7 — PRODUCT OWNER DECISION REGISTER

Decisions requiring product-owner authorization, presenting objective arguments and trade-offs.

---

## Decision 1: Relocating Duplicated Sections from Today's Screen

### The Situation:
Currently, the Today screen renders `Pinned Spaces`, `Recently Touched Items`, and `Goals` in addition to the daily plan, stretching the screen to over 3,200 vertical pixels.

### Proposed Change:
Permanently remove `Pinned Spaces` and `Recently Touched Items` from Today's scroll view, keeping them strictly within the **Spaces** tab. Keep Today focused on the daily plan, routines, learning triggers, and Day Close.

### Arguments for Keeping Current Behaviour:
- Users can see recent notes and pinned folders without having to tap into Spaces.
- Acts as a "one-stop dashboard" for everything in the app.

### Arguments for Changing:
- Physical emulator scroll captures proved that Today is overloaded with 6 viewports of content.
- A morning execution screen should communicate what to do *now*, not act as a second content library.
- Removing duplicated sections cuts Today's source code and vertical canvas by 60%, eliminating scroll lag.

### Recommendation:
**Approve the change.** Pinned spaces and recent projects already function seamlessly inside the Spaces tab.

---

## Decision 2: Renaming Tab 4 from "Direction" to "Progress"

### The Situation:
The 4th destination is labeled "Direction" (`Icons.explore_outlined`). It contains two tabs: Goals and Progress.

### Proposed Change:
Rename the 4th destination to **Progress** (or **Goals & Progress**), making the analytical Progress surface (streak, Done/Self score graphs, weekly summary) the primary hero view, with Goals accessible as long-term milestones.

### Arguments for Keeping Current Behaviour:
- "Direction" sounds philosophical and non-judgmental ("A direction, not a deadline").
- Preserves existing naming in `docs/DECISIONS.md` (D-045).

### Arguments for Changing:
- "Direction" is obscure and does not communicate that streaks, score graphs, and weekly retrospectives live inside.
- The streak chip on Today has to use a confusing indirect route to open Progress inside Direction.
- Every mainstream mobile app uses clear, predictable tab labels.

### Recommendation:
**Approve renaming to "Progress".** It directly describes the user's trajectory without diluting Nimo's philosophy.

---

## Decision 3: Multi-Structure Visual Exploration vs. Discrete Single Questions

### The Situation:
The current `ImagePointCard` allows testing only a single point per question record (e.g. "Tap the Left Ventricle").

### Proposed Change:
Support an **Atlas / Exploration Mode** where a single high-resolution image (e.g. Brain MRI, Cardiac Anatomy) can contain multiple annotated regions, allowing free-form tap-to-reveal study before entering test mode.

### Arguments for Keeping Current Behaviour:
- Simpler data structure: 1 question = 1 target coordinate.
- Matches standard flashcard mental models.

### Arguments for Changing:
- In complex visual domains (medicine, radiology, engineering), real learning occurs by understanding how structures relate to one another on a whole organ or scan, not in isolated micro-cards.
- Reduces pack authoring friction by allowing 1 image to serve as a comprehensive visual module.

### Recommendation:
**Approve introducing Atlas Mode in Phase 3.** Keep existing single-question format fully backward compatible while allowing multi-point datasets.
