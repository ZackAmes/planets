<script>
  import { onMount } from 'svelte'
  import { Canvas } from '@threlte/core'
  import PlanetView from './components/PlanetView.svelte'
  import TopBar from './components/TopBar.svelte'
  import ResourcesPanel from './components/ResourcesPanel.svelte'
  import ColonistsPanel from './components/ColonistsPanel.svelte'
  import BuildingsPanel from './components/BuildingsPanel.svelte'
  import ListsPanel from './components/ListsPanel.svelte'
  import GearPanel from './components/GearPanel.svelte'
  import InvaderPanel from './components/InvaderPanel.svelte'
  import BuildPanel from './components/BuildPanel.svelte'
  import DangerWidget from './components/DangerWidget.svelte'
  import TutorialTip from './components/TutorialTip.svelte'
  import { connect, disconnect, subscribe } from './lib/controller.js'
  import { mintGame, spawnPlanet, foundColony, constructBuilding, assignWorkers, collect, upgradeTc, upgradeBuilding, craftGear, fightInvader, waitForTx } from './lib/onchain.js'
  import { fetchDenshokanPlanets, fetchPlanet, fetchColony, fetchFullState } from './lib/contracts.js'
  import { getProvider } from './lib/contracts.js'
  import { terrainAt, terrainName, computeRates, computeThreat, attackProbability, EPOCH_SECONDS } from './lib/gameLogic.js'

  // ---------------------------------------------------------------------------
  // Wallet state
  // ---------------------------------------------------------------------------
  let account = $state(null)
  let address = $state(null)

  onMount(() => {
    return subscribe(({ account: a, address: addr }) => {
      account = a
      address = addr
    })
  })

  // ---------------------------------------------------------------------------
  // Game state — phases: 'connect' | 'mint' | 'spawn' | 'spawned' | 'founding' | 'managing' | 'won' | 'gameover'
  // ---------------------------------------------------------------------------
  let phase = $state('connect')
  let planetId = $state(null)
  let planetName = $state('')

  let planet    = $state(null)  // { seed, seedFull, population, actionCount, ... }
  let colony    = $state(null)  // { col, row, founded, tcLevel }
  let resources = $state(null)  // { water, iron, defense, lastUpdatedAt }
  let assigned  = $state(null)  // { count }
  let unassigned = $state(null) // { count }

  let pendingLocation        = $state(null)  // { col, row }
  let pendingLocationTerrain = $state(null)  // terrain type at selected colony site
  let pendingMarker          = $state(null)  // [x, y, z]
  let confirmedMarker        = $state(null)  // [x, y, z]

  let invader  = $state(null) // { active, strength, lon, lat, spawnedAt }
  let gear     = $state(null) // { weapons, armor }

  let buildings        = $state([])
  let buildMode        = $state(false)
  let selectedBuildType = $state(null)
  let pendingBuildSite  = $state(null) // { lon, lat, localPos }
  let selectedBuilding  = $state(null) // { lon, lat } - which building is selected for worker assignment

  let lastEvents = $state([])
  let txPending  = $state(false)
  let txStatus   = $state('')

  // Tutorial/tips state - persisted to localStorage
  let dismissedTips = $state(new Set())
  
  onMount(() => {
    // Load dismissed tips from localStorage
    const stored = localStorage.getItem('planets_dismissed_tips')
    if (stored) {
      try {
        const parsed = JSON.parse(stored)
        dismissedTips = new Set(parsed)
      } catch (e) {
        console.warn('Failed to parse dismissed tips:', e)
      }
    }
  })
  
  function handleDismissTip(tipId) {
    dismissedTips.add(tipId)
    // Persist to localStorage
    localStorage.setItem('planets_dismissed_tips', JSON.stringify([...dismissedTips]))
  }

  // ---------------------------------------------------------------------------
  // Wallet connect + game state restore
  // ---------------------------------------------------------------------------
  async function handleConnect() {
    const acc = await connect()
    if (!acc) return
    txPending = true
    txStatus = 'Loading your planets...'
    try {
      await restoreState(address)
    } catch (e) {
      console.warn('State restore failed:', e)
      phase = 'mint'
    } finally {
      txPending = false
      txStatus = ''
    }
  }

  async function restoreState(playerAddress) {
    const ids = await fetchDenshokanPlanets(playerAddress)
    if (ids.length === 0) { phase = 'mint'; return }

    const id = ids[ids.length - 1]
    planetId = id

    const s = await fetchFullState(id)
    if (!s) { phase = 'spawn'; return }

    planetName = s.planet.name
    setPlanetState(s.planet)

    if (s.planet.population === 0 && s.planet.actionCount > 0) { phase = 'gameover'; return }

    if (!s.colony) { phase = 'founding'; return }

    colony     = s.colony
    resources  = s.resources
    assigned   = s.assigned
    unassigned = s.unassigned
    buildings  = s.buildings
    invader    = s.invader
    gear       = s.gear
    confirmedMarker = null
    phase = buildings.some(b => b.buildingType === 6) ? 'won' : 'managing'
  }

  async function refreshColonyState(id) {
    const pid = id ?? planetId
    const s = await fetchFullState(pid)
    if (!s) return
    setPlanetState(s.planet)
    if (s.colony) colony = s.colony
    resources  = s.resources
    assigned   = s.assigned
    unassigned = s.unassigned
    buildings  = s.buildings
    invader    = s.invader
    gear       = s.gear
  }

  async function handleManualRefresh() {
    if (!planetId) return
    txPending = true
    txStatus = 'Refreshing...'
    try {
      await refreshColonyState(planetId)
      txStatus = ''
    } catch (e) {
      console.error('[handleManualRefresh] error:', e)
      txStatus = 'Error: ' + (e.message ?? String(e))
    } finally { txPending = false }
  }

  async function handleDisconnect() {
    await disconnect()
    phase = 'connect'; planetId = null; planetName = ''; planet = null
    colony = null; resources = null; assigned = null; unassigned = null
    invader = null; gear = null; confirmedMarker = null; buildings = []
  }

  // ---------------------------------------------------------------------------
  // Mint
  // ---------------------------------------------------------------------------
  async function handleMint() {
    if (!account || !planetName.trim()) return
    txPending = true
    txStatus = 'Minting planet token...'
    try {
      const { transaction_hash, tokenId } = await mintGame(account, planetName.trim())
      console.log('[mint]', transaction_hash, tokenId?.toString())
      planetId = tokenId
      txStatus = 'Token minted!'
      phase = 'spawn'
    } catch (e) {
      txStatus = 'Error: ' + (e.message ?? String(e))
    } finally { txPending = false }
  }

  // ---------------------------------------------------------------------------
  // Spawn
  // ---------------------------------------------------------------------------
  async function handleSpawn() {
    if (!account || !planetName.trim() || planetId == null) return
    txPending = true
    txStatus = 'Spawning planet...'
    try {
      await spawnPlanet(account, planetId, planetName.trim())
      await loadPlanetAfterSpawn()
    } catch (e) {
      console.error('[handleSpawn] error:', e)
      txStatus = 'Error: ' + (e.message ?? String(e))
    } finally { txPending = false }
  }

  // Polls for planet state after spawn tx — node may lag behind accepted tx.
  // If it can't find the planet after several retries, moves to 'spawned' phase
  // so the player can manually retry without re-sending the tx.
  async function loadPlanetAfterSpawn() {
    txStatus = 'Reading planet seed...'
    const delays = [1000, 2000, 3000, 5000]
    for (const delay of delays) {
      await new Promise(r => setTimeout(r, delay))
      const p = await fetchPlanet(planetId)
      if (p) {
        setPlanetState(p)
        txStatus = ''
        phase = 'founding'
        return
      }
    }
    // Tx went through but node not returning state yet — let player manually retry
    txStatus = ''
    phase = 'spawned'
  }

  async function handleRefreshAfterSpawn() {
    txPending = true
    txStatus = 'Checking planet state...'
    try {
      const p = await fetchPlanet(planetId)
      if (p) {
        setPlanetState(p)
        phase = 'founding'
      } else {
        txStatus = 'Planet not found yet — try again in a moment'
      }
    } catch (e) {
      console.error('[handleRefreshAfterSpawn] error:', e)
      txStatus = 'Error: ' + (e.message ?? String(e))
    } finally { txPending = false }
  }

  function setPlanetState(p) {
    planet = {
      seed: p.seedJs,
      seedFull: p.seed,   // BigInt felt252
      population: p.population,
      actionCount: p.actionCount,
      width: p.width,
      height: p.height,
      spawnedAt: p.spawnedAt,
      lastActionAt: p.lastActionAt,
    }
  }

  // ---------------------------------------------------------------------------
  // Building selection
  // ---------------------------------------------------------------------------
  function handleBuildingClick(lon, lat) {
    if (buildMode) return // Don't select buildings during build mode
    if (selectedBuilding && selectedBuilding.lon === lon && selectedBuilding.lat === lat) {
      // Click same building again to deselect
      selectedBuilding = null
    } else {
      selectedBuilding = { lon, lat }
    }
  }

  const selectedBuildingData = $derived(
    selectedBuilding 
      ? buildings.find(b => b.lon === selectedBuilding.lon && b.lat === selectedBuilding.lat)
      : null
  )

  // ---------------------------------------------------------------------------
  // Colony founding
  // ---------------------------------------------------------------------------
  function handleLocationPick(col, row, lon, lat, localPos) {
    pendingLocation = { col, row }
    pendingMarker = localPos
    pendingLocationTerrain = planet?.seedFull ? terrainAt(planet.seedFull, lon, lat) : null
  }

  async function handleConfirmLocation() {
    if (!pendingLocation || !account) return
    txPending = true
    txStatus = 'Founding colony...'
    try {
      const tx = await foundColony(account, planetId, pendingLocation.col, pendingLocation.row)
      await waitForTx(getProvider(), tx)
      confirmedMarker = pendingMarker
      pendingLocation = null
      pendingMarker = null
      await refreshColonyState(planetId)
      phase = buildings.some(b => b.buildingType === 6) ? 'won' : 'managing'
      txStatus = ''
    } catch (e) {
      txStatus = 'Error: ' + (e.message ?? String(e))
    } finally { txPending = false }
  }

  // ---------------------------------------------------------------------------
  // Building placement
  // ---------------------------------------------------------------------------
  function handleToggleBuildMode() {
    buildMode = !buildMode
    selectedBuilding = null // Deselect any building when entering build mode
    if (!buildMode) {
      // Exiting build mode
      selectedBuildType = null
      pendingBuildSite = null
    }
  }
  
  function handleBuildMode(type) {
    if (type === null) { 
      selectedBuildType = null
      pendingBuildSite = null
    } else { 
      selectedBuildType = type
      pendingBuildSite = null
    }
  }

  function handleBuildPick(lon, lat, localPos) {
    pendingBuildSite = { lon, lat, localPos }
  }

  async function handleConfirmBuild(lon, lat, type) {
    if (!account) return
    txPending = true
    txStatus = 'Constructing building...'
    try {
      const tx = await constructBuilding(account, planetId, lon, lat, type)
      console.log('[construct_building]', tx, { lon, lat, type })
      await waitForTx(getProvider(), tx)
      await refreshColonyState(planetId)
      selectedBuildType = null
      pendingBuildSite = null
      if (type === 6) phase = 'won'
      txStatus = ''
    } catch (e) {
      txStatus = 'Error: ' + (e.message ?? String(e))
    } finally { txPending = false }
  }

  // ---------------------------------------------------------------------------
  // Upgrade building
  // ---------------------------------------------------------------------------
  async function handleUpgradeBuilding(lon, lat) {
    if (!account) return
    txPending = true
    txStatus = 'Upgrading building...'
    try {
      await upgradeBuilding(account, planetId, lon, lat)
      await refreshColonyState(planetId)
      txStatus = ''
    } catch (e) {
      txStatus = 'Error: ' + (e.message ?? String(e))
    } finally { txPending = false }
  }

  // ---------------------------------------------------------------------------
  // Worker assignment
  // ---------------------------------------------------------------------------
  async function handleAssignWorkers(lon, lat, workers) {
    if (!account) return
    txPending = true
    txStatus = 'Assigning workers...'
    try {
      await assignWorkers(account, planetId, lon, lat, workers)
      await refreshColonyState(planetId)
      txStatus = ''
    } catch (e) {
      txStatus = 'Error: ' + (e.message ?? String(e))
    } finally { txPending = false }
  }

  // ---------------------------------------------------------------------------
  // Upgrade TC
  // ---------------------------------------------------------------------------
  async function handleUpgradeTc() {
    if (!account) return
    txPending = true
    txStatus = 'Upgrading Town Center...'
    try {
      await upgradeTc(account, planetId)
      await refreshColonyState(planetId)
      txStatus = ''
    } catch (e) {
      txStatus = 'Error: ' + (e.message ?? String(e))
    } finally { txPending = false }
  }

  // ---------------------------------------------------------------------------
  // Craft gear
  // ---------------------------------------------------------------------------
  async function handleCraftGear(weapons, armor) {
    if (!account) return
    txPending = true
    txStatus = 'Crafting gear...'
    try {
      await craftGear(account, planetId, weapons, armor)
      await refreshColonyState(planetId)
      txStatus = ''
    } catch (e) {
      txStatus = 'Error: ' + (e.message ?? String(e))
    } finally { txPending = false }
  }

  // ---------------------------------------------------------------------------
  // Fight invader
  // ---------------------------------------------------------------------------
  async function handleFightInvader(colonists, weapons, armor) {
    if (!account) return
    txPending = true
    txStatus = 'Sending fighters...'
    try {
      await fightInvader(account, planetId, colonists, weapons, armor)
      await refreshColonyState(planetId)
      if (planet?.population === 0) phase = 'gameover'
      txStatus = ''
    } catch (e) {
      txStatus = 'Error: ' + (e.message ?? String(e))
    } finally { txPending = false }
  }

  // ---------------------------------------------------------------------------
  // Collect (tick)
  // ---------------------------------------------------------------------------
  async function handleCollect() {
    if (!account) return
    txPending = true
    txStatus = 'Collecting resources...'
    try {
      await collect(account, planetId)
      await refreshColonyState(planetId)
      if (planet?.population === 0) phase = 'gameover'
      txStatus = ''
    } catch (e) {
      txStatus = 'Error: ' + (e.message ?? String(e))
    } finally { txPending = false }
  }

  // ---------------------------------------------------------------------------
  // Periodic state polling — refresh every 30s when managing
  // ---------------------------------------------------------------------------
  $effect(() => {
    if (phase !== 'managing' || !planetId) return
    const id = setInterval(async () => {
      if (txPending) return
      const p = await fetchPlanet(planetId)
      if (p) setPlanetState(p)
      await refreshColonyState(planetId)
    }, 30_000)
    return () => clearInterval(id)
  })

  // ---------------------------------------------------------------------------
  // Derived state for UI components
  // ---------------------------------------------------------------------------
  let nowSeconds = $state(Math.floor(Date.now() / 1000))
  $effect(() => {
    const id = setInterval(() => { nowSeconds = Math.floor(Date.now() / 1000) }, 1000)
    return () => clearInterval(id)
  })

  const tcLevel = $derived(colony?.tcLevel ?? 1)
  const rates = $derived(computeRates(buildings ?? [], planet?.population ?? 0))
  
  const epochProgress = $derived((() => {
    const ref = planet?.lastActionAt ?? 0
    if (!ref) return 0
    return Math.min(1, (nowSeconds - ref) / EPOCH_SECONDS)
  })())

  const epochCountdown = $derived.by(() => {
    const ref = planet?.lastActionAt ?? 0
    if (!ref) return '--:--'
    const remaining = Math.max(0, EPOCH_SECONDS - (nowSeconds - ref))
    if (remaining === 0) return 'READY'
    const m = Math.floor(remaining / 60)
    const s = remaining % 60
    return `${m}:${s.toString().padStart(2, '0')}`
  })
  
  const epochsElapsed = $derived.by(() => {
    const ref = planet?.lastActionAt ?? 0
    if (!ref) return 0
    return Math.floor((nowSeconds - ref) / EPOCH_SECONDS)
  })

  const threat = $derived(
    (planet && resources) ? computeThreat(planet, resources, nowSeconds) : 0
  )
  const attackProb = $derived(attackProbability(threat))
  
  // Calculate time since colony founding
  const timeSinceFounding = $derived.by(() => {
    if (!planet?.spawnedAt) return '--:--:--'
    const elapsed = nowSeconds - planet.spawnedAt
    const hours = Math.floor(elapsed / 3600)
    const minutes = Math.floor((elapsed % 3600) / 60)
    const seconds = elapsed % 60
    return `${hours}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`
  })
  
  const hasWorkshop = $derived(buildings.some(b => b.buildingType === 7))
  const populationAtCap = $derived(
    planet && (planet.population >= tcLevel * 10)
  )

  const DEV_SEED = 987654321
  const displaySeed = $derived(planet?.seed ?? DEV_SEED)
</script>

<div class="root">
  <Canvas>
    <PlanetView
      seed={displaySeed}
      seedFull={planet?.seedFull ?? null}
      canPick={phase === 'founding' && !txPending}
      canBuild={phase === 'managing' && buildMode && !txPending}
      colonyMarker={phase === 'managing' || phase === 'gameover'
        ? confirmedMarker
        : pendingMarker}
      {buildings}
      {invader}
      {selectedBuilding}
      onlocationpick={handleLocationPick}
      onbuildpick={handleBuildPick}
      onbuildingclick={handleBuildingClick}
    />
  </Canvas>

  <div class="ui">
    <div class="header">
      <span class="planet-label">PLANETS</span>
      {#if planetName && (phase === 'managing' || phase === 'founding' || phase === 'won' || phase === 'gameover')}
        <span class="planet-name-hdr">{planetName}</span>
      {/if}
      {#if address}
        <span class="addr">{address.slice(0, 6)}…{address.slice(-4)}</span>
        {#if planet && (phase === 'managing' || phase === 'founding')}
          <button class="btn-sm" onclick={handleManualRefresh} disabled={txPending} title="Refresh state">⟳</button>
        {/if}
        <button class="btn-sm" onclick={handleDisconnect}>×</button>
      {/if}
    </div>

    {#if planet && (phase === 'managing' || phase === 'founding')}
        <TopBar
          {resources}
          {planet}
          {buildings}
          {timeSinceFounding}
          {epochProgress}
          {epochCountdown}
          {epochsElapsed}
          oncollect={handleCollect}
          disabled={txPending}
        />
    {/if}

    {#if planet && (phase === 'founding' || phase === 'managing')}
      <TutorialTip
        {phase}
        {planet}
        {resources}
        {buildings}
        {threat}
        invaderActive={invader?.active ?? false}
        {hasWorkshop}
        {tcLevel}
        {populationAtCap}
        onDismiss={handleDismissTip}
      />
    {/if}

    {#if txStatus}
      <div class="status" class:error={txStatus.startsWith('Error')}>
        {txStatus}
      </div>
    {/if}

    {#if phase === 'connect'}
      <div class="card center">
        <h2>PLANETS</h2>
        <p>An onchain colony builder.</p>
        <button class="btn-primary" onclick={handleConnect}>Connect Wallet</button>
      </div>

    {:else if phase === 'mint'}
      <div class="card">
        <h2>Name Your Planet</h2>
        <input class="name-input" type="text" placeholder="Planet name…" maxlength="31"
          bind:value={planetName} onkeydown={(e) => e.key === 'Enter' && handleMint()} />
        <button class="btn-primary" onclick={handleMint} disabled={txPending || !planetName.trim()}>
          {txPending ? 'Minting…' : 'Mint Planet Token'}
        </button>
      </div>

    {:else if phase === 'spawn'}
      <div class="card">
        <h2>Settle Your World</h2>
        <p class="dim">Token #{planetId?.toString()} ready.</p>
        <input class="name-input" bind:value={planetName} placeholder="Planet name" maxlength="31" />
        <button class="btn-primary" onclick={handleSpawn} disabled={txPending || !planetName.trim()}>
          {txPending ? 'Spawning…' : 'Spawn Planet'}
        </button>
      </div>

    {:else if phase === 'spawned'}
      <div class="card">
        <h2>Planet Spawned</h2>
        <p class="dim">Tx confirmed. Waiting for node to reflect state.</p>
        <button class="btn-primary" onclick={handleRefreshAfterSpawn} disabled={txPending}>
          {txPending ? 'Checking…' : 'Check Planet State'}
        </button>
      </div>

    {:else if planet}
      {#if phase === 'founding'}
        <BuildPanel
          {phase}
          {resources}
          {planet}
          {tcLevel}
          {buildMode}
          {pendingBuildSite}
          {pendingLocation}
          {pendingLocationTerrain}
          onbuildmode={handleBuildMode}
          onbuild={handleConfirmBuild}
          onconfirm={handleConfirmLocation}
          disabled={txPending}
        />
      {:else if phase === 'managing'}
        <DangerWidget
          {threat}
          {attackProb}
          invaderActive={invader?.active ?? false}
          defenseRemaining={resources?.defense}
          cannonCoverage={rates.cannonDamageRate}
        />

        <ColonistsPanel
          {assigned}
          {unassigned}
          {resources}
          {tcLevel}
          onupgradetc={handleUpgradeTc}
          disabled={txPending}
        />

        <InvaderPanel
          {invader}
          {unassigned}
          {gear}
          {resources}
          cannonDamageRate={rates.cannonDamageRate}
          onfight={handleFightInvader}
          disabled={txPending}
        />

        {#if selectedBuildingData?.buildingType === 7}
          <GearPanel
            {gear}
            {resources}
            {buildings}
            oncraftgear={handleCraftGear}
            disabled={txPending}
          />
        {/if}

        {#if !buildMode}
          <button class="build-mode-btn" onclick={handleToggleBuildMode} disabled={txPending}>
            Enter Build Mode
          </button>
        {:else}
          <BuildPanel
            {phase}
            {resources}
            {planet}
            {tcLevel}
            {buildMode}
            {pendingBuildSite}
            {pendingLocation}
            {pendingLocationTerrain}
            onbuildmode={handleBuildMode}
            onbuild={handleConfirmBuild}
            onconfirm={handleConfirmLocation}
            onexit={handleToggleBuildMode}
            disabled={txPending}
          />
        {/if}
      {:else if phase === 'won'}
        <div class="end-panel">
          <h2 class="won-title">LAUNCHED!</h2>
          <p class="hint">Your colony has reached the stars.</p>
          <p class="dim">Survived {planet.actionCount} turns.</p>
          <p class="dim" style="color:#bb44ff">Population: {planet.population}</p>
        </div>
      {:else if phase === 'gameover'}
        <div class="end-panel">
          <h2>Colony Lost</h2>
          <p class="hint">Your colonists are gone.</p>
          <p class="dim">Survived {planet.actionCount} turns.</p>
        </div>
      {/if}
    {/if}
  </div>

  <!-- Left side panels -->
  {#if phase === 'managing' && planet}
    <div class="ui-left">
      {#if selectedBuildingData}
        <BuildingsPanel
          building={selectedBuildingData}
          {resources}
          {tcLevel}
          onassign={handleAssignWorkers}
          onupgradebuilding={handleUpgradeBuilding}
          ondeselect={() => selectedBuilding = null}
          disabled={txPending}
        />
      {/if}

      <ListsPanel
        {buildings}
        colonists={{ assigned, unassigned }}
        onbuildingselect={handleBuildingClick}
      />
    </div>
  {/if}
</div>

<style>
  .root {
    width: 100vw;
    height: 100vh;
    position: relative;
    background: #050510;
  }

  .ui {
    position: absolute;
    top: 5rem;
    right: 1rem;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    pointer-events: all;
    max-width: 280px;
    max-height: calc(100vh - 6rem);
    overflow-y: auto;
    padding-right: 0.25rem;
    z-index: 10;
  }

  .ui-left {
    position: absolute;
    top: 1rem;
    left: 1rem;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    pointer-events: all;
    max-width: 280px;
    max-height: calc(100vh - 2rem);
    overflow-y: auto;
    padding-right: 0.25rem;
    z-index: 10;
  }

  .ui::-webkit-scrollbar,
  .ui-left::-webkit-scrollbar {
    width: 6px;
  }

  .ui::-webkit-scrollbar-track,
  .ui-left::-webkit-scrollbar-track {
    background: rgba(10, 10, 20, 0.3);
    border-radius: 3px;
  }

  .ui::-webkit-scrollbar-thumb,
  .ui-left::-webkit-scrollbar-thumb {
    background: rgba(100, 120, 140, 0.5);
    border-radius: 3px;
  }

  .ui::-webkit-scrollbar-thumb:hover,
  .ui-left::-webkit-scrollbar-thumb:hover {
    background: rgba(100, 120, 140, 0.7);
  }

  .header {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    background: rgba(5, 5, 20, 0.85);
    border: 1px solid #1a2a3a;
    border-radius: 6px;
    padding: 0.35rem 0.75rem;
    font-family: monospace;
    font-size: 0.72rem;
  }

  .planet-label { color: #445566; letter-spacing: 0.12em; }
  .planet-name-hdr { color: #6ab4ff; font-size: 0.7rem; flex: 1; text-align: center; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 90px; letter-spacing: 0.05em; }
  .addr { color: #445566; font-size: 0.65rem; }

  .status {
    background: rgba(20, 40, 20, 0.9);
    border: 1px solid #2a5a3a;
    border-radius: 6px;
    padding: 0.4rem 0.75rem;
    font-family: monospace;
    font-size: 0.72rem;
    color: #6aff9a;
  }

  .status.error { background: rgba(40, 10, 10, 0.9); border-color: #5a2a2a; color: #ff6a6a; }

  .card {
    background: rgba(5, 5, 20, 0.9);
    border: 1px solid #1a2a3a;
    border-radius: 8px;
    padding: 1.25rem;
    font-family: monospace;
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .card.center { align-items: center; text-align: center; }
  .card h2 { font-size: 1.1rem; color: #8ecfff; letter-spacing: 0.15em; margin: 0; }
  .card p { color: #667; font-size: 0.8rem; margin: 0; }
  .dim { color: #556; font-size: 0.75rem; }

  .name-input {
    background: #0a0a1a;
    border: 1px solid #1a3a5a;
    border-radius: 4px;
    color: #cce;
    font-family: monospace;
    font-size: 0.85rem;
    padding: 0.45rem 0.6rem;
    width: 100%;
    box-sizing: border-box;
  }

  .name-input:focus { outline: none; border-color: #2a6aaa; }

  .btn-primary {
    background: #1a3a5a;
    border: 1px solid #2a5a8a;
    border-radius: 6px;
    color: #8ecfff;
    font-family: monospace;
    font-size: 0.85rem;
    padding: 0.6rem 1rem;
    cursor: pointer;
    width: 100%;
    transition: background 0.15s;
  }

  .btn-primary:hover:not(:disabled) { background: #1f4a72; }
  .btn-primary:disabled { opacity: 0.4; cursor: not-allowed; }

  .btn-sm {
    background: none;
    border: 1px solid #1a2a3a;
    border-radius: 4px;
    color: #446;
    font-family: monospace;
    font-size: 0.65rem;
    padding: 0.15rem 0.4rem;
    cursor: pointer;
  }

  .btn-sm:hover { color: #6ab4ff; border-color: #2a4a6a; }

  .end-panel {
    background: rgba(5, 5, 20, 0.9);
    border: 1px solid #1a2a3a;
    border-radius: 8px;
    padding: 1.25rem;
    font-family: monospace;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    align-items: center;
    text-align: center;
  }

  .end-panel h2 {
    font-size: 1rem;
    color: #8ecfff;
    letter-spacing: 0.12em;
    margin: 0;
  }

  .end-panel .won-title {
    font-size: 1.1rem;
    color: #bb44ff;
    text-transform: uppercase;
    letter-spacing: 0.15em;
  }

  .end-panel .hint {
    color: #667;
    font-size: 0.75rem;
    margin: 0;
  }

  .end-panel .dim {
    color: #556;
    font-size: 0.7rem;
    margin: 0;
  }

  .build-mode-btn {
    background: #1a2a4a;
    border: 1px solid #2a4a6a;
    border-radius: 6px;
    color: #6ab4ff;
    font-family: monospace;
    font-size: 0.8rem;
    padding: 0.5rem 1rem;
    cursor: pointer;
    width: 100%;
    transition: background 0.15s;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .build-mode-btn:hover:not(:disabled) {
    background: #1f3a6a;
  }

  .build-mode-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }
</style>
