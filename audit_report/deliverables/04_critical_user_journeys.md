# DELIVERABLE 4 — CRITICAL USER JOURNEYS

End-to-end evaluation and optimization of the 10 foundational user journeys across Nimo.

---

## Journey 1: Quick Idea Capture and Filing
- **Goal:** User has an immediate thought while walking and wants to record it in 5 seconds.
- **Current Flow:** Tap `+ Note` on Today $\rightarrow$ Dialog prompts "Choose workspace" $\rightarrow$ User selects workspace $\rightarrow$ Dialog prompts "Choose project" $\rightarrow$ User selects project $\rightarrow$ Enters title $\rightarrow$ Opens editor. *(Friction: 5 taps, multiple organizational decisions).*
- **Optimized Flow:** Tap `+ Note` on Today $\rightarrow$ Text prompt appears $\rightarrow$ Type thought $\rightarrow$ Auto-saved directly to **`Inbox`** project $\rightarrow$ SnackBar shows `"Saved to Inbox"` with an **"Open"** button.
- **Result:** Taps reduced from 5 to 2. Zero cognitive friction during capture.

---

## Journey 2: Morning Plan Check-in & Execution
- **Goal:** Open app in the morning, review daily obligations, and start work.
- **Current Flow:** Open app $\rightarrow$ Large greeting header $\rightarrow$ Scroll past week strip $\rightarrow$ Scroll past Quick Add row $\rightarrow$ Reach Today's Plan $\rightarrow$ Tick first routine.
- **Optimized Flow:** Open app $\rightarrow$ Compact brand header with streak $\rightarrow$ Plan sits **above the fold** $\rightarrow$ First routine tapped immediately in 1 tap $\rightarrow$ Tactile checkbox sound and visual strike-through.

---

## Journey 3: Study a Topic & Transition to Practice
- **Goal:** Read a medical pathology PDF and immediately test comprehension.
- **Current Flow:** Open Learn $\rightarrow$ Open Topics $\rightarrow$ Select Topic $\rightarrow$ Tap PDF source $\rightarrow$ Read text cards $\rightarrow$ Highlight key sentence to mark point $\rightarrow$ Cloze minted $\rightarrow$ Back out to Topics $\rightarrow$ Back out to Learn $\rightarrow$ Hope spaced repetition scheduler serves the new card.
- **Optimized Flow:** Open Topic $\rightarrow$ Tap PDF source $\rightarrow$ Mark sentences $\rightarrow$ Return to Topic Detail $\rightarrow$ Tap new **`Practice (N)`** button $\rightarrow$ Direct session launches with the freshly marked cloze points.

---

## Journey 4: Image-Based Visual Structure Identification (Anatomy/Radiology)
- **Goal:** Study a chest X-ray or brain MRI and identify specific anatomical structures.
- **Current Flow:** Card displays image with prompt: *"Tap the Left Ventricle"* $\rightarrow$ User taps image $\rightarrow$ Circle pin drawn $\rightarrow$ System evaluates tap distance using normalized aspect ratio math $\rightarrow$ Green/red feedback.
- **Enhanced Flow (Atlas Mode):**
  1. **Practice Mode:** Tap target structure $\rightarrow$ Instant feedback + anatomical explanation callout.
  2. **Exploration Mode:** Interactive anatomy viewer where tapping any tagged region displays its label, diagnostic significance, and cross-references to the user's project notes.

---

## Journey 5: Evening Day Close & Reflection
- **Goal:** Conclude the workday, reflect on progress, and protect the streak.
- **Current Flow:** At 20:00, Today displays the Day Close banner $\rightarrow$ Tap banner $\rightarrow$ 4-step sheet opens:
  1. *Step 1 (Recap):* Review unticked tasks; tick completed ones or leave for carry-over.
  2. *Step 2 (Major Point):* Write 1-line key learning or win; optionally link to a topic.
  3. *Step 3 (Self Score):* Select chips 1–10 representing subjective effort.
  4. *Step 4 (Dual Reveal):* View objective Done Score side-by-side with subjective Self Score.
- **Outcome:** Day closed $\rightarrow$ Streak preserved $\rightarrow$ Return to Today showing calm completed state.

---

## Journey 6: Goal Milestone Tracking
- **Goal:** Update a scalar progress goal (e.g. read 20 research papers).
- **Current Flow:** Switch to Direction tab $\rightarrow$ Goals tab selected $\rightarrow$ Locate goal card $\rightarrow$ Tap `+` stepper button $\rightarrow$ Progress bar increments $\rightarrow$ Completing reaches 100% celebration.
- **Optimized Alignment:** Goals live in **Progress** under "Milestones & Trajectory", connecting long-term outcome progress directly with daily consistency charts.

---

## Journey 7: Search and Retrieve Past Knowledge
- **Goal:** Find a study note written two weeks ago.
- **Current Flow:** Must remember which Workspace and Project holds the note, or use local filter inside `TopicsScreen`.
- **Optimized Flow:** Quick-filter search available from the top of the **Spaces** tab, querying across project titles and note bodies with instant highlighted matches.

---

## Journey 8: Note Drafting with Safe Route Navigation
- **Goal:** Write a study note and quickly navigate away without losing data.
- **Flow:** User types in note editor $\rightarrow$ Debounced autosave writes to SQLite at 900ms $\rightarrow$ User taps Back arrow immediately while still typing $\rightarrow$ **`PopScope` intercepts pop** $\rightarrow$ `await _flushPending()` finishes writing $\rightarrow$ Route pops safely $\rightarrow$ Parent list displays updated title with zero data loss or flicker.
