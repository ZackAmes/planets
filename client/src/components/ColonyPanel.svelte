<script>
  import { BUILDING_INFO, previewConstruct, formatLonLat, previewFight, computeRates,
           WEAPON_COST, ARMOR_COST, tcUpgradeCost, upgradeBuildingCost,
           EPOCH_SECONDS, computeThreat, attackProbability, terrainName } from '../lib/gameLogic.js'

  let {
    phase,
    planet,
    colony,
    resources,
    assigned,
    unassigned,
    invader,
    gear,
    buildings,
    pendingLocation,
    lastEvents,
    disabled = false,
    buildMode = false,
    pendingBuildSite = null,
    onconfirm,
    oncollect,
    onassign,
    onupgradetc,
    onupgradebuilding,
    oncraftgear,
    onfight,
    onbuildmode,
    onbuild,
  } = $props()

  // Derived production rates
  const rates = $derived(computeRates(buildings ?? [], planet?.population ?? 0))

  // TC upgrade
  const tcLevel = $derived(colony?.tcLevel ?? 1)
  const tcCost = $derived(tcUpgradeCost(tcLevel))
  const canUpgradeTc = $derived(
    tcLevel < 5 &&
    (resources?.iron ?? 0) >= tcCost.iron &&
    (resources?.uranium ?? 0) >= tcCost.uranium
  )

  // Gear crafting draft
  let craftWeapons = $state(1)
  let craftArmor   = $state(0)
  const craftIronCost = $derived(craftWeapons * WEAPON_COST + craftArmor * ARMOR_COST)
  const canCraftAfford = $derived((resources?.iron ?? 0) >= craftIronCost && craftIronCost > 0)

  // Fight draft
  let fightColonists = $state(1)
  let fightWeapons   = $state(0)
  let fightArmor     = $state(0)
  const fightPreview = $derived(
    invader?.active
      ? previewFight(invader, fightColonists, fightWeapons, fightArmor)
      : null
  )
  const canFight = $derived(
    invader?.active &&
    fightColonists > 0 &&
    fightColonists <= (unassigned?.count ?? 0) &&
    fightWeapons <= (gear?.weapons ?? 0) &&
    fightArmor <= (gear?.armor ?? 0)
  )

  let selectedBuildType = $state(null)

  // Live clock for epoch countdown and threat
  let nowSeconds = $state(Math.floor(Date.now() / 1000))
  $effect(() => {
    const id = setInterval(() => { nowSeconds = Math.floor(Date.now() / 1000) }, 1000)
    return () => clearInterval(id)
  })

  const epochProgress = $derived((() => {
    const ref = planet?.lastActionAt ?? 0
    if (!ref) return 0
    return Math.min(1, (nowSeconds - ref) / EPOCH_SECONDS)
  })())

  const epochCountdown = $derived((() => {
    const ref = planet?.lastActionAt ?? 0
    if (!ref) return '--:--'
    const remaining = Math.max(0, EPOCH_SECONDS - (nowSeconds - ref))
    if (remaining === 0) return 'READY'
    const m = Math.floor(remaining / 60)
    const s = remaining % 60
    return `${m}:${s.toString().padStart(2, '0')}`
  })())

  const threat = $derived(
    (planet && resources) ? computeThreat(planet, resources, nowSeconds) : 0
  )
  const attackProb = $derived(attackProbability(threat))

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

  // Buildable types (exclude TownCenter), filtered by TC level
  const buildableTypes = $derived(
    BUILDING_INFO.filter(i => i.type !== 0 && i.minTcLevel <= tcLevel)
  )
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
        <span class="rate" class:negative={rates.netWater < 0}>{rates.netWater >= 0 ? '+' : ''}{rates.netWater}/ep</span>
      </div>
      <div class="stat">
        <span class="label">Iron</span>
        <span class="value gray">{resources?.iron ?? 0}</span>
        <span class="rate positive">+{rates.ironRate}/ep</span>
      </div>
      <div class="stat">
        <span class="label">Defense</span>
        <span class="value green">{resources?.defense ?? 0}</span>
        <span class="rate positive">+{rates.defenseRate}/ep</span>
      </div>
      <div class="stat">
        <span class="label">Uranium</span>
        <span class="value purple">{resources?.uranium ?? 0}</span>
        <span class="rate" class:positive={rates.uraniumRate > 0}>+{rates.uraniumRate}/ep</span>
      </div>
      <div class="stat">
        <span class="label">Pop / Cap</span>
        <span class="value">{planet?.population ?? 0} / {tcLevel * 10}</span>
        <span class="rate dim">TC lv{tcLevel}</span>
      </div>
    </div>

    <!-- TC upgrade -->
    <button class="tc-btn" onclick={onupgradetc}
      disabled={!canUpgradeTc || disabled || tcLevel >= 5}>
      {#if tcLevel >= 5}
        TC Max Level
      {:else}
        Upgrade TC lv{tcLevel}→{tcLevel + 1} ({tcCost.iron} iron{tcCost.uranium > 0 ? ` + ${tcCost.uranium} U` : ''})
      {/if}
    </button>

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

    <div class="epoch-wrap">
      <div class="epoch-track">
        <div class="epoch-fill" style="width:{epochProgress * 100}%" class:ready={epochProgress >= 1}></div>
      </div>
      <span class="epoch-label" class:ready={epochProgress >= 1}>{epochCountdown}</span>
    </div>

    <button class="collect-btn" onclick={oncollect} {disabled}>
      {disabled ? 'Working…' : 'Collect Resources'}
    </button>

    <!-- Threat gauge -->
    {#if threat > 0}
      <div class="threat-row">
        <span class="threat-label">Threat</span>
        <div class="threat-track">
          <div class="threat-fill"
            style="width:{threat}%; background:{threat < 33 ? '#3a9a6a' : threat < 66 ? '#c8901a' : '#e04444'}">
          </div>
        </div>
        <span class="threat-pct" style="color:{threat < 33 ? '#5ab' : threat < 66 ? '#ca8' : '#e66'}">{threat}% · {attackProb}% atk</span>
      </div>
    {/if}

    <!-- Invader alert -->
    {#if invader?.active}
      <div class="invader-panel">
        <h3 class="threat-title">INVADERS!</h3>
        <p class="dim">Strength: {invader.strength} · draining {Math.max(1, Math.floor(invader.strength / 10))}/epoch</p>
        <div class="fight-row">
          <span class="fight-label">Colonists</span>
          <button class="adj" onclick={() => fightColonists = Math.max(1, fightColonists - 1)} disabled={disabled}>-</button>
          <span class="wcount">{fightColonists}</span>
          <button class="adj" onclick={() => fightColonists = Math.min(unassigned?.count ?? 0, fightColonists + 1)} disabled={disabled}>+</button>
        </div>
        <div class="fight-row">
          <span class="fight-label">Weapons</span>
          <button class="adj" onclick={() => fightWeapons = Math.max(0, fightWeapons - 1)} disabled={disabled}>-</button>
          <span class="wcount">{fightWeapons}/{gear?.weapons ?? 0}</span>
          <button class="adj" onclick={() => fightWeapons = Math.min(gear?.weapons ?? 0, fightWeapons + 1)} disabled={disabled}>+</button>
        </div>
        <div class="fight-row">
          <span class="fight-label">Armor</span>
          <button class="adj" onclick={() => fightArmor = Math.max(0, fightArmor - 1)} disabled={disabled}>-</button>
          <span class="wcount">{fightArmor}/{gear?.armor ?? 0}</span>
          <button class="adj" onclick={() => fightArmor = Math.min(gear?.armor ?? 0, fightArmor + 1)} disabled={disabled}>+</button>
        </div>
        {#if fightPreview}
          <p class="fight-preview" class:win={fightPreview.willWin} class:lose={!fightPreview.willWin}>
            Power ~{fightPreview.fighterPower} (±25%) vs {fightPreview.invaderStrength}
            · ~{fightPreview.estimatedCasualties} casualties
            · {fightPreview.willWin ? 'LIKELY WIN' : 'LIKELY LOSE'}
          </p>
        {/if}
        <button class="fight-btn" onclick={() => onfight?.(fightColonists, fightWeapons, fightArmor)}
          disabled={!canFight || disabled}>
          {disabled ? 'Fighting…' : 'Send Fighters'}
        </button>
      </div>
    {/if}

    <!-- Worker assignment -->
    {#if workerBuildings.length > 0}
      <div class="divider"></div>
      <h3>Workers</h3>
      {#each workerBuildings as b}
        {@const info = BUILDING_INFO[b.buildingType]}
        {@const bLevel = b.level ?? 1}
        {@const upCost = upgradeBuildingCost(bLevel)}
        {@const canUpgrade = bLevel < tcLevel && (resources?.iron ?? 0) >= upCost.iron && (resources?.uranium ?? 0) >= upCost.uranium}
        {@const totalOutput = (b.workers ?? 0) * (b.outputPerWorkerEpoch ?? 0)}
        <div class="worker-row">
          <div class="brow-header">
            <span class="bname" style="color:{info?.color}">{info?.name ?? '?'}</span>
            <span class="blevel dim">lv{bLevel}</span>
            {#if bLevel < 5}
              <button class="upgrade-btn" onclick={() => onupgradebuilding?.(b.lon, b.lat)}
                disabled={!canUpgrade || disabled} title="Upgrade ({upCost.iron} iron{upCost.uranium > 0 ? ` + ${upCost.uranium} U` : ''})">
                +lv
              </button>
            {/if}
          </div>
          <div class="brow-meta">
            <span class="coords dim">{formatLonLat(b.lon, b.lat)}</span>
            {#if totalOutput > 0}
              <span class="output-tag">+{totalOutput} {info?.resource}/ep</span>
            {/if}
          </div>
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

    <!-- Gear crafting -->
    <div class="divider"></div>
    <h3>Gear — <span class="gear-stock">W:{gear?.weapons ?? 0} A:{gear?.armor ?? 0}</span></h3>
    <div class="craft-row">
      <span class="craft-label">Weapons ({WEAPON_COST} iron)</span>
      <button class="adj" onclick={() => craftWeapons = Math.max(0, craftWeapons - 1)} {disabled}>-</button>
      <span class="wcount">{craftWeapons}</span>
      <button class="adj" onclick={() => craftWeapons++} {disabled}>+</button>
    </div>
    <div class="craft-row">
      <span class="craft-label">Armor ({ARMOR_COST} iron)</span>
      <button class="adj" onclick={() => craftArmor = Math.max(0, craftArmor - 1)} {disabled}>-</button>
      <span class="wcount">{craftArmor}</span>
      <button class="adj" onclick={() => craftArmor++} {disabled}>+</button>
    </div>
    <button class="craft-btn" onclick={() => oncraftgear?.(craftWeapons, craftArmor)}
      disabled={!canCraftAfford || disabled}>
      Craft ({craftIronCost} iron)
    </button>

    <!-- Build section -->
    <div class="divider"></div>
    {#if !buildMode}
      <h3>Build</h3>
      <div class="build-grid">
        {#each buildableTypes as info}
          {@const canAfford = (resources?.iron ?? 0) >= info.ironCost && (resources?.water ?? 0) >= info.waterCost}
          <button
            class="build-btn"
            class:affordable={canAfford}
            style="--bcolor:{info.color}"
            onclick={() => startBuild(info.type)}
            {disabled}
          >
            <span class="bname-btn">{info.name}</span>
            <span class="bcost">
              {info.ironCost}⛏{info.waterCost > 0 ? ` + ${info.waterCost}💧` : ''}
            </span>
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
            {@const binfo = BUILDING_INFO[selectedBuildType]}
            <div class="terrain-badge">
              <span class="terrain-name">{preview.terrainName}</span>
              {#if preview.bonus > 0}
                <span class="terrain-bonus">+{preview.bonus}% bonus</span>
              {/if}
            </div>
            <p class="cost-ok">Cost: {preview.ironCost} iron{(binfo?.waterCost ?? 0) > 0 ? ` + ${binfo.waterCost} water` : ''}{(binfo?.uraniumCost ?? 0) > 0 ? ` + ${binfo.uraniumCost} uranium` : ''}{preview.output > 0 ? ` · +${preview.output}/w/ep` : binfo?.type === 3 ? ' · spawns 1 colonist' : ' · win condition'}</p>
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

  {:else if phase === 'won'}
    <h2 class="won-title">LAUNCHED!</h2>
    <p class="hint">Your colony has reached the stars.</p>
    <p class="dim">Survived {planet?.actionCount ?? 0} turns.</p>
    <p class="dim" style="color:#bb44ff">Population: {planet?.population ?? 0}</p>

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
  .value.purple { color: #bb44ff; }
  .rate { font-size: 0.6rem; color: #556; }
  .rate.positive { color: #5a9; }
  .rate.negative { color: #e55; }
  .rate.dim { color: #446; }

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

  .tc-btn {
    background: #2a2a10;
    border: 1px solid #5a5a20;
    border-radius: 6px;
    color: #ffdd44;
    font-family: monospace;
    font-size: 0.72rem;
    padding: 0.4rem;
    cursor: pointer;
    width: 100%;
    transition: background 0.15s;
  }

  .tc-btn:hover:not(:disabled) { background: #3a3a18; }
  .tc-btn:disabled { opacity: 0.4; cursor: not-allowed; }

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

  .brow-header { display: flex; align-items: center; gap: 0.3rem; }
  .blevel { font-size: 0.62rem; }
  .bname { font-size: 0.72rem; font-weight: bold; }

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
  .upgrade-btn:hover:not(:disabled) { background: #253525; }
  .upgrade-btn:disabled { opacity: 0.3; cursor: not-allowed; }

  .won-title { font-size: 1.1rem; color: #bb44ff; text-transform: uppercase; letter-spacing: 0.15em; margin: 0; }

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

  /* Invader */
  .invader-panel {
    background: rgba(40, 10, 10, 0.7);
    border: 1px solid #6a1a1a;
    border-radius: 6px;
    padding: 0.5rem;
    display: flex;
    flex-direction: column;
    gap: 0.3rem;
  }

  .threat-title { font-size: 0.8rem; color: #ff5555; text-transform: uppercase; letter-spacing: 0.12em; margin: 0; }

  .fight-row, .craft-row {
    display: flex;
    align-items: center;
    gap: 0.3rem;
  }

  .fight-label, .craft-label { color: #889; font-size: 0.68rem; flex: 1; }

  .fight-preview {
    font-size: 0.68rem;
    margin: 0;
    padding: 0.2rem 0.3rem;
    border-radius: 3px;
    background: #0a0a18;
  }

  .fight-preview.win { color: #6aff9a; }
  .fight-preview.lose { color: #ff6a6a; }

  .fight-btn {
    background: #3a1a1a;
    border: 1px solid #6a2a2a;
    border-radius: 5px;
    color: #ff8888;
    font-family: monospace;
    font-size: 0.75rem;
    padding: 0.35rem;
    cursor: pointer;
    width: 100%;
  }

  .fight-btn:hover:not(:disabled) { background: #4a2020; }
  .fight-btn:disabled { opacity: 0.4; cursor: not-allowed; }

  /* Epoch countdown bar */
  .epoch-wrap {
    display: flex;
    align-items: center;
    gap: 0.4rem;
  }
  .epoch-track {
    flex: 1;
    height: 10px;
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
  .epoch-fill.ready { background: #2a8a5a; }
  .epoch-label {
    font-size: 0.62rem;
    color: #557;
    min-width: 36px;
    text-align: right;
    font-variant-numeric: tabular-nums;
  }
  .epoch-label.ready { color: #6aff9a; }

  /* Threat gauge */
  .threat-row {
    display: flex;
    align-items: center;
    gap: 0.35rem;
  }
  .threat-label { font-size: 0.6rem; color: #556; min-width: 36px; }
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
  .threat-pct { font-size: 0.58rem; min-width: 72px; text-align: right; }

  /* Building output tag */
  .brow-meta {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  .output-tag { font-size: 0.6rem; color: #5a8a6a; }

  /* Terrain badge in build confirm */
  .terrain-badge {
    display: flex;
    align-items: center;
    gap: 0.4rem;
    background: #0a0a18;
    border: 1px solid #1a2030;
    border-radius: 3px;
    padding: 0.2rem 0.4rem;
  }
  .terrain-name { font-size: 0.68rem; color: #8aaccc; }
  .terrain-bonus { font-size: 0.6rem; color: #6a9a6a; margin-left: auto; }

  /* Gear */
  .gear-stock { color: #aac; font-size: 0.68rem; font-weight: normal; }

  .craft-btn {
    background: #1a2a1a;
    border: 1px solid #2a5a2a;
    border-radius: 5px;
    color: #88cc88;
    font-family: monospace;
    font-size: 0.72rem;
    padding: 0.3rem;
    cursor: pointer;
    width: 100%;
  }

  .craft-btn:hover:not(:disabled) { background: #203520; }
  .craft-btn:disabled { opacity: 0.4; cursor: not-allowed; }
</style>
