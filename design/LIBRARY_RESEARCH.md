# UI LIBRARY & ARCHITECTURAL RESEARCH
Generated: November 4, 2026
Author: Design Systems & Flutter Architecture Specialist

---

## 1. Candidate Library Evaluation

### A. Component & Layout Systems
| Candidate | URL | License | Flutter/Dart Compatibility | Suitability for Nimo |
|---|---|---|---|---|
| `shadcn_flutter` | https://pub.dev/packages/shadcn_flutter | MIT | Requires specific styling overrides; high dependency footprint | **Not recommended**: Introduces an entire second theme system that overrides standard Flutter `ThemeData` and can conflict with offline rendering and existing tests. |
| **Native Flutter Primitives (Selected)** | `flutter/material.dart`, `dart:ui` | BSD-3-Clause (Core) | Official, 100% compatible | **Recommended & Selected**: Built with `CustomPainter`, `BackdropFilter`, `Matrix4`, and `ThemeExtension`. Zero bloat, predictable 120fps GPU performance on mobile and desktop. |

### B. Motion & Interaction
| Candidate | URL | License | Flutter/Dart Compatibility | Suitability for Nimo |
|---|---|---|---|---|
| `flutter_animate` | https://pub.dev/packages/flutter_animate | MIT | Flutter 3+ compatible | Good for declarative cascades, but adds extra abstraction. |
| `animations` | https://pub.dev/packages/animations | BSD-3-Clause | Official Flutter team | Good for OpenContainer / SharedAxis transitions. |
| **Native Flutter Physics Springs (`Motion.spring`, `SpatialPerspective`)** | Core Flutter `AnimationController`, `CurvedAnimation` | BSD-3-Clause | Native | **Selected**: In `lib/core/motion.dart` and `lib/core/spatial_ui.dart`, custom cubic spring curves (`Motion.easeOutExpo`, `Motion.spring`) provide Emil Kowalski-grade 60/120fps velocity-aware motion without package dependencies. |

### C. Glass & Spatial Materials
| Candidate | URL | License | Notes / GPU Performance | Suitability for Nimo |
|---|---|---|---|---|
| `glass_mt` | https://pub.dev/packages/glass_mt | MIT | Uses experimental fragment shaders (`.frag`); known to drop frames or fail on older Vulkan/OpenGL ES devices. | **Rejected**: GPU risk on mid-range Android devices. |
| **Native `SpatialCard` & `GlassAtmosphere`** | Core Flutter (`BackdropFilter` + `ImageFilter.blur`) | BSD-3-Clause | Optimized GPU blur passes, selective rendering, dark mode fallbacks. | **Selected**: Custom implementation in `lib/core/spatial_ui.dart`. Uses uniform `Border.all` specular rim and calibrated dual shadows. |

### D. Typography
| Font Family | Format / Delivery | License | Suitability for Nimo |
|---|---|---|---|
| **Playfair Display** (500, 600, 500 Italic) | Bundled TTF in `assets/fonts/` | SIL Open Font License 1.1 | **Selected**: Editorial serif headlines with natural optical rhythm. Bundled locally for 100% offline usage. |
| **DM Sans** (400, 500, 700) | Bundled TTF in `assets/fonts/` | SIL Open Font License 1.1 | **Selected**: Highly legible modern sans-serif for UI labels, body text, and interactive tiles. |
| **DM Mono** (400, 500) | Bundled TTF in `assets/fonts/` | SIL Open Font License 1.1 | **Selected**: Tabular numbers for dates, streak counts, and scores. |

### E. Iconography
| System | Provider | License | Suitability for Nimo |
|---|---|---|---|
| `lucide_icons_flutter` | pub.dev | ISC | Clean icon family, but adds another external package. |
| **Material Icons (Outlined & Rounded)** | Flutter SDK (`Icons.*`) | Apache 2.0 | **Selected**: 100% bundled with Flutter SDK (`uses-material-design: true`). Using consistent `_outlined` variants for clean architectural aesthetic without package bloat. |

---

## 2. Decision Summary

To ensure Nimo remains **100% offline-first**, blisteringly fast on mobile devices, and maintainable without dependency hell, we rely on **native high-craft Flutter engineering**:
1. All fonts are bundled locally in `assets/fonts/`.
2. Spatial surfaces and dual-shadow physics are implemented via custom `SpatialCard` and `SpatialTactileTile`.
3. Motion is governed by Emil Kowalski design engineering principles using native `AnimationController` and physics curves.
4. No heavy third-party UI framework is injected, preserving all existing business logic and 647 unit tests.
