# DELIVERABLE 6 — DESIGN DIRECTION & PRINCIPLES

Visual and interaction design principles to preserve Nimo's quiet, editorial identity while ensuring tactile mobile ergonomics.

---

## 1. Core Visual Principles

1. **Quiet Editorial Aesthetic over Dashboard Noise:**
   - Nimo is not a corporate SaaS tool or a gamified mobile game.
   - High-contrast, calm typography (Playfair serif for titles, clean sans-serif for UI, monospaced for metadata/dates).
   - Warm background canvas tones (`AppThemeChoice.dark`: deep dark gray/black; `AppThemeChoice.light`: soft warm paper).
2. **Tactile Restraint:**
   - Soft, subtle surface elevations (`NeoPanel`, `NeoRaisedSm`) rather than heavy drop shadows.
   - Purposeful corner radii: controls = 3dp, cards = 10dp, navigation shell = 17dp.
3. **Information Density with Breathing Room:**
   - Generous touch targets for interactions (minimum 48x48dp per Material guidelines).
   - Zero gratuitous decorative cards. Every card must contain an actionable trigger or active obligation.

---

## 2. Low-Fidelity Screen Layout Blueprints

### A. Optimized Today Screen (Mobile Viewport)
```
┌──────────────────────────────────────────────┐
│ [Nimo Logo] Nimo               (🔥 12)  [⚙] │ 48dp AppBar
├──────────────────────────────────────────────┤
│ [ Task ]    [ Goal ]    [ Note ]  [Checklist]│ 56dp Quick Add
├──────────────────────────────────────────────┤
│ Today's plan                Edit routine →  │
│ ──────────────────────────────────────────── │
│ [ ] Read 1 chapter of Anatomy       (Core)   │
│ [ ] Review pharmacology flashcards  (Core)   │ Above-The-Fold
│ [ ] Follow up on clinic schedule             │ Immediate Focus
│                                              │
│ [⚡] If I feel distracted, then I take a walk │
├──────────────────────────────────────────────┤
│ ┌──────────────────────────────────────────┐ │
│ │ 📖 12 cards ready for deliberate review  │ │ Deliberate Practice
│ └──────────────────────────────────────────┘ │ Trigger
├──────────────────────────────────────────────┤
│ [🌙 Day Close banner (adaptive evening)]     │
├──────────────────────────────────────────────┤
│ [Today]       [Spaces]      [Learn] [Progress] 56dp Bottom Bar
└──────────────────────────────────────────────┘
```

### B. Interactive Medical / Anatomical Image Card Blueprint
```
┌──────────────────────────────────────────────┐
│ Learn · Radiology / Anatomy                  │
├──────────────────────────────────────────────┤
│ "Identify the highlighted anatomical landmark"│ Question Prompt
├──────────────────────────────────────────────┤
│ ┌──────────────────────────────────────────┐ │
│ │                                          │ │
│ │             [ Chest X-Ray ]              │ │
│ │                                          │ │
│ │                 [ • ]                    │ │ Letterbox-Safe
│ │              User Tap Pin                │ │ Aspect Ratio Canvas
│ │                                          │ │
│ │                                          │ │
│ └──────────────────────────────────────────┘ │
├──────────────────────────────────────────────┤
│ ┌──────────────────────────────────────────┐ │
│ │ ✓ Correct: Aortic Arch                   │ │ Instant Anatomical
│ │ Radius error: 4.2% · Latency: 1.4s       │ │ Explanation Callout
│ └──────────────────────────────────────────┘ │
├──────────────────────────────────────────────┤
│ [                   Continue                 ] │ Primary Bottom Button
└──────────────────────────────────────────────┘
```
