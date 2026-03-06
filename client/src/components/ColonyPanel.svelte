<script>
  let {
    phase,           // 'founding' | 'managing' | 'gameover'
    planet,
    colony,
    pendingLocation, // { col, row } | null — location chosen but not confirmed
    lastEvents,      // string[]
    onconfirm,       // () => void — confirm colony location
    onsubmit,        // (orders) => void — submit turn orders
  } = $props()

  let farming = $state(50)
  let mining = $state(20)
  let building = $state(20)
  let defense = $state(10)

  const total = $derived(farming + mining + building + defense)
  const valid = $derived(total <= 100)

  function handleSubmit() {
    if (!valid) return
    onsubmit({ farming, mining, building, defense })
  }

  function clamp(val) {
    return Math.min(100, Math.max(0, val))
  }
</script>

<div class="panel">
  {#if phase === 'founding'}
    <h2>Found a Colony</h2>

    {#if pendingLocation}
      <div class="location-info">
        <p>Location: ({pendingLocation.col}, {pendingLocation.row})</p>
        {#if colony}
          <div class="bonuses">
            <span class="bonus">Fertility: {colony.fertility}/100</span>
            <span class="bonus">Minerals: {colony.mineralRichness}/100</span>
          </div>
        {/if}
        <button class="primary" onclick={onconfirm}>Settle Here</button>
      </div>
    {:else}
      <p class="hint">Click on the planet to choose a colony site.</p>
    {/if}

  {:else if phase === 'managing'}
    <h2>Colony Orders</h2>

    <div class="stats">
      <div class="stat">
        <span class="label">Population</span>
        <span class="value">{planet?.population ?? 0}</span>
      </div>
      <div class="stat">
        <span class="label">Food</span>
        <span class="value">{colony?.food ?? 0}</span>
      </div>
      <div class="stat">
        <span class="label">Minerals</span>
        <span class="value">{colony?.minerals ?? 0}</span>
      </div>
      <div class="stat">
        <span class="label">Buildings</span>
        <span class="value">{colony?.buildings ?? 0}</span>
      </div>
      <div class="stat">
        <span class="label">Defense</span>
        <span class="value">{colony?.defense ?? 0}</span>
      </div>
      <div class="stat">
        <span class="label">Turn</span>
        <span class="value">{planet?.actionCount ?? 0}</span>
      </div>
    </div>

    <div class="divider"></div>

    <div class="orders">
      <div class="order-row">
        <label for="r-farming">Farming</label>
        <input id="r-farming" type="range" min="0" max="100" bind:value={farming} />
        <span class="pct">{farming}%</span>
      </div>
      <div class="order-row">
        <label for="r-mining">Mining</label>
        <input id="r-mining" type="range" min="0" max="100" bind:value={mining} />
        <span class="pct">{mining}%</span>
      </div>
      <div class="order-row">
        <label for="r-building">Building</label>
        <input id="r-building" type="range" min="0" max="100" bind:value={building} />
        <span class="pct">{building}%</span>
      </div>
      <div class="order-row">
        <label for="r-defense">Defense</label>
        <input id="r-defense" type="range" min="0" max="100" bind:value={defense} />
        <span class="pct">{defense}%</span>
      </div>
    </div>

    <div class="total" class:over={!valid}>
      Allocated: {total}% {valid ? '' : '(over 100!)'}
    </div>

    <div class="idle-note">
      {100 - total}% idle (no output)
    </div>

    <button class="primary" onclick={handleSubmit} disabled={!valid}>
      End Turn
    </button>

    {#if lastEvents.length > 0}
      <div class="events">
        {#each lastEvents as ev}
          <p class="event">{ev}</p>
        {/each}
      </div>
    {/if}

  {:else if phase === 'gameover'}
    <h2>Colony Lost</h2>
    <p class="hint">Your colonists are gone. The planet is silent once more.</p>
    <p>Survived {planet?.actionCount ?? 0} turns.</p>
  {/if}
</div>

<style>
  .panel {
    width: 240px;
    background: rgba(5, 5, 20, 0.85);
    border: 1px solid #1a2a3a;
    border-radius: 8px;
    padding: 1rem;
    color: #ccd;
    font-family: monospace;
    font-size: 0.8rem;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    max-height: calc(100vh - 2rem);
    overflow-y: auto;
  }

  h2 {
    font-size: 0.95rem;
    color: #8ecfff;
    text-transform: uppercase;
    letter-spacing: 0.12em;
    margin: 0 0 0.25rem;
  }

  .hint {
    color: #667;
    font-size: 0.75rem;
  }

  .location-info {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .bonuses {
    display: flex;
    gap: 0.75rem;
  }

  .bonus {
    background: #0a1a2a;
    border: 1px solid #1a3a5a;
    border-radius: 4px;
    padding: 0.2rem 0.4rem;
    color: #6ab4ff;
    font-size: 0.75rem;
  }

  .stats {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.35rem;
  }

  .stat {
    background: #0a0a18;
    border: 1px solid #1a2030;
    border-radius: 4px;
    padding: 0.3rem 0.5rem;
    display: flex;
    flex-direction: column;
  }

  .label {
    color: #556;
    font-size: 0.65rem;
    text-transform: uppercase;
  }

  .value {
    color: #aaddff;
    font-size: 0.9rem;
    font-weight: bold;
  }

  .divider {
    border-top: 1px solid #1a2a3a;
    margin: 0.25rem 0;
  }

  .orders {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
  }

  .order-row {
    display: grid;
    grid-template-columns: 60px 1fr 32px;
    align-items: center;
    gap: 0.4rem;
  }

  .order-row label {
    color: #889;
    font-size: 0.72rem;
  }

  .order-row input[type='range'] {
    width: 100%;
    accent-color: #4a8fd4;
  }

  .pct {
    text-align: right;
    color: #aaddff;
    font-size: 0.72rem;
  }

  .total {
    font-size: 0.75rem;
    color: #7a9;
    text-align: right;
  }

  .total.over {
    color: #e44;
  }

  .idle-note {
    font-size: 0.68rem;
    color: #445;
    text-align: right;
  }

  button.primary {
    background: #1a3a5a;
    border: 1px solid #2a5a8a;
    border-radius: 6px;
    color: #8ecfff;
    font-family: monospace;
    font-size: 0.8rem;
    padding: 0.5rem;
    cursor: pointer;
    transition: background 0.15s;
    width: 100%;
  }

  button.primary:hover:not(:disabled) {
    background: #1f4a72;
  }

  button.primary:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .events {
    border-top: 1px solid #1a2a3a;
    padding-top: 0.4rem;
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
  }

  .event {
    color: #e8a040;
    font-size: 0.72rem;
  }
</style>
