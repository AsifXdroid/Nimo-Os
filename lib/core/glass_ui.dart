/// LIVING GLASS — Nimo's modern glass and layered interface system.
///
/// D-052 NOTE: this kit is RETAINED for the screens that still
/// build on it, but its palette is re-tinted to Green & Black
/// (near-black fills, white hairlines, the one signal-green
/// glow) so unconverted surfaces stay coherent with the new
/// foundation. New work uses the theme + neo_ui kit, not glass.
///
/// Material levels:
///   1. Atmosphere: ambient deep background with organic radial illumination.
///   2. Primary Glass: important panels, cards, and floating navigation.
///   3. Secondary Glass: grouped content, controls, and chips.
///   4. Floating Glass: overlays, sheets, formatting bar, and dialogs.
library;

import 'dart:ui';

import 'package:flutter/material.dart';


/// Depth tiers in the Living Glass material hierarchy.
enum GlassTier { atmosphere, primary, secondary, floating, recessed } // retained for API compatibility; the glass widgets that consumed it were removed in audit Step 8

/// Centralized glass tokens for blur, opacity, borders, and ambient glow.
abstract final class GlassTokens {
  // Blur sigmas
  static const double blurSubtle = 8.0;
  static const double blurStandard = 14.0;
  static const double blurDense = 22.0;

  // Dark palette glass fills (D-052: the #101010 family)
  static const Color darkAtmosphere = Color(0xFF0A0A0A);
  static const Color darkGlassPrimary = Color(0xBD191919);
  static const Color darkGlassSecondary = Color(0x94141414);
  static const Color darkGlassFloating = Color(0xD61E1E1E);
  static const Color darkGlassRecessed = Color(0x8A050505);

  // Light palette glass fills (D-052: the soft green-paper set)
  static const Color lightAtmosphere = Color(0xFFE9EFEB);
  static const Color lightGlassPrimary = Color(0xD6FFFFFF);
  static const Color lightGlassSecondary = Color(0xACF4F7F4);
  static const Color lightGlassFloating = Color(0xF0FFFFFF);
  static const Color lightGlassRecessed = Color(0x94DCE5DE);

  // Rim highlights (light refraction along top edge)
  static const Color darkRimHighlight = Color(0x2EFFFFFF);
  static const Color lightRimHighlight = Color(0x6EFFFFFF);

  // Border outlines
  static const Color darkBorder = Color(0x24FFFFFF);
  static const Color darkBorderSubtle = Color(0x14FFFFFF);
  static const Color lightBorder = Color(0x38276C57);
  static const Color lightBorderSubtle = Color(0x24000000);

  // Atmospheric glow colors (D-052: the one green, no plum)
  static const Color darkGlowMint = Color(0x1F1ED760);
  static const Color darkGlowForest = Color(0x3314301D);
  static const Color darkGlowPlum = Color(0x141ED760);

  static const Color lightGlowTeal = Color(0x1A276C57);
  static const Color lightGlowSun = Color(0x28FFF8E7);
  static const Color lightGlowPlum = Color(0x0F276C57);

  // D-053 Premium Charcoal (the Today redesign's surface
  // system, owner brief 2026-11-05). Dark values are the
  // brief's set; fills carry their alpha so surfaces read as
  // translucent charcoal over the page base. Text values are
  // for use ON these surfaces. The light theme keeps its
  // D-052 soft surfaces — charcoal is a dark-mode system.
  static const Color darkCharcoal = Color(0xE6181818);
  static const Color darkCharcoalSolid = Color(0xFF181818);
  static const Color darkCharcoalRaised = Color(0xEB202020);
  static const Color darkCharcoalElevated = Color(0xFF262626);
  static const Color darkCharcoalBorder = Color(0xFF363636);
  static const Color darkOnCharcoal = Color(0xFFF5F5F5);
  static const Color darkOnCharcoalSecondary = Color(0xFFA7A7A7);
  static const Color darkOnCharcoalMuted = Color(0xFF8A8A8A);
}

