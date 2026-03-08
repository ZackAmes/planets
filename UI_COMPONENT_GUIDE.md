# UI Component Guide

## Panel Overview

The colony UI is now organized into 6 distinct panels, each handling a specific aspect of gameplay.

---

## 1. Resources Panel (Always Open)
**Purpose**: Monitor your colony's resources and production  
**Color**: Teal (#7a9)

**Sections:**
- **Resource Grid** (2x3)
  - Water (blue) - with net rate (can go negative!)
  - Iron (gray) - production rate
  - Defense (green) - production rate
  - Uranium (purple) - production rate  
  - Population / Cap - with TC level
  
- **Epoch Timer**
  - Visual progress bar (fills over 10 minutes)
  - Countdown display (changes to "READY" when full)
  
- **Collect Button**
  - Primary action button
  - Advances the game by one epoch
  
- **Threat Gauge** (when threat > 0)
  - Bar fills with color: green → yellow → red
  - Shows threat % and attack probability

---

## 2. Colonists & TC Panel (Always Open)
**Purpose**: Manage your population and upgrade Town Center  
**Color**: Teal (#7a9)

**Sections:**
- **Colonist Stats** (3 columns)
  - Assigned: Workers in buildings
  - Free: Available colonists  
  - Avg Strength: Combat power of free colonists
  
- **Town Center Upgrade**
  - Shows current level → next level
  - Cost breakdown (iron + uranium)
  - Disabled if max level (5) or insufficient resources

---

## 3. Buildings & Workers Panel (Always Open)
**Purpose**: Assign workers and upgrade production buildings  
**Color**: Teal (#7a9)

**Features:**
- **Building Cards** (one per building)
  - Building name (color-coded by type)
  - Level indicator
  - Location coordinates
  - Output rate display
  - Worker assignment controls (+/− buttons)
  - Upgrade button (when affordable)
  
- **Special States**
  - Busy buildings show countdown timer
  - Barracks show "Training" when active
  - Output rates calculated automatically

---

## 4. Gear Crafting Panel (Collapsed by Default)
**Purpose**: Craft weapons and armor for combat  
**Color**: Orange (#ff9933)

**Sections:**
- **Inventory Display**
  - Current weapons count
  - Current armor count
  
- **Crafting Controls**
  - Weapons: 20 iron each, +5 combat power
  - Armor: 30 iron each, +3 combat power
  - +/− buttons to select quantities
  - Total cost display
  
- **Workshop Lock**
  - Shows requirement message if no Workshop
  - Unlocks at TC level 2

---

## 5. Invader Panel (Only Shows During Attacks)
**Purpose**: Defend your colony from invaders  
**Color**: Red (#ff4444) with pulsing danger animation

**Sections:**
- **Invader Stats**
  - Strength: Total invader power
  - Drain: Defense lost per epoch
  - Cannon: Damage dealt by your cannons
  
- **Defense Warning**
  - Shows epochs until defense depleted
  - Turns red when critical (≤2 epochs)
  - Shows "safe" message if cannons cover all damage
  
- **Combat Setup**
  - Colonists: Select how many to send (shows avg strength)
  - Weapons: Select equipment to use
  - Armor: Select equipment to use
  
- **Combat Preview**
  - Shows your power vs invader strength
  - Win/Lose indicator
  - Estimated casualties
  - ±25% variance note
  
- **Send Fighters Button**
  - Executes the combat action

---

## 6. Build Structures Panel (Always Open)
**Purpose**: Construct new buildings and found colonies  
**Color**: Teal (#7a9) or Blue (#8ecfff) during founding

**Founding Phase:**
- Location selector prompt
- Terrain type display
- Unbuildable warning for ocean tiles
- "Settle Here" confirmation button

**Building Phase:**
- **Building Grid** (2 columns)
  - 8 building types (unlocked by TC level)
  - Color-coded by function
  - Shows cost (iron/water/uranium)
  - Shows worker capacity or special feature
  - Hover for full description
  - Affordable buildings highlighted
  
- **Placement Mode** (after selecting building)
  - Shows building name being placed
  - Cancel button (✕)
  - Location prompt: "Click planet to choose site"
  
- **Placement Confirmation** (after clicking planet)
  - Location coordinates
  - Terrain type badge
  - Terrain bonus percentage (for production buildings)
  - Output preview (if applicable)
  - Total cost display
  - "Confirm Build" or error message

---

## Visual Design Elements

### Color Coding
- **Teal (#7a9)**: Standard panels
- **Orange (#ff9933)**: Gear crafting
- **Red (#ff4444)**: Danger/combat
- **Blue (#8ecfff)**: Colony founding
- **Purple (#bb44ff)**: Victory/uranium
- **Gray (#556)**: Secondary info

### Interactive Elements
- **+/− Buttons**: Adjust quantities
- **Panel Headers**: Click to expand/collapse
- **Hover Effects**: All buttons darken on hover
- **Disabled States**: 40% opacity + not-allowed cursor
- **Progress Bars**: Smooth filling animations

### Typography
- **Monospace font** throughout
- **UPPERCASE** for headings
- **Letter spacing** for titles
- **Tabular numbers** for countdowns
- **Color-coded values** for different resources

---

## Interaction Flow

### Normal Turn
1. Check **Resources** → see what you have
2. Check **Buildings** → adjust workers if needed
3. Click **Collect** → advance epoch
4. Check **Colonists** → see if you can upgrade TC
5. Expand **Build** → place new structures

### Combat Turn
1. **Invader Panel** appears automatically
2. Check defense drain vs cannon coverage
3. Select colonists + equipment
4. Preview win/loss
5. Send fighters or wait for next epoch

### Building Flow
1. Open **Build Structures** panel
2. Hover buildings to read descriptions
3. Click building type
4. Click planet surface for placement
5. Review terrain bonus
6. Confirm or cancel

---

## Tips for Players

- Keep **Resources**, **Colonists**, and **Buildings** panels open
- Collapse **Gear** panel until you need to craft
- **Invader** panel auto-appears when needed
- Watch the **threat gauge** to anticipate attacks
- Use **terrain bonuses** for optimal building placement
