<script>
  import { BUILDING_INFO, previewConstruct, formatLonLat } from '../lib/gameLogic.js'

  let {
    phase,
    planet,
    colony,
    resources,
    assigned,
    unassigned,
    buildings,
    pendingLocation,
    lastEvents,
    disabled = false,
    buildMode = false,
    pendingBuildSite = null,
    onconfirm,
    oncollect,
    onassign,
    onbuildmode,
    onbuild,
  } = $props()

  let selectedBuildType = $state(null)

  // Per-building worker draft: { key -> workers }
  let workerDraft = $state({})

  function bkey(b) { return `${b.lon},${b.lat}` }

  function draftWorkers(b) {
    const k = bkey(b)
    return workerDraft[k] ?? b.workers
  }

  function setDraft(b, v) {
    const k = bkey(b)
    workerDraft[k] = Math.max(0, Math.min(b.maxWorkers, Number(v)))
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

  // Buildings with workers (excludes TownCenter and House)
  const workerBuildings = $derived(
    (buildings ?? []).filter(b => b.maxWorkers > 0)
  )

  // Buildable types (exclude TownCenter)
  const buildableTypes = BUILDING_INFO.filter(i => i.type !== 0)
</script>

<div class="panel">
  {#if phase === 'founding'}
    <h2>Found Colony</h2>
    {#if pendingLocation}
      <div class="section">
        <p class="dim">Location: ({pendingLocation.col}, {pendingLocation.row})</p>
        <button class="primary" onclick={onconfirm} {disabled}>
          {disabled ? 'Confirming…' : 'Settle Here'}
        </button>
      </div>
    {:else}
      <p class="hint">Click the planet to choose a colony site.</p>
    {/if}

  {:else if phase === 'managing'}
    <!-- Resources -->
    <h3>Resources</h3>
    <div class="stats">
      <div class="stat">
        <span class="label">Water</span>
        <span class="value blue">{resources?.water ?? 0}</span>
      </div>
      <div class="stat">
        <span class="label">Iron</span>
        <span class="value gray">{resources?.iron ?? 0}</span>
      </div>
      <div class="stat">
        <span class="label">Defense</span>
        <span class="value green">{resources?.defense ?? 0}</span>
      </div>
      <div class="stat">
        <span class="label">Population</span>
        <span class="value">{planet?.population ?? 0} / {(colony?.tcLevel ?? 1) * 10}</span>
      </div>
    </div>

    <!-- Colonists -->
    <div class="colonists">
      <span class="col-chip">
        <span class="label">Assigned</span>
        <span class="value">{assigned?.count ?? 0}</span>
      </span>
      <span class="col-chip">
        <span class="label">Free</span>
        <span class="value">{unassigned?.count ?? 0}</span>
      </span>
    </div>

    <button class="collect-btn" onclick={oncollect} {disabled}>
      {disabled ? 'Working…' : 'Collect Resources'}
    </button>

    <!-- Worker assignment -->
    {#if workerBuildings.length > 0}
      <div class="divider"></div>
      <h3>Workers</h3>
      {#each workerBuildings as b}
        {@const info = BUILDING_INFO[b.buildingType]}
        <div class="worker-row">
          <span class="bname" style="color:{info?.color}">{info?.name ?? '?'}</span>
          <span class="coords dim">{formatLonLat(b.lon, b.lat)}</span>
          <div class="worker-ctrl">
            <button class="adj" onclick={() => setDraft(b, draftWorkers(b) - 1)} disabled={disabled || draftWorkers(b) <= 0}>-</button>
            <span class="wcount">{draftWorkers(b)}/{b.maxWorkers}</span>
            <button class="adj" onclick={() => setDraft(b, draftWorkers(b) + 1)} disabled={disabled || draftWorkers(b) >= b.maxWorkers}>+</button>
            <button class="assign-btn"
              onclick={() => onassign?.(b.lon, b.lat, draftWorkers(b))}
              disabled={disabled || draftWorkers(b) === b.workers}>
              Assign
            </button>
          </div>
        </div>
      {/each}
    {/if}

    <!-- Build section -->
    <div class="divider"></div>
    {#if !buildMode}
      <h3>Build</h3>
      <div class="build-grid">
        {#each buildableTypes as info}
          {@const canAfford = (resources?.iron ?? 0) >= info.ironCost}
          <button
            class="build-btn"
            class:affordable={canAfford}
            style="--bcolor:{info.color}"
            onclick={() => startBuild(info.type)}
            {disabled}
          >
            <span class="bname-btn">{info.name}</span>
            <span class="bcost">{info.ironCost} iron</span>
          </button>
        {/each}
      </div>
    {:else}
      <h3>Place {BUILDING_INFO[selectedBuildType]?.name}</h3>
      {#if pendingBuildSite}
        {@const preview = previewConstruct(resources, selectedBuildType, planet?.seedFull, pendingBuildSite.lon, pendingBuildSite.lat)}
        <div class="build-confirm">
          <p class="dim">{formatLonLat(pendingBuildSite.lon, pendingBuildSite.lat)}</p>
          {#if preview.canBuild}
            <p class="cost-ok">Cost: {preview.ironCost} iron · +{preview.output}/worker/epoch</p>
            <button class="primary" onclick={confirmBuild} {disabled}>
              {disabled ? 'Building…' : 'Confirm Build'}
            </button>
          {:else}
            <p class="cost-err">{preview.reason}</p>
          {/if}
        </div>
      {:else}
        <p class="hint">Click the planet to choose a site.</p>
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
    <p class="hint">Your colonists are gone.</p>
    <p class="dim">Survived {planet?.actionCount ?? 0} turns.</p>
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

  h2 { font-size: 0.95rem; color: #8ecfff; text-transform: uppercase; letter-spacing: 0.12em; margin: 0 0 0.25rem; }
  h3 { font-size: 0.7rem; color: #7a9; text-transform: uppercase; letter-spacing: 0.1em; margin: 0; }

  .hint { color: #667; font-size: 0.75rem; margin: 0; }
  .dim { color: #556; font-size: 0.7rem; margin: 0; }
  .section { display: flex; flex-direction: column; gap: 0.4rem; }

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

  .label { color: #556; font-size: 0.62rem; text-transform: uppercase; }
  .value { color: #aaddff; font-size: 0.85rem; font-weight: bold; }
  .value.blue { color: #44aaff; }
  .value.gray { color: #aaaaaa; }
  .value.green { color: #44ff88; }

  .colonists {
    display: flex;
    gap: 0.4rem;
  }

  .col-chip {
    flex: 1;
    background: #0a0a18;
    border: 1px solid #1a2030;
    border-radius: 4px;
    padding: 0.25rem 0.5rem;
    display: flex;
    flex-direction: column;
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

  .collect-btn:hover:not(:disabled) { background: #1f4a38; }
  .collect-btn:disabled { opacity: 0.4; cursor: not-allowed; }

  .divider { border-top: 1px solid #1a2a3a; margin: 0.1rem 0; }

  .worker-row {
    background: #0a0a18;
    border: 1px solid #1a2030;
    border-radius: 4px;
    padding: 0.35rem 0.5rem;
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
  }

  .bname { font-size: 0.72rem; font-weight: bold; }

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

  .adj:disabled { opacity: 0.3; cursor: not-allowed; }

  .wcount { font-size: 0.75rem; color: #aac; min-width: 30px; text-align: center; }

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

  .assign-btn:hover:not(:disabled) { background: #1f3a6a; }
  .assign-btn:disabled { opacity: 0.4; cursor: not-allowed; }

  .build-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.3rem;
  }

  .build-btn {
    background: #0a0a18;
    border: 1px solid #1a2030;
    border-radius: 5px;
    padding: 0.4rem 0.3rem;
    cursor: pointer;
    display: flex;
    flex-direction: column;
    gap: 0.1rem;
    text-align: left;
    transition: border-color 0.15s;
  }

  .build-btn:hover:not(:disabled) { border-color: var(--bcolor); }
  .build-btn.affordable { border-color: color-mix(in srgb, var(--bcolor) 40%, #1a2030); }
  .build-btn:disabled { opacity: 0.4; cursor: not-allowed; }

  .bname-btn { color: var(--bcolor); font-size: 0.72rem; font-weight: bold; }
  .bcost { color: #667; font-size: 0.6rem; }

  .build-confirm { display: flex; flex-direction: column; gap: 0.35rem; }
  .cost-ok { color: #7a9; font-size: 0.7rem; margin: 0; }
  .cost-err { color: #e44; font-size: 0.7rem; margin: 0; }

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

  .cancel:hover { color: #e44; border-color: #4a2a2a; }

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

  button.primary:hover:not(:disabled) { background: #1f4a72; }
  button.primary:disabled { opacity: 0.4; cursor: not-allowed; }

  .events { border-top: 1px solid #1a2a3a; padding-top: 0.4rem; display: flex; flex-direction: column; gap: 0.2rem; }
  .event { color: #e8a040; font-size: 0.7rem; margin: 0; }
</style>
