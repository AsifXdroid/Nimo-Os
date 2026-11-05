# NIMO SPATIAL DESIGN SYSTEM: TOKENS & COMPONENT ARCHITECTURE
Generated: November 4, 2026
Status: Active System Standard

---

## 1. Spatial Elevation Tokens (`SpatialDepth`)

```dart
abstract final class SpatialDepth {
  static const double deep = -8.0;      // Recessed / completed tasks
  static const double base = 0.0;       // Canvas level / timeline rails
  static const double elevated = 6.0;   // Content cards / score wells
  static const double active = 12.0;    // Active focus / in-progress tasks
  static const double ornament = 24.0;  // Floating Capsule Nav / Quick Add Orb
  static const double modal = 44.0;     // Contextual sheets / inspection HUDs
}
```

---

## 2. Dual-Shadow System

To simulate natural optical lighting, every elevated surface casts two simultaneous shadows:
1. **Ambient Radiance Shadow**: Soft, expansive room bounce.
2. **Contact Occlusion Shadow**: Tight, sharp ground contact directly underneath the surface.

```dart
static List<BoxShadow> shadows(double elevation, {required bool dark}) {
  if (elevation <= 0) return const [];
  final ambientAlpha = dark ? 0.38 : 0.08;
  final contactAlpha = dark ? 0.48 : 0.12;

  return [
    BoxShadow(
      color: Colors.black.withValues(alpha: ambientAlpha),
      blurRadius: (elevation * 1.6).clamp(4.0, 32.0),
      offset: Offset(0, (elevation * 0.45).clamp(2.0, 16.0)),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: contactAlpha),
      blurRadius: (elevation * 0.4).clamp(2.0, 8.0),
      offset: Offset(0, (elevation * 0.18).clamp(1.0, 4.0)),
    ),
  ];
}
```

---

## 3. Spacing Scale (4pt Baseline Token System)

```dart
abstract final class Space {
  static const double s1 = 4.0;    // Micro gap (icon to label)
  static const double s2 = 8.0;    // Tight gap (text lines)
  static const double s3 = 12.0;   // Standard intra-card gap
  static const double s4 = 16.0;   // Standard container padding
  static const double s5 = 20.0;   // Section separation
  static const double s6 = 24.0;   // Major group separation
  static const double page = 20.0; // Horizontal viewport margin
}
```

---

## 4. Typography Scale (`AppType`)

* **Display Title**: Playfair Display 600, `28.0` pt, `-0.5` tracking, `1.2` height.
* **Screen Title**: Playfair Display 500, `22.0` pt, `-0.3` tracking, `1.25` height.
* **Section Heading**: DM Sans 700, `16.0` pt, `-0.2` tracking, `1.3` height.
* **Card Title**: DM Sans 500, `15.0` pt, `0.0` tracking, `1.35` height.
* **Body / Reading**: DM Sans 400, `14.0` pt, `0.0` tracking, `1.45` height.
* **Eyebrow / Metadata**: DM Sans 700 (Uppercase), `11.0` pt, `1.2` tracking.
* **Tabular Numbers / Scores**: DM Mono 500, `18.0` to `26.0` pt, `0.0` tracking.

---

## 5. Standard Spatial Component Hierarchy

1. `SpatialCard`: 2.5D container with dual shadows, illuminated rim, and optional glass.
2. `SpatialTactileTile`: Tactile button with instant pointer-down depression (`scale: 0.96`), mass spring rebound, and specular border.
3. `SpatialPerspective`: 3D tilt tracking pointer coordinates via 4x4 matrix transformation.
4. `CapsuleNavBar`: Detached floating frosted navigation capsule with spring-sliding selection pill.
5. `SpatialFloatingActionButton`: Floating contextual orb with breathing glow and radial elevation.
6. `SpatialSectionHeader`: Editorial section header with optional arrow action.
7. `SpatialMetricGauge`: Circular and linear score gauges with smooth spring-driven percentage interpolation.
