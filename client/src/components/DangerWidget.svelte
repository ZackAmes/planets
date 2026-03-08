<script>
  let {
    threat = 0,
    attackProb = 0,
    invaderActive = false,
    defenseRemaining = 0,
    cannonCoverage = 0,
  } = $props()

  const dangerLevel = $derived.by(() => {
    if (invaderActive) return 'critical'
    if (threat >= 75) return 'extreme'
    if (threat >= 50) return 'high'
    if (threat >= 25) return 'moderate'
    return 'low'
  })

  const dangerColor = $derived({
    low: '#44aa66',
    moderate: '#88aa44',
    high: '#cc8844',
    extreme: '#ee5544',
    critical: '#ff2222'
  }[dangerLevel])

  const dangerLabel = $derived({
    low: 'SAFE',
    moderate: 'ALERT',
    high: 'WARNING',
    extreme: 'DANGER',
    critical: 'UNDER ATTACK'
  }[dangerLevel])

  const pulseAnimation = $derived(dangerLevel === 'critical' || dangerLevel === 'extreme')
</script>

<div class="danger-widget" class:pulse={pulseAnimation} style="--danger-color:{dangerColor}">
  <div class="danger-header">
    <span class="danger-icon">⚠</span>
    <span class="danger-status">{dangerLabel}</span>
  </div>
  
  {#if invaderActive}
    <div class="danger-detail critical-text">
      INVADERS PRESENT
    </div>
    {#if cannonCoverage > 0}
      <div class="danger-detail safe-text">
        Cannons: -{cannonCoverage}/ep
      </div>
    {/if}
    {#if defenseRemaining !== undefined}
      <div class="danger-detail">
        Defense: {defenseRemaining}
      </div>
    {/if}
  {:else if threat > 0}
    <div class="danger-meter">
      <div class="meter-fill" style="width:{threat}%"></div>
    </div>
    <div class="danger-stats">
      <span class="stat-item">Threat: {threat}%</span>
      <span class="stat-item">Attack: {attackProb}%</span>
    </div>
  {:else}
    <div class="danger-detail safe-text">
      No immediate threats
    </div>
  {/if}
</div>

<style>
  @keyframes danger-pulse {
    0%, 100% { 
      border-color: var(--danger-color);
      box-shadow: 0 0 0 0 var(--danger-color);
    }
    50% { 
      border-color: var(--danger-color);
      box-shadow: 0 0 12px 2px var(--danger-color);
    }
  }

  .danger-widget {
    background: rgba(5, 5, 20, 0.9);
    border: 2px solid var(--danger-color);
    border-radius: 8px;
    padding: 0.75rem;
    font-family: monospace;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    min-width: 200px;
  }

  .danger-widget.pulse {
    animation: danger-pulse 1.5s ease-in-out infinite;
  }

  .danger-header {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .danger-icon {
    font-size: 1.2rem;
    color: var(--danger-color);
    line-height: 1;
  }

  .danger-status {
    font-size: 0.85rem;
    color: var(--danger-color);
    font-weight: bold;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    flex: 1;
  }

  .danger-meter {
    height: 8px;
    background: rgba(10, 10, 20, 0.8);
    border: 1px solid #1a2030;
    border-radius: 4px;
    overflow: hidden;
  }

  .meter-fill {
    height: 100%;
    background: var(--danger-color);
    transition: width 0.5s ease;
  }

  .danger-stats {
    display: flex;
    justify-content: space-between;
    font-size: 0.7rem;
    color: #889;
  }

  .stat-item {
    color: var(--danger-color);
    font-weight: bold;
  }

  .danger-detail {
    font-size: 0.72rem;
    color: #aac;
    text-align: center;
    padding: 0.2rem;
    background: rgba(10, 15, 25, 0.5);
    border-radius: 3px;
  }

  .critical-text {
    color: #ff4444;
    font-weight: bold;
    text-transform: uppercase;
    letter-spacing: 0.08em;
  }

  .safe-text {
    color: #44aa66;
  }
</style>
