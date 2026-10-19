# GLITCH//RUN — Google Play Store Listing & Store Assets Specification

**Application Name:** GLITCH//RUN  
**Package Identifier:** `com.antigravity.glitchrun`  
**Category:** Games / Action / Roguelike  
**Content Rating:** Everyone 10+ (Fantasy Violence, Minimal Blood/Gore)  
**Target API:** API Level 36 (Android 16)  
**Network Requirements:** None (100% Offline, Zero Permissions)  

---

## 1. Store Copy

### Short Description (78 / 80 characters)
```
Cyberpunk action roguelite where lethal glitch swarms evolve against your tactics.
```

### Full Description (3,248 / 4,000 characters)
```text
BREACH THE SIMULATION. ADAPT OR DECOMPILE.

GLITCH//RUN is a fast-paced cyberpunk twin-stick action roguelite where enemy swarms do not just attack—they observe, counter, and evolve in direct response to your combat habits.

Enter a corrupt virtual mainframe composed of shifting procedural sectors. Pilot your combat avatar across branching route networks, outmaneuver relentless sentinel programs, scavenge subroutine upgrades, and defeat multi-phase Overlord cores guarding sector exits.

---

KEY FEATURES

• BEHAVIOR-DRIVEN ENEMY LEARNING
Enemies genuinely adapt to how you fight. When you kite from a distance, Chasers develop rapid pursuit thrust and long-range crimson cannons. When you rely heavily on dash evasion, Dashers calculate flanking interception angles and lay static hazard trails. Switch your combat style mid-run to disrupt their adaptations before they reach lethal Tier 3 mutations.

• PROCEDURAL SECTORS & BRANCHING ROUTES
Every sector is dynamically generated with deterministic seed consistency. Navigate topological room graphs featuring high-threat combat arenas, Black Market kiosks, subroutine gift caches, and emergency recovery bays. Choose your path wisely—higher risks offer greater cache yields.

• CONSISTENT COMBAT STAKES & HEALTH EVOLUTION
Major species evolutions double their vitality (2^tier scaling), turning veteran foes into formidable elite threats while maintaining strict fair-play telegraphs and balanced attack budgets.

• TELEGRAPHED OVERLORD BOSS ENCOUNTERS
Face multi-phase mechanical bosses featuring clear visual telegraphs: laser charging sweeps, directional dash trails, rotating bullet curtain barriers, and summons. Master dodge timing with invulnerability phase dashing.

• DEEP SUBROUTINE CUSTOMIZATION
Collect and stack procedural upgrades across each run: kinetic ricochets, explosive fragmentation rounds, dash phase extensions, critical overclocks, and shield regeneration matrices.

• FULL DIRECTOR TELEMETRY DEBRIEF
Inspect post-combat telemetry logs after every run or chamber. Review player mobility metrics, aggression ratings, kiting ratios, and active enemy genome adaptations to refine your build.

• 100% OFFLINE & PRIVACY-RESPECTING
Zero internet permissions required. Zero ad tracking, zero telemetry harvesting, and zero in-app purchases. Your save state and high scores remain stored securely and locally on your device.

• DESIGNED FOR MOBILE PRECISION
Enjoy responsive dual virtual joysticks, full haptic feedback, adjustable UI scale, low-health danger vignettes, and native Android back-key navigation.

---

WILL YOU CRACK THE KERNEL OR BE OVERWRITTEN?
Install GLITCH//RUN and test your reflexes against an evolving digital threat.
```

---

## 2. Store Screenshot Composition Plan

Recommended format: 1920x1080 Landscape (16:9), PNG format.

| Slot | Headline / Overlay Text | Visual Content Focus | Key UI Elements Visible |
| :--- | :--- | :--- | :--- |
| **01** | **EVOLVING ENEMY SWARMS** | Dynamic arena combat showing player dodging Chasers with crimson cannon trails and Dasher hazard nodes. | Health bar, ammo gauge, active wave counter `WAVE 2/4 (SUB 1/2)`. |
| **02** | **PROCEDURAL ROUTE NETWORKS** | Room transition portal display showing branching doors: `BLACK MARKET // DATA TERMINAL` (Amber) and `SUBROUTINE CACHE // FREE REWARD` (Violet). | Minimap/Room label, sector depth display, clear color-coded portals. |
| **03** | **TELEGRAPHED BOSS OVERLORDS** | Overlord Sentinel charging a bright red directional death beam with dashed telegraph line across the arena. | Boss health bar, phase dash trail, invulnerability ghosting fx. |
| **04** | **DATA TERMINAL & SUBROUTINES** | Black Market shop interface selecting between Kinetic Ricochet, Glitch Splitter, and Nanite Armor. | Bit currency counter, upgrade descriptions, stack counters. |
| **05** | **TACTICAL DIRECTOR DEBRIEF** | Terminal debrief screen displaying combat analytics: Mobility Rating, Kiting Index, and Evolved Species Traits. | Telemetry graph, species mutation cards, run seed number. |

---

## 3. Store Graphic Asset Specifications

| Asset | Dimensions | Format | Design Direction |
| :--- | :--- | :--- | :--- |
| **App Icon** | 512 x 512 px | 32-bit PNG | Neon cyan chevron runner emblem with corrupted magenta scanline slice on dark navy grid. Matches `res://assets/icon/android_icon_192.png`. |
| **Feature Graphic** | 1024 x 500 px | 24-bit PNG / JPEG | Dark cyberpunk grid background with glowing neon title logo `GLITCH//RUN`, silhouette of the phase runner, and glowing crimson enemy eyes. |
| **Promo Video** | 16:9 (1080p, 30-60s) | MP4 | 0–5s: Fast dash gameplay hook; 5–15s: Enemy evolution alert overlay; 15–25s: Boss beam dodge; 25–30s: Logo reveal + "Offline Roguelite". |

---

## 4. Google Play Release Checklist (2026 Policy Compliance)

- [x] **Target SDK:** API 36 (Android 16) configured in `export_presets.cfg`.
- [x] **Version Code:** Incremented to `2` (`1.1.0`).
- [x] **Permissions:** Only `VIBRATE` requested. `INTERNET` and storage access completely omitted.
- [x] **Data Safety Form:**
  - Data Collected: **None**.
  - Data Shared: **None**.
  - Security Practices: Local on-device storage only (`user://save_data.json`).
- [x] **Closed Testing Requirements:**
  - Minimum 12 opted-in testers required for personal developer accounts.
  - Active testing period for 14 continuous days prior to production access application.
- [x] **Deterministic Test Coverage:** 51 headless test scenarios verified passing with Godot 4.7.2.
