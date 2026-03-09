<script>
  let {
    phase,
    planet,
    resources,
    buildings = [],
    threat,
    invaderActive = false,
    hasWorkshop = false,
    tcLevel = 1,
    populationAtCap = false,
    onDismiss,
  } = $props()

  // Tutorial progression tracking
  let dismissedTips = $state(new Set())
  let currentTipIndex = $state(0)

  function dismissTip(tipId) {
    dismissedTips.add(tipId)
    if (onDismiss) {
      onDismiss(tipId)
    }
  }

  // Get all relevant tips based on game state
  const allRelevantTips = $derived.by(() => {
    const tips = []
    
    // Phase-based tips
    if (phase === 'founding' && !dismissedTips.has('founding')) {
      tips.push({
        id: 'founding',
        title: 'Welcome to Your Colony!',
        message: 'Click anywhere on the planet to found your colony. Try to pick a strategic location with varied terrain for different building bonuses.',
        type: 'tutorial'
      })
    }

    // Early game tips
    if (planet?.actionCount === 0 && !dismissedTips.has('first_turn')) {
      tips.push({
        id: 'first_turn',
        title: 'Getting Started',
        message: 'Click "Collect Resources" to advance time. Each epoch lasts 2 minutes. Resources only generate from buildings with assigned workers!',
        type: 'tutorial'
      })
    }

    if (buildings.length === 1 && !dismissedTips.has('first_build')) {
      tips.push({
        id: 'first_build',
        title: 'Build Your Colony',
        message: 'Click "Enter Build Mode" to construct buildings. Water Wells and Iron Mines generate resources when workers are assigned to them. Build a House to add colonists!',
        type: 'tutorial'
      })
    }

    // CRITICAL: Worker assignment education
    if (buildings.length >= 2 && !dismissedTips.has('assign_workers')) {
      const workerBuildings = buildings.filter(b => b.maxWorkers > 0)
      const hasUnassigned = workerBuildings.some(b => b.workers === 0)
      if (hasUnassigned) {
        tips.push({
          id: 'assign_workers',
          title: '⚠️ Assign Workers!',
          message: 'Buildings don\'t produce anything without workers! Click a building on the planet, then use +/- buttons to assign colonists. Buildings need workers to generate resources.',
          type: 'warning'
        })
      }
    }

    // No water production warning
    if (buildings.length > 1 && !dismissedTips.has('no_water_production')) {
      const waterWells = buildings.filter(b => b.buildingType === 1)
      const hasWaterWell = waterWells.length > 0
      const waterProducing = waterWells.some(b => b.workers > 0)
      if (hasWaterWell && !waterProducing) {
        tips.push({
          id: 'no_water_production',
          title: '💧 No Water Production!',
          message: 'Your Water Wells have no workers assigned! Click the Water Well on the planet and assign colonists, or your colony will die of thirst.',
          type: 'warning'
        })
      }
    }

    // Contextual tips based on state
    if (populationAtCap && !dismissedTips.has('population_cap')) {
      tips.push({
        id: 'population_cap',
        title: 'Population Cap Reached',
        message: `Upgrade your Town Center to increase the colonist limit beyond ${tcLevel * 10}. Higher TC levels also unlock advanced buildings.`,
        type: 'tip'
      })
    }

    if (!hasWorkshop && tcLevel >= 2 && !dismissedTips.has('workshop_unlock')) {
      tips.push({
        id: 'workshop_unlock',
        title: 'Workshop Available',
        message: 'You can now build a Workshop! It provides a passive defense bonus to help protect your colony.',
        type: 'tip'
      })
    }

    if (threat > 50 && !invaderActive && !dismissedTips.has('danger_warning')) {
      tips.push({
        id: 'danger_warning',
        title: '⚠️ Danger Rising',
        message: 'Invaders will arrive soon! Build Cannons and stockpile defense resources. When they arrive, send colonists to fight or let cannons wear them down.',
        type: 'warning'
      })
    }

    if (invaderActive && !dismissedTips.has('invader_help')) {
      tips.push({
        id: 'invader_help',
        title: 'Under Attack!',
        message: 'Invaders attack periodically! Your defense absorbs some damage each attack. Fight them off with unassigned colonists, or let Cannons wear down their strength over time.',
        type: 'warning'
      })
    }

    if ((resources?.water ?? 0) < 0 && !dismissedTips.has('negative_water')) {
      tips.push({
        id: 'negative_water',
        title: 'Water Shortage',
        message: 'Your water is negative! Build more Water Wells or reduce population. Negative water prevents new colonists from spawning.',
        type: 'warning'
      })
    }

    // Advanced tips
    if (buildings.length >= 5 && !dismissedTips.has('worker_efficiency')) {
      tips.push({
        id: 'worker_efficiency',
        title: 'Pro Tip: Terrain Bonuses',
        message: 'Different terrains give bonuses: Mountains are great for mines, Beaches for water wells. Check the bonus when placing buildings!',
        type: 'tip'
      })
    }

    if (buildings.some(b => b.buildingType === 4) && !dismissedTips.has('training')) {
      tips.push({
        id: 'training',
        title: 'Training Colonists',
        message: 'Assign colonists to Barracks to train them. Trained colonists are stronger fighters with better survival rates in combat.',
        type: 'tip'
      })
    }

    // Population growth explanation
    if (buildings.some(b => b.buildingType === 3) && !dismissedTips.has('houses_only')) {
      tips.push({
        id: 'houses_only',
        title: 'Population Growth',
        message: 'Population only grows by building Houses! Each House instantly spawns one colonist. There is no natural population growth.',
        type: 'tip'
      })
    }

    return tips
  })

  // Current tip to display
  const currentTip = $derived.by(() => {
    // Phase-based tips
    if (phase === 'founding' && !dismissedTips.has('founding')) {
      return {
        id: 'founding',
        title: 'Welcome to Your Colony!',
        message: 'Click anywhere on the planet to found your colony. Try to pick a strategic location with varied terrain for different building bonuses.',
        type: 'tutorial'
      }
    }

    // Early game tips
    if (planet?.actionCount === 0 && !dismissedTips.has('first_turn')) {
      return {
        id: 'first_turn',
        title: 'Getting Started',
        message: 'Click "Collect Resources" to advance time. Each epoch lasts 2 minutes. Resources only generate from buildings with assigned workers!',
        type: 'tutorial'
      }
    }

    if (buildings.length === 1 && !dismissedTips.has('first_build')) {
      return {
        id: 'first_build',
        title: 'Build Your Colony',
        message: 'Click "Enter Build Mode" to construct buildings. Water Wells and Iron Mines generate resources when workers are assigned to them. Build a House to add colonists!',
        type: 'tutorial'
      }
    }

    // CRITICAL: Worker assignment education
    if (buildings.length >= 2 && !dismissedTips.has('assign_workers')) {
      const workerBuildings = buildings.filter(b => b.maxWorkers > 0)
      const hasUnassigned = workerBuildings.some(b => b.workers === 0)
      if (hasUnassigned) {
        return {
          id: 'assign_workers',
          title: '⚠️ Assign Workers!',
          message: 'Buildings don\'t produce anything without workers! Click a building on the planet, then use +/- buttons to assign colonists. Buildings need workers to generate resources.',
          type: 'warning'
        }
      }
    }

    // No water production warning
    if (buildings.length > 1 && !dismissedTips.has('no_water_production')) {
      const waterWells = buildings.filter(b => b.buildingType === 1)
      const hasWaterWell = waterWells.length > 0
      const waterProducing = waterWells.some(b => b.workers > 0)
      if (hasWaterWell && !waterProducing) {
        return {
          id: 'no_water_production',
          title: '💧 No Water Production!',
          message: 'Your Water Wells have no workers assigned! Click the Water Well on the planet and assign colonists, or your colony will die of thirst.',
          type: 'warning'
        }
      }
    }

    // Contextual tips based on state
    if (populationAtCap && !dismissedTips.has('population_cap')) {
      return {
        id: 'population_cap',
        title: 'Population Cap Reached',
        message: `Upgrade your Town Center to increase the colonist limit beyond ${tcLevel * 10}. Higher TC levels also unlock advanced buildings.`,
        type: 'tip'
      }
    }

    if (!hasWorkshop && tcLevel >= 2 && !dismissedTips.has('workshop_unlock')) {
      return {
        id: 'workshop_unlock',
        title: 'Workshop Available',
        message: 'You can now build a Workshop! It provides a passive defense bonus to help protect your colony.',
        type: 'tip'
      }
    }

    if (threat > 50 && !invaderActive && !dismissedTips.has('danger_warning')) {
      return {
        id: 'danger_warning',
        title: '⚠️ Danger Rising',
        message: 'Invaders will arrive soon! Build Cannons and stockpile defense resources. When they arrive, send colonists to fight or let cannons wear them down.',
        type: 'warning'
      }
    }

    if (invaderActive && !dismissedTips.has('invader_help')) {
      return {
        id: 'invader_help',
        title: 'Under Attack!',
        message: 'Invaders attack periodically! Your defense absorbs some damage each attack. Fight them off with unassigned colonists, or let Cannons wear down their strength over time.',
        type: 'warning'
      }
    }

    if ((resources?.water ?? 0) < 0 && !dismissedTips.has('negative_water')) {
      return {
        id: 'negative_water',
        title: 'Water Shortage',
        message: 'Your water is negative! Build more Water Wells or reduce population. Negative water prevents new colonists from spawning.',
        type: 'warning'
      }
    }

    // Advanced tips
    if (buildings.length >= 5 && !dismissedTips.has('worker_efficiency')) {
      return {
        id: 'worker_efficiency',
        title: 'Pro Tip: Terrain Bonuses',
        message: 'Different terrains give bonuses: Mountains are great for mines, Beaches for water wells. Check the bonus when placing buildings!',
        type: 'tip'
      }
    }

    if (buildings.some(b => b.buildingType === 4) && !dismissedTips.has('training')) {
      return {
        id: 'training',
        title: 'Training Colonists',
        message: 'Assign colonists to Barracks to train them. Trained colonists are stronger fighters with better survival rates in combat.',
        type: 'tip'
      }
    }

    // Population growth explanation
    if (buildings.some(b => b.buildingType === 3) && !dismissedTips.has('houses_only')) {
      return {
        id: 'houses_only',
        title: 'Population Growth',
        message: 'Population only grows by building Houses! Each House instantly spawns one colonist. There is no natural population growth.',
        type: 'tip'
      }
    }

    if (allRelevantTips.length === 0) return null
    
    // Clamp index to valid range
    if (currentTipIndex >= allRelevantTips.length) {
      currentTipIndex = 0
    }
    
    return allRelevantTips[currentTipIndex]
  })

  function nextTip() {
    if (allRelevantTips.length > 0) {
      currentTipIndex = (currentTipIndex + 1) % allRelevantTips.length
    }
  }

  function prevTip() {
    if (allRelevantTips.length > 0) {
      currentTipIndex = (currentTipIndex - 1 + allRelevantTips.length) % allRelevantTips.length
    }
  }

  const tipIcon = $derived({
    tutorial: '💡',
    tip: '💡',
    warning: '⚠️'
  }[currentTip?.type ?? 'tip'])

  const tipColor = $derived({
    tutorial: '#6ab4ff',
    tip: '#88aa44',
    warning: '#ee5544'
  }[currentTip?.type ?? 'tip'])
</script>

{#if currentTip}
  <div class="tip-container" style="--tip-color:{tipColor}">
    <div class="tip-header">
      <span class="tip-icon">{tipIcon}</span>
      <span class="tip-title">{currentTip.title}</span>
      <button class="tip-dismiss" onclick={() => dismissTip(currentTip.id)}>×</button>
    </div>
    <p class="tip-message">{currentTip.message}</p>
    {#if allRelevantTips.length > 1}
      <div class="tip-nav">
        <button class="tip-nav-btn" onclick={prevTip}>←</button>
        <span class="tip-counter">{currentTipIndex + 1} / {allRelevantTips.length}</span>
        <button class="tip-nav-btn" onclick={nextTip}>→</button>
      </div>
    {/if}
  </div>
{/if}

<style>
  .tip-container {
    background: rgba(5, 5, 20, 0.95);
    border: 2px solid var(--tip-color);
    border-radius: 8px;
    padding: 0.75rem;
    font-family: monospace;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.4);
    animation: slideIn 0.3s ease-out;
  }

  @keyframes slideIn {
    from {
      opacity: 0;
      transform: translateY(-10px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  .tip-header {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    margin-bottom: 0.5rem;
  }

  .tip-icon {
    font-size: 1.2rem;
    line-height: 1;
  }

  .tip-title {
    flex: 1;
    font-size: 0.8rem;
    color: var(--tip-color);
    font-weight: bold;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .tip-dismiss {
    background: none;
    border: none;
    color: #667;
    font-size: 1.2rem;
    line-height: 1;
    cursor: pointer;
    padding: 0;
    width: 20px;
    height: 20px;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: color 0.15s;
  }

  .tip-dismiss:hover {
    color: #e44;
  }

  .tip-message {
    margin: 0;
    font-size: 0.75rem;
    color: #aac;
    line-height: 1.5;
  }

  .tip-nav {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 0.75rem;
    margin-top: 0.5rem;
    padding-top: 0.5rem;
    border-top: 1px solid rgba(100, 120, 140, 0.2);
  }

  .tip-nav-btn {
    background: rgba(100, 120, 140, 0.2);
    border: 1px solid rgba(100, 120, 140, 0.3);
    border-radius: 4px;
    color: #aac;
    font-size: 0.9rem;
    width: 28px;
    height: 28px;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: all 0.15s;
  }

  .tip-nav-btn:hover {
    background: rgba(100, 120, 140, 0.4);
    border-color: var(--tip-color);
    color: var(--tip-color);
  }

  .tip-counter {
    font-size: 0.65rem;
    color: #667;
    min-width: 3rem;
    text-align: center;
  }
</style>
