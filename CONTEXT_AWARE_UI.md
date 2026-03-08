# Context-Aware UI Updates

## Overview
The UI has been further refined to show **only immediately relevant information**. Panels now appear contextually based on user actions, reducing cognitive load and focusing attention.

## Key Changes

### 1. Building Selection System
**Old Behavior:** All worker buildings shown in a scrollable list  
**New Behavior:** Click a building on the planet to manage it

- Buildings are now **clickable** on the 3D planet view
- Selected buildings **glow brighter** and are **slightly larger**
- Only the **selected building** shows worker assignment UI
- Click the same building again to deselect
- "Back to Colony View" button returns to overview

**Benefits:**
- Focus on one building at a time
- Clear visual feedback on selection
- Reduces information overload
- Direct manipulation of game objects

### 2. Workshop-Gated Crafting
**Old Behavior:** Gear panel always visible (with lock message if no workshop)  
**New Behavior:** Gear panel **only appears** when Workshop building is selected

- Crafting UI hidden until Workshop is clicked on planet
- Makes it clear that gear is tied to the Workshop building
- Reduces UI clutter when not crafting

**Benefits:**
- Clearer connection between building and function
- Less visual noise
- More intuitive workflow

### 3. Manual Build Mode
**Old Behavior:** Build menu always visible  
**New Behavior:** "Enter Build Mode" button shows build menu on demand

- Build menu hidden by default
- Click "Enter Build Mode" to show building selection
- "Exit Build Mode" button to return to normal view
- Building selection deselected when entering build mode

**Benefits:**
- Cleaner default view
- Clear mode separation (manage vs build)
- Prevents accidental building placement

### 4. Buildings Overview Panel
**New Addition:** Shows when no building is selected

- Displays total building count
- Shows workshop status (✓ if built)
- Clear instruction: "👆 Click a building on the planet"
- Guides player on what to do next

## UI Flow Comparison

### Before
```
[Resources]
[Colonists]
[Invader] (if active)
[Buildings List] ← all buildings always shown
[Gear Crafting] ← always shown (locked if no workshop)
[Build Menu] ← always shown
```

### After - Default View
```
[Resources]
[Colonists]
[Invader] (if active)
[Buildings Overview] ← helpful overview
[Enter Build Mode] ← button only
```

### After - Building Selected
```
[Resources]
[Colonists]
[Invader] (if active)
[Manage Building] ← single building details
[Gear Crafting] ← ONLY if workshop selected
[Enter Build Mode]
```

### After - Build Mode Active
```
[Resources]
[Colonists]
[Invader] (if active)
[Build Structures] ← grid of building options
  [Exit Build Mode] ← prominent exit button
```

## Technical Implementation

### Selection State
- `selectedBuilding: { lon, lat } | null` - tracks selected building
- `selectedBuildingData` - derived from buildings array
- Buildings pulse/glow when selected on planet

### Conditional Rendering
```svelte
{#if selectedBuildingData}
  <BuildingsPanel building={selectedBuildingData} />
{:else}
  <BuildingsOverview {buildings} />
{/if}

{#if selectedBuildingData?.buildingType === 7}
  <GearPanel ... />
{/if}

{#if !buildMode}
  <button>Enter Build Mode</button>
{:else}
  <BuildPanel ... />
{/if}
```

### Click Handling
- **Planet surface**: Found colony or place building (depending on mode)
- **Building markers**: Select building for management
- **Click same building**: Deselect

## User Interaction Patterns

### Managing Buildings
1. Look at planet
2. Click a building marker
3. Panel appears with that building's details
4. Adjust workers, upgrade, etc.
5. Click "Back" or different building

### Crafting Gear
1. Click Workshop building on planet
2. Gear panel appears automatically
3. Adjust quantities and craft
4. Click away or "Back" to exit

### Building Structures
1. Click "Enter Build Mode"
2. Browse building grid
3. Select building type
4. Click planet to place
5. Click "Exit Build Mode" when done

## Benefits Summary

✅ **Reduced Cognitive Load**: Only 2-3 panels visible at once  
✅ **Contextual Help**: Clear instructions on what to do  
✅ **Direct Manipulation**: Click what you want to manage  
✅ **Mode Clarity**: Clear separation between manage/build modes  
✅ **Visual Feedback**: Selected items glow on planet  
✅ **Focused Workflow**: One task at a time  
✅ **Cleaner Interface**: No unused panels cluttering the view

## Files Modified

- `App.svelte` - Selection state, conditional rendering
- `PlanetSphere.svelte` - Building click handlers, selection glow
- `PlanetView.svelte` - Pass through selection props
- `BuildingsPanel.svelte` - Single building instead of list
- `BuildPanel.svelte` - Exit button, mode awareness
- `BuildingsOverview.svelte` - **New component**

## Migration Notes

No breaking changes - all features preserved, just accessed differently.

Users will need to:
- Click buildings to manage them (instead of scrolling a list)
- Click "Enter Build Mode" to build (instead of always-visible menu)
- Select Workshop to craft (instead of always-visible but locked panel)
