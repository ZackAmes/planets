# Tutorial & Tips System

## Overview

Added a contextual, progressive tutorial system that guides players seamlessly through the game without being intrusive.

## Features

### 1. 📚 Smart Tutorial Tips

**Context-Aware:**
- Tips appear based on game state and progression
- Only show relevant information at the right time
- Dismissible with persistence (localStorage)
- Smooth slide-in animation

**Tip Types:**
- 💡 **Tutorial** (Blue) - Step-by-step guidance for new players
- 💡 **Tip** (Yellow-green) - Helpful hints and strategies
- ⚠️ **Warning** (Red) - Important alerts about game state

### 2. 🎯 Progressive Tutorial Flow

**Early Game:**
1. **Founding** - "Click anywhere on the planet to found your colony"
2. **First Turn** - "Click 'Collect Resources' to advance time"
3. **First Build** - "Click 'Enter Build Mode' to construct buildings"

**Mid Game:**
4. **Population Cap** - "Upgrade Town Center to increase colonist limit"
5. **Workshop Unlock** - "You can now build a Workshop for gear crafting"
6. **Worker Efficiency** - "Different terrains give bonuses to buildings"

**Advanced:**
7. **Training** - "Assign colonists to Barracks to make them stronger"
8. **Danger Warning** - "High stored resources attract invaders"

**Critical:**
9. **Invader Help** - "Fight with colonists + gear or let Cannons handle it"
10. **Water Shortage** - "Negative water prevents population growth"

### 3. 📖 Quick Tips Tooltip

**In Resources Panel:**
- Toggle button: "Show Tips" / "Hide Tips"
- Explains core mechanics:
  - Resources = Danger
  - Epoch Timer (10 minutes)
  - Water can go negative
  - Defense protects against invaders
  - Terrain matters for bonuses

### 4. 💾 Persistence System

**localStorage Tracking:**
- Dismissed tips saved to `planets_dismissed_tips`
- Tips won't re-appear once dismissed
- Persists across sessions
- Players can progress at their own pace

## Tutorial Tip Examples

### Welcome Tip
```
┌────────────────────────────────┐
│ 💡 Welcome to Your Colony!     │
│ ─────────────────────────── × │
│ Click anywhere on the planet   │
│ to found your colony. Try to   │
│ pick a strategic location with │
│ varied terrain for building    │
│ bonuses.                        │
└────────────────────────────────┘
```

### Danger Warning
```
┌────────────────────────────────┐
│ ⚠️ Danger Rising               │
│ ─────────────────────────── × │
│ Having more stored resources   │
│ increases danger! Build        │
│ Cannons for defense or spend   │
│ resources quickly.             │
└────────────────────────────────┘
```

### Info Tooltip
```
┌────────────────────────────────┐
│ 💡 Quick Tips                  │
│ ──────────────────────────────│
│ • Resources = Danger: High     │
│   stored resources attract     │
│   invaders                     │
│ • Epoch Timer: Resources       │
│   generate over 10 minutes     │
│ • Water: Can go negative if    │
│   population exceeds production│
│ • Defense: Protects against    │
│   invader damage               │
│ • Terrain Matters: Buildings   │
│   get bonuses on certain       │
│   terrain                      │
│ ──────────────────────────────│
│ Click buildings on the planet  │
│ to manage them                 │
└────────────────────────────────┘
```

## Tip Triggers

| Tip ID | Trigger Condition | Priority |
|--------|------------------|----------|
| `founding` | Phase = founding | Highest |
| `first_turn` | actionCount = 0 | High |
| `first_build` | buildings.length = 1 | High |
| `population_cap` | pop >= cap | Medium |
| `workshop_unlock` | TC level 2+ && no workshop | Medium |
| `danger_warning` | threat > 50% | High |
| `invader_help` | invader active | Critical |
| `negative_water` | water < 0 | Critical |
| `worker_efficiency` | 5+ buildings | Low |
| `training` | has barracks | Low |

## Design Philosophy

### Non-Intrusive
✅ Dismissible with one click  
✅ Appears at logical moments  
✅ Never blocks gameplay  
✅ Respects player progress

### Contextual
✅ Shows what matters NOW  
✅ Adapts to game state  
✅ Progressive disclosure  
✅ Just-in-time learning

### Helpful
✅ Explains WHY not just WHAT  
✅ Teaches strategy, not just controls  
✅ Warns about dangers  
✅ Guides without hand-holding

## Implementation Details

### TutorialTip Component
```javascript
// Determines which tip to show
const currentTip = $derived.by(() => {
  // Check game state
  // Return highest priority relevant tip
  // Or null if nothing to show
})
```

### Tip Structure
```javascript
{
  id: 'unique_tip_id',
  title: 'Tip Title',
  message: 'Helpful explanation...',
  type: 'tutorial' | 'tip' | 'warning'
}
```

### Dismissal System
```javascript
// Load from localStorage
const stored = localStorage.getItem('planets_dismissed_tips')
dismissedTips = new Set(JSON.parse(stored))

// Save on dismiss
function handleDismissTip(tipId) {
  dismissedTips.add(tipId)
  localStorage.setItem('planets_dismissed_tips', 
    JSON.stringify([...dismissedTips]))
}
```

## User Experience Flow

### New Player (First Session)

1. **Lands on planet selection** → See "Welcome" tip
2. **Clicks planet** → Tip dismissed, colony founded
3. **Sees UI** → "First Turn" tip appears
4. **Collects resources** → Tip dismissed automatically
5. **Needs to build** → "First Build" tip appears
6. **Enters build mode** → Learns building system
7. **As threats grow** → Danger warnings appear
8. **Population caps** → TC upgrade tip shows

### Experienced Player (Return Visit)

- Previously dismissed tips don't reappear
- Only new contextual tips show (warnings, alerts)
- Can access Quick Tips tooltip anytime
- Seamless experience, no tutorial repetition

## Benefits

### For New Players
✅ **Smooth onboarding** - Learn by doing, not reading walls of text  
✅ **Discover mechanics** - Tips reveal features as they become relevant  
✅ **Avoid mistakes** - Warnings prevent common errors  
✅ **Build confidence** - Progressive learning reduces overwhelm

### For Returning Players
✅ **No repetition** - Dismissed tips stay dismissed  
✅ **Fresh reminders** - Quick tips always available  
✅ **Strategic hints** - Learn advanced tactics  
✅ **Clean interface** - Tips don't clutter the screen

### For Game Design
✅ **Reduced friction** - Players understand mechanics faster  
✅ **Better retention** - Less confusion = more engagement  
✅ **Faster iteration** - Can add tips without tutorial rework  
✅ **Data-driven** - Could track which tips help most (future)

## Future Enhancements

### Possible Additions
- Reset tutorial button in settings
- Tip replay system
- Achievement-based tips
- Video/GIF demonstrations
- Community tips submission
- Difficulty-based tip filtering
- Analytics on tip dismissal rates

### Advanced Features
- Interactive tutorials (step-by-step with UI highlighting)
- Tooltip overlays on UI elements
- Context menu "What's this?" help
- Onboarding checklist
- Progressive mission system

## Accessibility

- **Keyboard accessible** (can dismiss with Esc)
- **Clear visual hierarchy** (icon, title, message)
- **Color-coded by importance** (blue, yellow, red)
- **Readable font sizes** (0.75-0.8rem)
- **High contrast** (dark bg, light text)
- **Animation can be disabled** (future: prefers-reduced-motion)

## Testing Checklist

- [x] Tips appear at correct game states
- [x] Dismissal persists across sessions
- [x] No duplicate tips show
- [x] Tips don't block critical UI
- [x] Animations perform smoothly
- [x] localStorage handles errors gracefully
- [x] Multiple tips don't stack (one at a time)
- [x] Build succeeds without errors

## Conclusion

The tutorial system provides a **seamless, non-intrusive onboarding experience** that:
- Teaches players progressively
- Respects their intelligence
- Adapts to their skill level
- Never gets in the way

Players will appreciate learning the game **through play, not through reading**. The contextual tips guide without hand-holding, warn without nagging, and teach without lecturing.

🎮 **Much more accessible for new players!**
