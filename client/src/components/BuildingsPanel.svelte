<script>
  import CollapsiblePanel from './CollapsiblePanel.svelte'
  import { BUILDING_INFO, upgradeBuildingCost, formatLonLat } from '../lib/gameLogic.js'

  let {
    building,
    resources,
    tcLevel = 1,
    onassign,
    onupgradebuilding,
    ondeselect,
    disabled = false,
  } = $props()

  let nowSeconds = $state(Math.floor(Date.now() / 1000))
  $effect(() => {
    const id = setInterval(() => { nowSeconds = Math.floor(Date.now() / 1000) }, 1000)
    return () => clearInterval(id)
  })

  let workerDraft = $state(0)

  // Reset draft when building changes
  $effect(() => {
    if (building) {
      workerDraft = building.workers
    }
  })

  function setDraft(v) {
    workerDraft = Math.max(0, Math.min(building.maxWorkers, Number(v)))
  }

  function isBusyBuilding(b) {
    return b.completesAt > 0 && b.completesAt > nowSeconds
  }

  function buildingCountdown(b) {
    if (!b.completesAt || b.completesAt <= nowSeconds) return null
    const remaining = b.completesAt - nowSeconds
    const m = Math.floor(remaining / 60)
    const s = remaining % 60
    return `${m}:${s.toString().padStart(2, '0')}`
  }

  function busyLabel(b) {
    if (b.buildingType === 4 && b.workers > 0) return 'Training'
    return 'Building'
  }

  const info = $derived(BUILDING_INFO[building?.buildingType ?? 0])
  const bLevel = $derived(building?.level ?? 1)
  const upCost = $derived(upgradeBuildingCost(bLevel))
  const busy = $derived(building ? isBusyBuilding(building) : false)
  const countdown = $derived(building ? buildingCountdown(building) : null)
  const canUpgrade = $derived(
    !busy &&
    bLevel < 3 &&
    bLevel < tcLevel &&
    (resources?.iron ?? 0) >= upCost.iron
  )
  const totalOutput = $derived((building?.workers ?? 0) * (building?.outputPerWorkerEpoch ?? 0))
</script>

<CollapsiblePanel title="Manage Building" defaultOpen={true}>
  <button class="deselect-btn" onclick={ondeselect}>
    ← Back to Colony View
  </button>

  <div class="worker-row" class:busy-row={busy}>
    <div class="brow-header">
      <span class="bname" style="color:{info?.color}">{info?.name ?? '?'}</span>
      <span class="blevel dim">lv{bLevel}</span>
      {#if busy}
        <span class="busy-label">{busyLabel(building)} {countdown}</span>
      {:else if bLevel < 3}
        <button class="upgrade-btn" onclick={() => onupgradebuilding?.(building.lon, building.lat)}
          disabled={!canUpgrade || disabled}
          title="Upgrade ({upCost.iron} iron)">
          +lv
        </button>
      {/if}
    </div>
    
    <div class="brow-meta">
      <span class="coords dim">{formatLonLat(building.lon, building.lat)}</span>
      {#if busy && building.buildingType === 4 && building.workers > 0}
        <span class="output-tag training">Training...</span>
      {:else if busy}
        <span class="output-tag busy-tag">Busy...</span>
      {:else if building.buildingType === 4}
        <span class="output-tag training">+{bLevel} str/session</span>
      {:else if totalOutput > 0}
        <span class="output-tag">
          {building.buildingType === 8 ? `+${totalOutput} def/ep` : `+${totalOutput} ${info?.resource}/ep`}
        </span>
      {/if}
    </div>
    
    <div class="worker-ctrl">
      <button class="adj" onclick={() => setDraft(workerDraft - 1)} 
        disabled={disabled || busy || workerDraft <= 0}>-</button>
      <span class="wcount">{workerDraft}/{building.maxWorkers}</span>
      <button class="adj" onclick={() => setDraft(workerDraft + 1)} 
        disabled={disabled || busy || workerDraft >= building.maxWorkers}>+</button>
      <button class="assign-btn"
        onclick={() => onassign?.(building.lon, building.lat, workerDraft)}
        disabled={disabled || busy || workerDraft === building.workers}>
        {busy ? 'Busy' : 'Assign'}
      </button>
    </div>
  </div>

  <p class="hint">Click building on planet to select different building</p>
</CollapsiblePanel>

<style>
  .deselect-btn {
    background: rgba(10, 15, 25, 0.5);
    border: 1px solid #1a2a3a;
    border-radius: 4px;
    color: #6ab4ff;
    font-family: monospace;
    font-size: 0.7rem;
    padding: 0.35rem 0.6rem;
    cursor: pointer;
    width: 100%;
    transition: background 0.15s, border-color 0.15s;
  }

  .deselect-btn:hover {
    background: rgba(15, 20, 30, 0.6);
    border-color: #2a4a6a;
  }

  .hint {
    color: #556;
    font-size: 0.65rem;
    margin: 0;
    font-style: italic;
    text-align: center;
  }

  .empty-msg {
    color: #667;
    font-size: 0.7rem;
    margin: 0;
    font-style: italic;
    line-height: 1.4;
  }

  .empty-msg {
    color: #667;
    font-size: 0.7rem;
    margin: 0;
    font-style: italic;
    line-height: 1.4;
  }

  .worker-row {
    background: #0a0a18;
    border: 1px solid #1a2030;
    border-radius: 4px;
    padding: 0.35rem 0.5rem;
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
  }

  .busy-row {
    opacity: 0.75;
  }

  .brow-header {
    display: flex;
    align-items: center;
    gap: 0.3rem;
  }

  .bname {
    font-size: 0.72rem;
    font-weight: bold;
  }

  .blevel {
    font-size: 0.62rem;
    color: #556;
  }

  .dim {
    color: #556;
  }

  .busy-label {
    font-size: 0.6rem;
    color: #cc8844;
    margin-left: auto;
    font-variant-numeric: tabular-nums;
  }

  .upgrade-btn {
    background: #1a2a1a;
    border: 1px solid #3a6a3a;
    border-radius: 3px;
    color: #6aff6a;
    font-family: monospace;
    font-size: 0.6rem;
    padding: 0.05rem 0.3rem;
    cursor: pointer;
    margin-left: auto;
  }

  .upgrade-btn:hover:not(:disabled) {
    background: #253525;
  }

  .upgrade-btn:disabled {
    opacity: 0.3;
    cursor: not-allowed;
  }

  .brow-meta {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  .coords {
    font-size: 0.6rem;
  }

  .output-tag {
    font-size: 0.6rem;
    color: #5a8a6a;
  }

  .output-tag.training {
    color: #4466ff;
  }

  .output-tag.busy-tag {
    color: #cc8844;
  }

  .worker-ctrl {
    display: flex;
    align-items: center;
    gap: 0.3rem;
  }

  .adj {
    background: #1a1a2a;
    border: 1px solid #2a2a4a;
    border-radius: 3px;
    color: #8ecfff;
    font-family: monospace;
    font-size: 0.8rem;
    width: 20px;
    height: 20px;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
  }

  .adj:disabled {
    opacity: 0.3;
    cursor: not-allowed;
  }

  .wcount {
    font-size: 0.75rem;
    color: #aac;
    min-width: 30px;
    text-align: center;
  }

  .assign-btn {
    background: #1a2a4a;
    border: 1px solid #2a4a6a;
    border-radius: 4px;
    color: #6ab4ff;
    font-family: monospace;
    font-size: 0.65rem;
    padding: 0.15rem 0.4rem;
    cursor: pointer;
    margin-left: auto;
  }

  .assign-btn:hover:not(:disabled) {
    background: #1f3a6a;
  }

  .assign-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }
</style>
