<script>
  import { computeRates } from '../lib/gameLogic.js'

  let {
    resources,
    planet,
    buildings = [],
    timeSinceFounding = '--:--:--',
    epochFraction = 0,
    epochsReady = 0,
    epochNextIn = '--:--',
    oncollect,
    disabled = false,
  } = $props()

  const rates = $derived(computeRates(buildings, planet?.population ?? 0))
  const hasReady = $derived(epochsReady > 0)
</script>

<div class="top-bar">
  <div class="top-section colony-info">
    <span class="top-label">Colony Age</span>
    <span class="top-value">{timeSinceFounding}</span>
    <span class="top-sep">|</span>
    <span class="top-label">Population</span>
    <span class="top-value">{planet?.population ?? 0}</span>
  </div>

  <div class="top-section resources-info">
    <div class="resource-item">
      <span class="resource-icon">💧</span>
      <span class="resource-value">{resources?.water ?? 0}</span>
      <span class="resource-rate" class:negative={rates.netWater < 0}>
        {rates.netWater > 0 ? '+' : ''}{rates.netWater}/e
      </span>
    </div>
    <div class="resource-item">
      <span class="resource-icon">⚙️</span>
      <span class="resource-value">{resources?.iron ?? 0}</span>
      <span class="resource-rate positive">+{rates.ironRate}/e</span>
    </div>
    <div class="resource-item">
      <span class="resource-icon">☢️</span>
      <span class="resource-value">{resources?.uranium ?? 0}</span>
      <span class="resource-rate positive">+{rates.uraniumRate}/e</span>
    </div>
    <div class="resource-item" title="Defense buffer — absorbs invader attacks. Cannons stockpile defense when no invader is active.">
      <span class="resource-icon">🛡️</span>
      <span class="resource-value">{resources?.defense ?? 0}</span>
      <span class="resource-rate positive">+{rates.defenseRate}/e</span>
    </div>
  </div>

  <div class="top-section epoch-info">
    <div class="epoch-header">
      <span class="epoch-label">Epochs ready</span>
      <span class="epoch-ready-count" class:has-ready={hasReady}>{epochsReady}</span>
      <span class="epoch-sep">·</span>
      <span class="epoch-label">next in</span>
      <span class="epoch-next">{epochNextIn}</span>
    </div>
    <div class="epoch-track">
      <div class="epoch-fill" style="width:{epochFraction * 100}%" class:has-ready={hasReady}></div>
    </div>
    <button class="collect-btn-compact" class:glow={hasReady} onclick={oncollect} {disabled}>
      {disabled ? '...' : hasReady ? `Collect (${epochsReady})` : 'Collect'}
    </button>
  </div>
</div>

<style>
  .top-bar {
    position: fixed;
    top: 0;
    left: 50%;
    transform: translateX(-50%);
    z-index: 1000;
    display: flex;
    gap: 1.5rem;
    align-items: center;
    background: rgba(5, 10, 20, 0.95);
    backdrop-filter: blur(8px);
    border: 1px solid #1a2a3a;
    border-top: none;
    border-radius: 0 0 12px 12px;
    padding: 0.75rem 1.5rem;
    font-family: monospace;
    box-shadow: 0 4px 12px rgba(0,0,0,0.3);
  }

  .top-section {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .colony-info {
    gap: 0.4rem;
  }

  .top-label {
    font-size: 0.65rem;
    color: #667;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .top-value {
    font-size: 0.8rem;
    color: #8ac;
    font-weight: bold;
  }

  .top-sep {
    color: #2a3a4a;
    margin: 0 0.25rem;
  }

  .resources-info {
    gap: 0.75rem;
    padding: 0 0.75rem;
    border-left: 1px solid #1a2a3a;
    border-right: 1px solid #1a2a3a;
  }

  .resource-item {
    display: flex;
    align-items: center;
    gap: 0.3rem;
    flex-direction: column;
  }

  .resource-icon {
    font-size: 0.9rem;
  }

  .resource-value {
    font-size: 0.75rem;
    color: #8ac;
    font-weight: bold;
    min-width: 2rem;
    text-align: center;
  }

  .resource-rate {
    font-size: 0.55rem;
    color: #667;
    font-variant-numeric: tabular-nums;
  }

  .resource-rate.positive { color: #6a9; }
  .resource-rate.negative { color: #c66; }

  /* Epoch section */
  .epoch-info {
    display: flex;
    flex-direction: column;
    gap: 0.3rem;
    min-width: 160px;
  }

  .epoch-header {
    display: flex;
    align-items: center;
    gap: 0.35rem;
  }

  .epoch-label {
    font-size: 0.6rem;
    color: #667;
    text-transform: uppercase;
  }

  .epoch-sep {
    color: #334;
    font-size: 0.6rem;
  }

  .epoch-ready-count {
    font-size: 0.8rem;
    font-weight: bold;
    color: #556;
    font-variant-numeric: tabular-nums;
    min-width: 1.2rem;
    text-align: center;
    transition: color 0.3s;
  }

  .epoch-ready-count.has-ready {
    color: #6aff9a;
  }

  .epoch-next {
    font-size: 0.7rem;
    color: #667;
    font-variant-numeric: tabular-nums;
    margin-left: auto;
  }

  .epoch-track {
    height: 4px;
    background: rgba(10, 20, 30, 0.8);
    border-radius: 2px;
    overflow: hidden;
    border: 1px solid #1a2a3a;
  }

  .epoch-fill {
    height: 100%;
    background: linear-gradient(90deg, #2a5a8a, #4a8aba);
    transition: width 1s linear;
  }

  .epoch-fill.has-ready {
    background: linear-gradient(90deg, #3a9a5a, #6aff9a);
  }

  .collect-btn-compact {
    background: #1a3a5a;
    border: 1px solid #2a5a8a;
    border-radius: 4px;
    color: #8ecfff;
    font-family: monospace;
    font-size: 0.65rem;
    padding: 0.3rem 0.6rem;
    cursor: pointer;
    transition: background 0.15s, border-color 0.15s, color 0.15s, box-shadow 0.15s;
  }

  .collect-btn-compact.glow {
    background: #1a3a2a;
    border-color: #2a6a4a;
    color: #6aff9a;
    box-shadow: 0 0 6px rgba(106, 255, 154, 0.25);
  }

  .collect-btn-compact:hover:not(:disabled) {
    background: #1f4a72;
  }

  .collect-btn-compact.glow:hover:not(:disabled) {
    background: #1f4a38;
  }

  .collect-btn-compact:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }
</style>
