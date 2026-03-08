<script>
  import { EPOCH_SECONDS, computeRates } from '../lib/gameLogic.js'

  let {
    resources,
    planet,
    buildings = [],
    timeSinceFounding = '--:--:--',
    epochProgress = 0,
    epochCountdown = '--:--',
    epochsElapsed = 0,
    oncollect,
    disabled = false,
  } = $props()

  const rates = $derived(computeRates(buildings, planet?.population ?? 0))

  let nowSeconds = $state(Math.floor(Date.now() / 1000))
  $effect(() => {
    const id = setInterval(() => { nowSeconds = Math.floor(Date.now() / 1000) }, 1000)
    return () => clearInterval(id)
  })

  const isEstimating = $derived(
    resources && planet?.lastActionAt && (nowSeconds - planet.lastActionAt) > 5
  )
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
      <span class="resource-icon">🛡️</span>
      <span class="resource-value">{resources?.defense ?? 0}</span>
      <span class="resource-rate positive">+{rates.defenseRate}/e</span>
    </div>
    <div class="resource-item">
      <span class="resource-icon">☢️</span>
      <span class="resource-value">{resources?.uranium ?? 0}</span>
      <span class="resource-rate positive">+{rates.uraniumRate}/e</span>
    </div>
  </div>

  <div class="top-section epoch-info">
    <div class="epoch-timer">
      <span class="epoch-label">Next Epoch</span>
      <span class="epoch-countdown" class:ready={epochProgress >= 1}>{epochCountdown}</span>
    </div>
    <div class="epoch-progress">
      <div class="epoch-fill" style="width:{epochProgress * 100}%" class:ready={epochProgress >= 1}></div>
    </div>
    {#if epochProgress >= 1}
      <span class="epoch-status ready">Ready to collect!</span>
    {:else}
      <span class="epoch-status">Epochs: {epochsElapsed}</span>
    {/if}
    <button class="collect-btn-compact" onclick={oncollect} {disabled}>
      {disabled ? '...' : 'Collect'}
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

  .resource-rate.positive {
    color: #6a9;
  }

  .resource-rate.negative {
    color: #c66;
  }

  .epoch-info {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    min-width: 140px;
  }

  .epoch-timer {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  .epoch-label {
    font-size: 0.6rem;
    color: #667;
    text-transform: uppercase;
  }

  .epoch-countdown {
    font-size: 0.7rem;
    color: #889;
    font-weight: bold;
    font-variant-numeric: tabular-nums;
  }

  .epoch-countdown.ready {
    color: #6aff9a;
  }

  .epoch-progress {
    height: 3px;
    background: rgba(10, 20, 30, 0.6);
    border-radius: 2px;
    overflow: hidden;
  }

  .epoch-fill {
    height: 100%;
    background: linear-gradient(90deg, #2a5a8a 0%, #4a8aba 100%);
    transition: width 0.3s ease;
  }

  .epoch-fill.ready {
    background: linear-gradient(90deg, #3a9a5a 0%, #6aff9a 100%);
  }

  .epoch-status {
    font-size: 0.6rem;
    color: #667;
    text-align: center;
  }

  .epoch-status.ready {
    color: #6aff9a;
    font-weight: bold;
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
    transition: background 0.15s;
  }

  .collect-btn-compact:hover:not(:disabled) {
    background: #1f4a72;
  }

  .collect-btn-compact:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }
</style>
