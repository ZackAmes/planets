<script>
  import CollapsiblePanel from './CollapsiblePanel.svelte'
  import InfoTooltip from './InfoTooltip.svelte'
  import { computeRates, EPOCH_SECONDS } from '../lib/gameLogic.js'

  let {
    resources,
    buildings = [],
    planet,
    tcLevel = 1,
    epochProgress = 0,
    epochCountdown = '--:--',
    epochsElapsed = 0,
    threat = 0,
    attackProb = 0,
    oncollect,
    disabled = false,
    showHelp = false,
  } = $props()

  const rates = $derived(computeRates(buildings, planet?.population ?? 0))
  
  let showTooltip = $state(false)
  
  // Calculate estimated current resources based on time since last collection
  let nowSeconds = $state(Math.floor(Date.now() / 1000))
  $effect(() => {
    const id = setInterval(() => { nowSeconds = Math.floor(Date.now() / 1000) }, 1000)
    return () => clearInterval(id)
  })
  
  const estimatedResources = $derived.by(() => {
    if (!resources || !planet?.lastActionAt) return resources
    
    const secondsSinceLastAction = nowSeconds - planet.lastActionAt
    const epochsFraction = Math.min(secondsSinceLastAction / EPOCH_SECONDS, 1)
    
    const estimatedWater = Math.max(0, (resources.water ?? 0) + Math.floor(rates.netWater * epochsFraction))
    const estimatedIron = (resources.iron ?? 0) + Math.floor(rates.ironRate * epochsFraction)
    const estimatedDefense = (resources.defense ?? 0) + Math.floor(rates.defenseRate * epochsFraction)
    const estimatedUranium = (resources.uranium ?? 0) + Math.floor(rates.uraniumRate * epochsFraction)
    
    return {
      water: estimatedWater,
      iron: estimatedIron,
      defense: estimatedDefense,
      uranium: estimatedUranium,
      lastUpdatedAt: resources.lastUpdatedAt,
    }
  })
  
  const isEstimating = $derived(
    resources && planet?.lastActionAt && (nowSeconds - planet.lastActionAt) > 5
  )
</script>

<CollapsiblePanel title="Resources" defaultOpen={true}>
  <div class="help-row">
    <button class="help-btn" onclick={() => showTooltip = !showTooltip}>
      {showTooltip ? 'Hide' : 'Show'} Tips
    </button>
  </div>
  
  <InfoTooltip show={showTooltip} />
  
  <div class="stats">
    <div class="stat">
      <span class="label">Water</span>
      <span class="value blue" class:estimating={isEstimating}>
        {estimatedResources?.water ?? 0}
        {#if isEstimating}<span class="est-indicator">~</span>{/if}
      </span>
      <span class="rate" class:negative={rates.netWater < 0}>
        {rates.netWater >= 0 ? '+' : ''}{rates.netWater}/ep
      </span>
    </div>
    
    <div class="stat">
      <span class="label">Iron</span>
      <span class="value gray" class:estimating={isEstimating}>
        {estimatedResources?.iron ?? 0}
        {#if isEstimating}<span class="est-indicator">~</span>{/if}
      </span>
      <span class="rate positive">+{rates.ironRate}/ep</span>
    </div>
    
    <div class="stat">
      <span class="label">Defense</span>
      <span class="value green" class:estimating={isEstimating}>
        {estimatedResources?.defense ?? 0}
        {#if isEstimating}<span class="est-indicator">~</span>{/if}
      </span>
      <span class="rate positive">+{rates.defenseRate}/ep</span>
    </div>
    
    <div class="stat">
      <span class="label">Uranium</span>
      <span class="value purple" class:estimating={isEstimating}>
        {estimatedResources?.uranium ?? 0}
        {#if isEstimating}<span class="est-indicator">~</span>{/if}
      </span>
      <span class="rate" class:positive={rates.uraniumRate > 0}>
        +{rates.uraniumRate}/ep
      </span>
    </div>
    
    <div class="stat">
      <span class="label">Pop / Cap</span>
      <span class="value">{planet?.population ?? 0} / {tcLevel * 10}</span>
      <span class="rate dim">TC lv{tcLevel}      </span>
    </div>
  </div>

  {#if isEstimating}
    <p class="estimate-note">~ Estimated values based on production rates</p>
  {/if}

  <div class="epoch-section">
    <div class="epoch-header">
      <span class="epoch-title">Time Until Next Epoch</span>
      <span class="epoch-countdown" class:ready={epochProgress >= 1}>{epochCountdown}</span>
    </div>
    <div class="epoch-track">
      <div class="epoch-fill" style="width:{epochProgress * 100}%" class:ready={epochProgress >= 1}></div>
    </div>
    <div class="epoch-footer">
      <span class="epoch-info">
        {#if epochProgress >= 1}
          <strong style="color: #6aff9a;">Full epoch ready!</strong> Click collect to claim resources
        {:else}
          Epochs since last claim: <strong>{epochsElapsed}</strong>
        {/if}
      </span>
    </div>
  </div>

  <button class="collect-btn" onclick={oncollect} {disabled}>
    {disabled ? 'Working…' : 'Collect Resources'}
  </button>

  {#if threat > 0}
    <div class="threat-row">
      <span class="threat-label">Threat</span>
      <div class="threat-track">
        <div class="threat-fill"
          style="width:{threat}%; background:{threat < 33 ? '#3a9a6a' : threat < 66 ? '#c8901a' : '#e04444'}">
        </div>
      </div>
      <span class="threat-pct" style="color:{threat < 33 ? '#5ab' : threat < 66 ? '#ca8' : '#e66'}">
        {threat}% · {attackProb}% atk
      </span>
    </div>
  {/if}
</CollapsiblePanel>

<style>

  .stats {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.3rem;
  }

  .stat {
    background: #0a0a18;
    border: 1px solid #1a2030;
    border-radius: 4px;
    padding: 0.25rem 0.5rem;
    display: flex;
    flex-direction: column;
  }

  .label {
    color: #556;
    font-size: 0.62rem;
    text-transform: uppercase;
  }

  .value {
    color: #aaddff;
    font-size: 0.85rem;
    font-weight: bold;
  }

  .value.blue { color: #44aaff; }
  .value.gray { color: #aaaaaa; }
  .value.green { color: #44ff88; }
  .value.purple { color: #bb44ff; }

  .rate {
    font-size: 0.6rem;
    color: #556;
  }

  .rate.positive { color: #5a9; }
  .rate.negative { color: #e55; }
  .rate.dim { color: #446; }

  .estimating {
    position: relative;
  }

  .est-indicator {
    font-size: 0.7rem;
    color: #8ac;
    margin-left: 0.1rem;
  }

  .estimate-note {
    font-size: 0.6rem;
    color: #667;
    margin: 0;
    text-align: center;
    font-style: italic;
    padding: 0.2rem;
    background: rgba(10, 30, 40, 0.3);
    border-radius: 3px;
  }

  .epoch-section {
    display: flex;
    flex-direction: column;
    gap: 0.3rem;
    background: rgba(10, 20, 30, 0.4);
    padding: 0.6rem;
    border-radius: 6px;
    border: 1px solid #1a2a3a;
  }

  .epoch-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  .epoch-title {
    font-size: 0.65rem;
    color: #667;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .epoch-countdown {
    font-size: 0.75rem;
    color: #889;
    font-weight: bold;
    font-variant-numeric: tabular-nums;
  }

  .epoch-countdown.ready {
    color: #6aff9a;
  }

  .epoch-footer {
    display: flex;
    justify-content: center;
  }

  .epoch-info {
    font-size: 0.65rem;
    color: #667;
    text-align: center;
  }

  .epoch-info strong {
    color: #8ac;
    font-weight: bold;
  }

  .epoch-hint {
    font-size: 0.6rem;
    color: #556;
    margin: 0;
    text-align: center;
    font-style: italic;
  }

  .epoch-wrap {
    display: flex;
    align-items: center;
    gap: 0.4rem;
  }

  .epoch-track {
    flex: 1;
    height: 8px;
    background: #0a0a18;
    border: 1px solid #1a2030;
    border-radius: 3px;
    overflow: hidden;
  }

  .epoch-fill {
    height: 100%;
    background: #1a5a3a;
    transition: width 1s linear;
  }

  .epoch-fill.ready {
    background: #2a8a5a;
  }

  .epoch-label {
    font-size: 0.62rem;
    color: #557;
    min-width: 36px;
    text-align: right;
    font-variant-numeric: tabular-nums;
  }

  .epoch-label.ready {
    color: #6aff9a;
  }

  .collect-btn {
    background: #1a3a2a;
    border: 1px solid #2a6a4a;
    border-radius: 6px;
    color: #6aff9a;
    font-family: monospace;
    font-size: 0.78rem;
    padding: 0.45rem;
    cursor: pointer;
    width: 100%;
    transition: background 0.15s;
  }

  .collect-btn:hover:not(:disabled) {
    background: #1f4a38;
  }

  .collect-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .threat-row {
    display: flex;
    align-items: center;
    gap: 0.35rem;
  }

  .threat-label {
    font-size: 0.6rem;
    color: #556;
    min-width: 36px;
  }

  .threat-track {
    flex: 1;
    height: 6px;
    background: #0a0a18;
    border: 1px solid #1a2030;
    border-radius: 3px;
    overflow: hidden;
  }

  .threat-fill {
    height: 100%;
    transition: width 0.5s ease, background 0.5s ease;
  }

  .threat-pct {
    font-size: 0.58rem;
    min-width: 72px;
    text-align: right;
  }

  .help-row {
    display: flex;
    justify-content: flex-end;
    margin-bottom: 0.5rem;
  }

  .help-btn {
    background: rgba(10, 30, 50, 0.5);
    border: 1px solid #2a4a6a;
    border-radius: 4px;
    color: #6ab4ff;
    font-family: monospace;
    font-size: 0.65rem;
    padding: 0.25rem 0.5rem;
    cursor: pointer;
    transition: all 0.15s;
  }

  .help-btn:hover {
    background: rgba(15, 35, 60, 0.7);
    border-color: #4a6a9a;
  }
</style>
