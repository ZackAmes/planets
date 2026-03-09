<script>
  import CollapsiblePanel from './CollapsiblePanel.svelte'
  import { BUILDING_INFO, previewConstruct, formatLonLat, terrainName, terrainCanBuild } from '../lib/gameLogic.js'

  let {
    resources,
    planet,
    tcLevel = 1,
    buildMode = false,
    pendingBuildSite = null,
    pendingLocation = null,
    pendingLocationTerrain = null,
    onbuildmode,
    onbuild,
    onconfirm,
    onexit,
    disabled = false,
    phase = 'managing',
  } = $props()

  let selectedBuildType = $state(null)
  let hoveredBuildType = $state(null)

  const buildableTypes = $derived(
    BUILDING_INFO.filter(i => i.type !== 0)
  )

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
  
  const panelTitle = $derived(phase === 'founding' ? 'Found Colony' : 'Build Structures')
  const panelColor = $derived(phase === 'founding' ? '#8ecfff' : '#7a9')
</script>

{#if phase === 'founding'}
  <CollapsiblePanel title={panelTitle} defaultOpen={true} color={panelColor}>
    {#if pendingLocation}
      {@const canSettle = pendingLocationTerrain === null || terrainCanBuild(pendingLocationTerrain)}
      <div class="section">
        <p class="location-info">Location: ({pendingLocation.col}, {pendingLocation.row})</p>
        {#if pendingLocationTerrain !== null}
          <div class="terrain-badge">
            <span class="terrain-name">{terrainName(pendingLocationTerrain)}</span>
            {#if !canSettle}
              <span class="terrain-ocean">unbuildable</span>
            {/if}
          </div>
        {/if}
        {#if !canSettle}
          <p class="cost-err">Cannot settle on ocean — pick a land tile.</p>
        {/if}
        <button class="primary" onclick={onconfirm} disabled={disabled || !canSettle}>
          {disabled ? 'Confirming…' : 'Settle Here'}
        </button>
      </div>
    {:else}
      <p class="hint">Click the planet to choose a colony site.</p>
      <p class="hint">Avoid ocean tiles.</p>
    {/if}
  </CollapsiblePanel>
{:else}
  <CollapsiblePanel title={panelTitle} defaultOpen={true} color={panelColor}>
    <button class="exit-build-btn" onclick={onexit}>
      Exit Build Mode
    </button>
    
    {#if !selectedBuildType}
      <div class="build-grid">
        {#each buildableTypes as info}
          {@const isLocked = tcLevel < info.minTcLevel}
          {@const canAfford = !isLocked && (resources?.iron ?? 0) >= info.ironCost && (resources?.water ?? 0) >= info.waterCost && (resources?.uranium ?? 0) >= (info.uraniumCost ?? 0)}
          <button
            class="build-btn"
            class:affordable={canAfford}
            class:locked={isLocked}
            class:selected={hoveredBuildType === info.type}
            style="--bcolor:{info.color}"
            onclick={() => startBuild(info.type)}
            onmouseenter={() => hoveredBuildType = info.type}
            onmouseleave={() => hoveredBuildType = null}
            disabled={disabled || isLocked}
          >
            <span class="bname-btn">{info.name}</span>
            <span class="bcost">
              {info.ironCost > 0 ? `${info.ironCost} iron` : 'free'}{info.waterCost > 0 ? ` + ${info.waterCost} water` : ''}{info.uraniumCost > 0 ? ` + ${info.uraniumCost} U` : ''}
            </span>
            {#if isLocked}
              <span class="lock-msg">TC lvl {info.minTcLevel} required</span>
            {/if}
            {#if info.maxWorkers > 0}
              <span class="bworkers">up to {info.maxWorkers}w · {info.baseOutput} base/ep</span>
            {:else if info.type === 3}
              <span class="bworkers">spawns colonist</span>
            {:else if info.type === 6}
              <span class="bworkers">WIN</span>
            {:else if info.type === 7}
              <span class="bworkers">+defense bonus</span>
            {/if}
          </button>
        {/each}
      </div>
      
      {#if hoveredBuildType !== null}
        {@const hinfo = BUILDING_INFO[hoveredBuildType]}
        {#if hinfo}
          <p class="build-desc">{hinfo.description}</p>
        {/if}
      {/if}
    {:else}
      {@const sbinfo = BUILDING_INFO[selectedBuildType]}
      <div class="build-mode-header">
        <span class="build-mode-title" style="color:{sbinfo?.color}">
          Placing: {sbinfo?.name}
        </span>
        <button class="cancel-inline" onclick={cancelBuild}>✕</button>
      </div>
      
      {#if pendingBuildSite}
        {@const preview = previewConstruct(resources, selectedBuildType, planet?.seedFull, pendingBuildSite.lon, pendingBuildSite.lat)}
        <div class="build-confirm">
          <p class="location-info">{formatLonLat(pendingBuildSite.lon, pendingBuildSite.lat)}</p>
          {#if preview.canBuild}
            <div class="terrain-badge">
              <span class="terrain-name">{preview.terrainName}</span>
              {#if preview.bonus > 0}
                <span class="terrain-bonus">+{preview.bonus}% bonus</span>
              {:else if preview.bonus === 0 && sbinfo?.maxWorkers > 0}
                <span class="terrain-neutral">no bonus</span>
              {/if}
            </div>
            {#if preview.output > 0}
              <div class="output-preview">
                <span>Output/worker/ep</span>
                <span class="output-val">{preview.output}</span>
              </div>
            {/if}
            <p class="cost-ok">
              Cost: {preview.ironCost} iron{(sbinfo?.waterCost ?? 0) > 0 ? ` + ${sbinfo.waterCost} water` : ''}{(sbinfo?.uraniumCost ?? 0) > 0 ? ` + ${sbinfo.uraniumCost} uranium` : ''}
            </p>
            <button class="primary" onclick={confirmBuild} {disabled}>
              {disabled ? 'Building…' : 'Confirm Build'}
            </button>
          {:else}
            <p class="cost-err">{preview.reason}</p>
            <button class="cancel" onclick={cancelBuild}>Cancel</button>
          {/if}
        </div>
      {:else}
        <p class="hint">Click the planet to choose a site.</p>
      {/if}
      
      {#if !pendingBuildSite || previewConstruct(resources, selectedBuildType, planet?.seedFull, pendingBuildSite?.lon, pendingBuildSite?.lat)?.canBuild}
        <button class="cancel" onclick={cancelBuild}>Cancel</button>
      {/if}
    {/if}
  </CollapsiblePanel>
{/if}

<style>

  .section {
    display: flex;
    flex-direction: column;
    gap: 0.4rem;
  }

  .hint {
    color: #667;
    font-size: 0.72rem;
    margin: 0;
    line-height: 1.4;
  }

  .location-info {
    color: #556;
    font-size: 0.7rem;
    margin: 0;
  }

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
    transition: border-color 0.15s, background 0.15s;
  }

  .build-btn:hover:not(:disabled) {
    border-color: var(--bcolor);
    background: #0e0e22;
  }

  .build-btn.affordable {
    border-color: color-mix(in srgb, var(--bcolor) 40%, #1a2030);
  }

  .build-btn.selected {
    border-color: var(--bcolor);
    background: #0e0e22;
  }

  .build-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .build-btn.locked {
    opacity: 0.5;
    border-color: #3a3a3a;
    background: #090912;
  }

  .bname-btn {
    color: var(--bcolor);
    font-size: 0.72rem;
    font-weight: bold;
  }

  .bcost {
    color: #667;
    font-size: 0.6rem;
  }

  .bworkers {
    color: #445;
    font-size: 0.58rem;
    font-style: italic;
  }

  .lock-msg {
    color: #b88;
    font-size: 0.58rem;
    font-style: italic;
  }

  .build-desc {
    font-size: 0.65rem;
    color: #667;
    margin: 0.1rem 0 0;
    line-height: 1.4;
    font-style: italic;
  }

  .build-mode-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 0.1rem;
  }

  .build-mode-title {
    font-size: 0.75rem;
    font-weight: bold;
  }

  .cancel-inline {
    background: none;
    border: none;
    color: #665;
    font-size: 0.8rem;
    cursor: pointer;
    padding: 0;
    line-height: 1;
  }

  .cancel-inline:hover {
    color: #e44;
  }

  .build-confirm {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
  }

  .terrain-badge {
    display: flex;
    align-items: center;
    gap: 0.4rem;
    background: #0a0a18;
    border: 1px solid #1a2030;
    border-radius: 3px;
    padding: 0.2rem 0.4rem;
  }

  .terrain-name {
    font-size: 0.68rem;
    color: #8aaccc;
  }

  .terrain-bonus {
    font-size: 0.6rem;
    color: #6a9a6a;
    margin-left: auto;
  }

  .terrain-neutral {
    font-size: 0.6rem;
    color: #446;
    margin-left: auto;
  }

  .terrain-ocean {
    font-size: 0.6rem;
    color: #e44;
    margin-left: auto;
  }

  .output-preview {
    display: flex;
    justify-content: space-between;
    align-items: center;
    font-size: 0.68rem;
    color: #558;
    background: #0a0a18;
    border: 1px solid #1a2030;
    border-radius: 3px;
    padding: 0.15rem 0.4rem;
  }

  .output-val {
    color: #5a8a6a;
    font-weight: bold;
  }

  .cost-ok {
    color: #7a9;
    font-size: 0.7rem;
    margin: 0;
  }

  .cost-err {
    color: #e44;
    font-size: 0.7rem;
    margin: 0;
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

  .exit-build-btn {
    background: rgba(40, 20, 10, 0.5);
    border: 1px solid #5a3a2a;
    border-radius: 4px;
    color: #cc8844;
    font-family: monospace;
    font-size: 0.75rem;
    padding: 0.4rem;
    cursor: pointer;
    width: 100%;
    transition: background 0.15s, border-color 0.15s;
  }

  .exit-build-btn:hover {
    background: rgba(50, 25, 15, 0.6);
    border-color: #7a5a3a;
  }
</style>
