<script>
  import { BUILDING_INFO, previewConstruct, formatLonLat } from '../lib/gameLogic.js'

  let {
    phase,           // 'founding' | 'managing' | 'gameover'
    planet,
    colony,
    pendingLocation, // { col, row } | null
    lastEvents,
    disabled = false,
    buildMode = false,        // true when player is picking a build site
    pendingBuildSite = null,  // { lon, lat } chosen but not confirmed
    onconfirm,       // () => void
    onsubmit,        // (orders) => void
    onbuildmode,     // (type: number | null) => void — enter/exit build mode
    onbuild,         // (lon, lat, type) => void
  } = $props()

  let farming  = $state(50)
  let mining   = $state(20)
  let building = $state(20)
  let defense  = $state(10)

  const total = $derived(farming + mining + building + defense)
  const valid = $derived(total <= 100)

  // Which building type the player has selected for placement
  let selectedBuildType = $state(null)

  function handleSubmit() {
    if (!valid) return
    onsubmit({ farming, mining, building, defense })
  }

  function startBuild(type) {
    selectedBuildType = type
    onbuildmode?.(type)
  }

  function cancelBuild() {
    selectedBuildType = null
    onbuildmode?.(null)
  }

  function confirmBuild() {
    if (pendingBuildSite == null || selectedBuildType == null) return
    onbuild?.(pendingBuildSite.lon, pendingBuildSite.lat, selectedBuildType)
  }

  function canAfford(type) {
    if (!colony) return false
    const preview = previewConstruct(colony, type)
    return preview.canBuild
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
        <button class="primary" onclick={onconfirm} {disabled}>
          {disabled ? 'Confirming…' : 'Settle Here'}
        </button>
      </div>
    {:else}
      <p class="hint">Click on the planet to choose a colony site.</p>
    {/if}

  {:else if phase === 'managing'}
    <h2>Colony Orders</h2>

    <!-- Resource stats -->
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
        <span class="label">Build Pts</span>
        <span class="value">{colony?.buildPoints ?? 0}</span>
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

    <!-- Building counts badge row -->
    {#if colony && (colony.farms + colony.mines + colony.barracks + colony.workshops) > 0}
      <div class="building-badges">
        {#each BUILDING_INFO as info}
          {#if (colony[['farms','mines','barracks','workshops'][info.type]] ?? 0) > 0}
            <span class="badge" style="color:{info.color}">
              {['farms','mines','barracks','workshops'][info.type][0].toUpperCase()}&thinsp;×{colony[['farms','mines','barracks','workshops'][info.type]]}
            </span>
          {/if}
        {/each}
      </div>
    {/if}

    <div class="divider"></div>

    <!-- Orders sliders -->
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
      {total}% allocated {valid ? '' : '— over 100!'}
    </div>

    <button class="primary" onclick={handleSubmit} disabled={!valid || disabled}>
      {disabled ? 'Submitting…' : 'End Turn'}
    </button>

    <div class="divider"></div>

    <!-- Build section -->
    {#if !buildMode}
      <h3>Construct</h3>
      <div class="build-grid">
        {#each BUILDING_INFO as info}
          <button
            class="build-btn"
            class:affordable={canAfford(info.type)}
            style="--bcolor:{info.color}"
            onclick={() => startBuild(info.type)}
            {disabled}
          >
            <span class="bname">{info.name}</span>
            <span class="bcost">{info.mineralCost}⛏ {info.buildCost}🔨</span>
            <span class="bdesc">{info.description}</span>
          </button>
        {/each}
      </div>
    {:else}
      <h3>Place {BUILDING_INFO[selectedBuildType]?.name}</h3>

      {#if pendingBuildSite}
        <div class="build-confirm">
          <p class="site-coords">
            {formatLonLat(pendingBuildSite.lon, pendingBuildSite.lat)}
          </p>
          {#if colony}
            {#if previewConstruct(colony, selectedBuildType).canBuild}
              <p class="cost-ok">
                Cost: {BUILDING_INFO[selectedBuildType].mineralCost} minerals
                + {BUILDING_INFO[selectedBuildType].buildCost} build pts
              </p>
              <button class="primary" onclick={confirmBuild} {disabled}>
                {disabled ? 'Building…' : 'Confirm Build'}
              </button>
            {:else}
              <p class="cost-err">{previewConstruct(colony, selectedBuildType).reason}</p>
            {/if}
          {/if}
        </div>
      {:else}
        <p class="hint">Click on the planet to choose a build site.</p>
      {/if}

      <button class="cancel" onclick={cancelBuild}>Cancel</button>
    {/if}

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

  h3 {
    font-size: 0.75rem;
    color: #7a9;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    margin: 0;
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

  .building-badges {
    display: flex;
    gap: 0.4rem;
    flex-wrap: wrap;
  }

  .badge {
    font-size: 0.7rem;
    background: #0a0a18;
    border: 1px solid #1a2030;
    border-radius: 4px;
    padding: 0.15rem 0.4rem;
  }

  .divider {
    border-top: 1px solid #1a2a3a;
    margin: 0.1rem 0;
  }

  .orders {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
  }

  .order-row {
    display: grid;
    grid-template-columns: 58px 1fr 30px;
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

  .build-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.35rem;
  }

  .build-btn {
    background: #0a0a18;
    border: 1px solid #1a2030;
    border-radius: 5px;
    padding: 0.4rem 0.3rem;
    cursor: pointer;
    display: flex;
    flex-direction: column;
    gap: 0.15rem;
    text-align: left;
    transition: border-color 0.15s;
  }

  .build-btn:hover:not(:disabled) {
    border-color: var(--bcolor);
  }

  .build-btn.affordable {
    border-color: color-mix(in srgb, var(--bcolor) 40%, #1a2030);
  }

  .build-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .bname {
    color: var(--bcolor);
    font-size: 0.75rem;
    font-weight: bold;
  }

  .bcost {
    color: #556;
    font-size: 0.6rem;
  }

  .bdesc {
    color: #7a8a8a;
    font-size: 0.6rem;
  }

  .build-confirm {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
  }

  .site-coords {
    color: #8ecfff;
    font-size: 0.75rem;
  }

  .cost-ok {
    color: #7a9;
    font-size: 0.72rem;
  }

  .cost-err {
    color: #e44;
    font-size: 0.72rem;
  }

  .cancel {
    background: none;
    border: 1px solid #2a1a1a;
    border-radius: 4px;
    color: #665;
    font-family: monospace;
    font-size: 0.72rem;
    padding: 0.3rem;
    cursor: pointer;
  }

  .cancel:hover {
    color: #e44;
    border-color: #4a2a2a;
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
