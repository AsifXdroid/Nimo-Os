> **SUPERSEDED (2026-11-05, D-052):** the Green & Black prototype is now the app's visual foundation — see docs/DECISIONS.md D-052. This document is kept as the record of the Spatial direction it replaced.

# DESIGN DIRECTION: SOFT NEUTRAL SPATIAL — ARCHITECTURAL MINIMALISM
Generated: November 4, 2026
Direction: Production-Grade Spatial Mobile UI

---

## 1. Philosophical Manifesto: Anti-Slop, High Craft

Nimo is not a colorful toy, a gaming dashboard, or a generic AI-generated template.
It is an **architectural personal sanctuary**:
- **Quiet Dignity**: High contrast without harshness; soft neutral surfaces that let personal thoughts and intentions breathe.
- **Physical Reality (Spatial Depth)**: Depth is functional, not decorative. Elements float, rest, or sink according to their temporal urgency and focus.
- **Editorial Art Direction**: Large, elegant serif headings paired with crisp mono metadata and balanced sans-serif body copy.
- **Tactile Weight (Emil Kowalski)**: When pressed, surfaces physically yield along the $Z$-axis immediately (`onPointerDown`), responding with authentic mass and spring damping.

---

## 2. Core Color & Tonal Architecture

| Role | Token Name | Dark Mode (Midnight Plate) | Light Mode (Warm Paper Plate) | Purpose |
|---|---|---|---|---|
| **Environment Canvas** | `canvas` | `#111614` (Deep Evergreen) | `#E8E5DA` (Warm Paper) | Primary background room |
| **Primary Brand Accent** | `brandTeal` | `#2DD4BF` (Mint Radiance) | `#285C4D` (Deep Teal) | Brand mark, active state, core milestones |
| **Secondary Accent** | `mutedTeal` | `#577877` | `#4A6B6A` | Inactive tracks, secondary metadata |
| **Elevated Surface (E1)** | `surfaceElevated` | `#16201C` (Smoked Glass) | `#FAF9F5` (Soft Porcelain) | Cards, project tiles, score wells |
| **Active Surface (E2)** | `surfaceActive` | `#1E2C27` | `#FFFFFF` | Currently active task, focused item |
| **Detached Floating (E3)**| `surfaceFloating`| `rgba(22, 32, 28, 0.85)` | `rgba(250, 249, 245, 0.90)` | Floating Capsule Navigation, FAB (+) |
| **Primary Text** | `textPrimary` | `#F0F5F7` (Porcelain) | `#141A17` (Deep Obsidian) | High-contrast editorial headings |
| **Secondary Text** | `textMuted` | `#8A9E99` | `#636F6B` | Supporting descriptions, metadata |
| **Specular Rim** | `specular` | `rgba(255, 255, 255, 0.14)`| `rgba(0, 0, 0, 0.08)` | Uniform illuminated top/side rim |

---

## 3. The 4 Spatial Surface Classes

1. **Environment Canvas ($Z = 0\text{dp}$)**:
   - Deep Evergreen / Warm Paper.
   - Houses static editorial greetings, dates, and background timeline rails.
2. **Elevated Content Cards ($Z = +6\text{dp}$)**:
   - Houses Quiet Progress score wells, projects, and inactive tasks.
   - Dual shadows: diffuse ambient room bounce ($16\text{px}$ blur) + contact occlusion ($4\text{px}$ blur).
   - $1.0\text{px}$ illuminated rim.
3. **Active Focus Plane ($Z = +12\text{dp}$)**:
   - Houses the currently active plan item or active learn session.
   - Ambient mint glow halo (`glowColor: #2DD4BF.withValues(alpha: 0.15)`).
   - Real-time 3D pointer tilt (`SpatialPerspective`).
4. **Detached Floating Ornaments ($Z = +24\text{dp}$ to $+44\text{dp}$)**:
   - Floating Capsule Navigation Bar, Floating Quick Add Orb (`+`), and Modal Action Sheets.
   - $16\text{px}$ Gaussian backdrop blur (`BackdropFilter`).
   - Sits completely decoupled from the window frame with breathing depth.
