# Blueprint - AI Development Guide

> **Skill Reference:** Use the `balatro-mod-dev` skill for:
> - Game source paths and search recipes
> - Lovely patch syntax (`patterns/lovely-patches.md`)
> - SMODS API patterns (`patterns/smods-api.md`)
> - Mobile compatibility (`patterns/mobile-compat.md`)
> - UI architecture (`patterns/ui-system.md`)
> - Global variables (`reference/globals.md`)

---

## 1. Big Picture

Blueprint dynamically changes the texture display of **Blueprint** and **Brainstorm** joker cards to visually match the joker they are copying. Blueprint shows a blue color-shifted version; Brainstorm shows an edge-detected outline with a tiled background pattern.

**Mod Type:** Standalone visual enhancement
**Dependencies:** Steamodded (for SMODS.DrawStep, config_tab, Atlas)

---

## 2. Repository Structure

```
Blueprint/
├── blueprint.lua         # Main entry point
├── smods.lua             # SMODS config & UI settings, DrawStep registration
├── smods.json            # SMODS manifest (id, version, deps)
├── config.lua            # Default configuration values
├── lovely.toml           # Lovely injector patch configuration
│
├── core/
│   ├── core.lua          # Core sprite/texture manipulation logic (MAIN FILE)
│   └── settings.lua      # Settings management
│
├── internal/
│   ├── init.lua          # Initialization & module loading
│   ├── assets.lua        # Asset loading & shader initialization
│   ├── config.lua        # Config loading/saving
│   └── localization.lua  # Localization support
│
├── assets/
│   ├── shaders/
│   │   ├── blueprint.fs  # Blueprint shader (color transformation)
│   │   └── brainstorm.fs # Brainstorm shader (edge detection)
│   ├── 1x/               # 1x resolution assets
│   └── 2x/               # 2x resolution assets
│
├── localization/
│   ├── en-us.lua         # English strings
│   └── zh_CN.lua         # Simplified Chinese strings
│
└── libs/
    └── nativefs.lua      # Native filesystem access library
```

### Key Files

| File | Purpose | Key Exports/Functions |
|------|---------|----------------------|
| `blueprint.lua` | Entry point, mod initialization | Loads internal/init.lua |
| `smods.lua` | SMODS manifest, DrawStep, config UI | `SMODS.DrawStep`, `config_tab` |
| `core/core.lua` | All sprite copying and manipulation | `blueprint_sprite()`, `brainstorm_sprite()`, `restore_sprite()` |
| `core/settings.lua` | Settings management | `Blueprint.SETTINGS` |

---

## 3. Core Behavior

### 3.1 Sprite Copying System

The mod intercepts joker drawing and replaces Blueprint/Brainstorm visuals with a processed copy of the target joker's sprite.

**Blueprint**: Uses `blueprint.fs` shader for blue color transformation
**Brainstorm**: Uses `brainstorm.fs` shader for Canny edge detection with tiled background

### 3.2 State Variables

```lua
-- Card-level state (stored on card object)
card.blueprint_sprite_copy  -- Cached original sprite
card.blueprint_copy_key     -- Cached copy key (joker ID)
card.blueprint_T            -- Cached original dimensions {h, w}
card.blueprint_scale_y      -- Cached original scale.y
```

### 3.3 Key Functions (core/core.lua)

| Function | Purpose | Location |
|----------|---------|----------|
| `align_card(self, card, restore)` | Unified dimension alignment for both cards | `core/core.lua` |
| `dimensions_match(self, card)` | Check if dimensions/scale match (optimization) | `core/core.lua` |
| `get_floating_offset(card)` | Calculate floating sprite offset | `core/core.lua` |
| `get_aspect_scale(self, card)` | Calculate aspect ratio scale for h_scale | `core/core.lua` |
| `setup_center_sprite(self, card, atlas, pos)` | Create and configure center sprite | `core/core.lua` |
| `setup_floating_sprite(self, card, atlas)` | Create floating sprite (Blueprint only) | `core/core.lua` |
| `prepare_sprite_update(self, card)` | Cache, align, and cleanup logic | `core/core.lua` |
| `blueprint_sprite(self, card)` | Apply blueprint effect to card | `core/core.lua` |
| `brainstorm_sprite(self, card)` | Apply brainstorm effect to card | `core/core.lua` |
| `restore_sprite(card)` | Restore original sprite | `core/core.lua` |

### 3.4 Hooks / Patches

| Hook/Patch | Target | Purpose |
|------------|--------|---------|
| `SMODS.DrawStep` | Card rendering | Draws copied sprite with shader effects |
| `lovely.toml` patches | Various game functions | Inject sprite copying logic |

---

## 4. Constraints & Gotchas

### 4.1 Critical Rules

- **DO NOT:** Cache original sprite AFTER modifications - must cache BEFORE
- **ALWAYS:** Use unified field names (`blueprint_T`, `blueprint_sprite_copy`) for both cards
- **NEVER:** Skip dimension check in early return - causes sticker position mismatch

### 4.2 Platform Notes

| Platform | Consideration |
|----------|---------------|
| Desktop | Standard shaders work |
| Mobile | Check `patterns/mobile-compat.md` for touch handling |

### 4.3 Known Issues

| Issue | Status | Workaround |
|-------|--------|------------|
| Brainstorm stretching on first selection after height change | Fixed | Cache before modifications, restore from unified `blueprint_T` |
| Wee Joker pattern double-scaling | Fixed | Use aspect ratio change instead of raw height ratio |
| Blueprint not updating when switching joker sizes | Fixed | Added dimension check to early return |
| Sticker position/size mismatch | Fixed | Check dimensions BEFORE calling `align_card` |

---

## 5. Lessons Learned

### 5.1 What Didn't Work

1. **Caching sprite AFTER align_card**: Cached modified dimensions, causing restore failures
2. **Raw height ratio for h_scale**: Resulted in double-scaling (0.7 x 0.7 = 0.49x)
3. **Early return without dimension check**: Caused sticker position mismatch

### 5.2 Key Insights

- Both Blueprint and Brainstorm should have **identical scale/shape behavior** - only the shader effect differs
- Aspect ratio change (`new_aspect / original_aspect`) is the correct h_scale calculation
- Dimension caching must happen BEFORE any modifications

---

## 6. Development

### 6.1 Scripts

```bash
./scripts/sync_to_mods.sh        # Sync to game
./scripts/sync_to_mods.sh --watch # Auto-sync
./scripts/create_release.sh [ver] # Create release
```

### 6.2 Testing

| Scenario | Steps | Expected |
|----------|-------|----------|
| Blueprint copying regular joker | Get Blueprint + any joker | Blue-shifted sprite appears |
| Blueprint copying Wee Joker | Get Blueprint + Wee Joker | Scaled down, pattern NOT double-scaled |
| Brainstorm copying tall joker | Get Brainstorm + Cavendish | Height adjusts, stickers aligned |
| Switch between joker sizes | Change copied joker | Immediate update, no stretching |

### 6.3 Debugging

- Lovely logs: `~/Library/Application Support/Balatro/Mods/lovely/log/` (macOS)
- Windows: `%APPDATA%/Balatro/Mods/lovely/log/`
- Use temp logs: `pcall(print, "[Debug] " .. tostring(var))`

---

## 7. Recent Changes

| Version | Change |
|---------|--------|
| v3.3 | Unified alignment functions, fixed Brainstorm stretching, Wee Joker pattern scaling |
| v3.2 | Allow Brainstorm to scale to same height as copied joker (PR #16) |

---

## 8. Open Tasks

- [ ] Test mobile compatibility
- [ ] Consider adding more shader options
