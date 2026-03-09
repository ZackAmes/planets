<script>
  import { onMount } from 'svelte'
  import { Canvas } from '@threlte/core'
  import PlanetView from './components/PlanetView.svelte'
  import TopBar from './components/TopBar.svelte'
  import ResourcesPanel from './components/ResourcesPanel.svelte'
  import ColonistsPanel from './components/ColonistsPanel.svelte'
  import BuildingsPanel from './components/BuildingsPanel.svelte'
  import ListsPanel from './components/ListsPanel.svelte'
  import InvaderPanel from './components/InvaderPanel.svelte'
  import BuildPanel from './components/BuildPanel.svelte'
  import DangerWidget from './components/DangerWidget.svelte'
  import TutorialTip from './components/TutorialTip.svelte'
  import { connect, disconnect, subscribe } from './lib/controller.js'
  import { mintGame, spawnPlanet, foundColony, constructBuilding, assignWorkers, collect, upgradeTc, upgradeBuilding, fightInvader, waitForTx } from './lib/onchain.js'
  import { fetchDenshokanPlanets, fetchPlanet, fetchColony, fetchFullState } from './lib/contracts.js'
  import { getProvider } from './lib/contracts.js'
  import { terrainAt, computeRates, computeThreat, attackProbability, EPOCH_SECONDS } from './lib/gameLogic.js'

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
    // Reassign so Svelte reactivity updates immediately.
    dismissedTips = new Set([...dismissedTips, tipId])
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

  function isPlanetFinished(s) {
    if (!s) return false
    const isDead = s.planet.population === 0 && s.planet.actionCount > 0
    const hasSpaceport = s.buildings.some(b => b.buildingType === 6)
    return isDead || hasSpaceport
  }

  async function restoreState(playerAddress) {
    const ids = await fetchDenshokanPlanets(playerAddress)
    if (ids.length === 0) { phase = 'mint'; return }

    // Scan newest-first for an active (unfinished) planet
    for (let i = ids.length - 1; i >= 0; i--) {
      const id = ids[i]
      const s = await fetchFullState(id)
      if (!s) {
        // Not yet spawned — offer spawn
        planetId = id
        phase = 'spawn'
        return
      }
      if (isPlanetFinished(s)) continue

      // Found an active planet
      planetId = id
      planetName = s.planet.name
      applyState(s)
      confirmedMarker = null
      if (!s.colony) { phase = 'founding'; return }
      phase = 'managing'
      return
    }

    // All planets are finished — let them mint a fresh one
    phase = 'mint'
  }

  async function refreshColonyState(id) {
    const pid = id ?? planetId
    const s = await fetchFullState(pid)
    if (!s) return
    applyState(s)
  }

  function applyState(s) {
    setPlanetState(s.planet)
    if (s.colony) colony = s.colony
    resources  = s.resources
    assigned   = s.assigned
    unassigned = s.unassigned
    buildings  = s.buildings
    invader    = s.invader
  }

  /**
   * Poll fetchFullState until `until(state)` returns true or retries exhausted.
   * Applies state on each successful fetch so the UI updates as soon as the node catches up.
   */
  async function pollUntil(pid, until, { tries = 10, delay = 800 } = {}) {
    for (let i = 0; i < tries; i++) {
      if (i > 0) await new Promise(r => setTimeout(r, delay))
      const s = await fetchFullState(pid)
      if (!s) continue
      applyState(s)
      if (until(s)) return
    }
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
    invader = null; confirmedMarker = null; buildings = []
  }

  function handleNewPlanet() {
    planetId = null; planetName = ''; planet = null
    colony = null; resources = null; assigned = null; unassigned = null
    invader = null; confirmedMarker = null; buildings = []
    phase = 'mint'
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

  function isUserCancelledTx(error) {
    const code = error?.code ?? error?.cause?.code
    const msg = String(error?.message ?? error ?? '').toLowerCase()
    return (
      code === 4001 ||
      code === 'USER_ABORTED' ||
      msg.includes('user rejected') ||
      msg.includes('rejected by user') ||
      msg.includes('user aborted') ||
      msg.includes('transaction cancelled') ||
      msg.includes('transaction canceled') ||
      msg.includes('request canceled') ||
      msg.includes('request cancelled')
    )
  }

  // ---------------------------------------------------------------------------
  // Building selection
  // ---------------------------------------------------------------------------
  function handleBuildingClick(lon, lat) {
    // Allow building selection even in build mode
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
      await pollUntil(planetId, s => s.colony !== null)
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
    // Don't deselect building when entering build mode
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
      await pollUntil(planetId, s => s.buildings.some(b => b.lon === lon && b.lat === lat))
      selectedBuildType = null
      pendingBuildSite = null
      if (type === 6) {
        // Final collect to lock end state on-chain before showing won screen
        try {
          await collect(account, planetId)
          await refreshColonyState(planetId)
        } catch (_) { /* ignore if it fails */ }
        phase = 'won'
      }
      txStatus = ''
    } catch (e) {
      if (isUserCancelledTx(e)) {
        // Keep current selection/site so the player can retry instantly.
        txStatus = 'Build cancelled.'
      } else {
        txStatus = 'Error: ' + (e.message ?? String(e))
      }
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
      const previousLevel = colony?.tcLevel ?? 1
      await upgradeTc(account, planetId)
      await pollUntil(planetId, s => (s.colony?.tcLevel ?? previousLevel) > previousLevel)
      txStatus = ''
    } catch (e) {
      txStatus = 'Error: ' + (e.message ?? String(e))
    } finally { txPending = false }
  }

  // ---------------------------------------------------------------------------
  // Fight invader
  // ---------------------------------------------------------------------------
  async function handleFightInvader(colonists) {
    if (!account) return
    txPending = true
    txStatus = 'Sending fighters...'
    try {
      await fightInvader(account, planetId, colonists)
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
  
  // Complete epochs that have accumulated since last collect
  const epochsReady = $derived.by(() => {
    const ref = planet?.lastActionAt ?? 0
    if (!ref) return 0
    return Math.floor((nowSeconds - ref) / EPOCH_SECONDS)
  })

  // Progress within the current (next) partial epoch (0–1)
  const epochFraction = $derived.by(() => {
    const ref = planet?.lastActionAt ?? 0
    if (!ref) return 0
    const elapsed = nowSeconds - ref
    return (elapsed % EPOCH_SECONDS) / EPOCH_SECONDS
  })

  // Countdown to the next epoch tick
  const epochNextIn = $derived.by(() => {
    const ref = planet?.lastActionAt ?? 0
    if (!ref) return '--:--'
    const elapsed = nowSeconds - ref
    const remaining = EPOCH_SECONDS - (elapsed % EPOCH_SECONDS)
    const m = Math.floor(remaining / 60)
    const s = remaining % 60
    return `${m}:${s.toString().padStart(2, '0')}`
  })

  // Keep for any legacy uses
  const epochsElapsed = epochsReady
  const epochProgress = epochFraction
  const epochCountdown = epochNextIn

  const threat = $derived(
    (planet && resources) ? computeThreat(planet, resources, nowSeconds) : 0
  )
  const attackProb = $derived(attackProbability(threat))
  
  // Calculate time since colony founding
  const timeSinceFounding = $derived.by(() => {
    if (!colony?.foundedAt) return '--:--:--'
    const elapsed = nowSeconds - colony.foundedAt
    const hours = Math.floor(elapsed / 3600)
    const minutes = Math.floor((elapsed % 3600) / 60)
    const seconds = elapsed % 60
    return `${hours}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`
  })
  
  const colonyAgeEpochs = $derived.by(() => {
    if (!colony?.foundedAt || !resources?.lastUpdatedAt) return 0
    return Math.floor((resources.lastUpdatedAt - colony.foundedAt) / EPOCH_SECONDS)
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
      pendingBuildSite={pendingBuildSite}
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

  <a class="github-btn" href="https://github.com/ZackAmes/planets" target="_blank" rel="noopener" title="View on GitHub">
    <svg class="github-icon" viewBox="0 0 98 96" xmlns="http://www.w3.org/2000/svg">
      <path fill-rule="evenodd" clip-rule="evenodd" d="M48.854 0C21.839 0 0 22 0 49.217c0 21.756 13.993 40.172 33.405 46.69 2.427.49 3.316-1.059 3.316-2.362 0-1.141-.08-5.052-.08-9.127-13.59 2.934-16.42-5.867-16.42-5.867-2.184-5.704-5.42-7.17-5.42-7.17-4.448-3.015.324-3.015.324-3.015 4.934.326 7.523 5.052 7.523 5.052 4.367 7.496 11.404 5.378 14.235 4.074.404-3.178 1.699-5.378 3.074-6.6-10.839-1.141-22.243-5.378-22.243-24.283 0-5.378 1.94-9.778 5.014-13.2-.485-1.222-2.184-6.275.486-13.038 0 0 4.125-1.304 13.426 5.052a46.97 46.97 0 0 1 12.214-1.63c4.125 0 8.33.571 12.213 1.63 9.302-6.356 13.427-5.052 13.427-5.052 2.67 6.763.97 11.816.485 13.038 3.155 3.422 5.015 7.822 5.015 13.2 0 18.905-11.404 23.06-22.324 24.283 1.78 1.548 3.316 4.481 3.316 9.126 0 6.6-.08 11.897-.08 13.526 0 1.304.89 2.853 3.316 2.364 19.412-6.52 33.405-24.935 33.405-46.691C97.707 22 75.788 0 48.854 0z"/>
    </svg>
  </a>

  <div class="ui">
    <div class="header">
      <span class="planet-label">PLANETS</span>
      {#if planetName && (phase === 'managing' || phase === 'founding' || phase === 'won' || phase === 'gameover')}
        <span class="planet-name-hdr">{planetName}</span>
      {/if}
      {#if planetId != null && (phase === 'managing' || phase === 'founding' || phase === 'won' || phase === 'gameover')}
        <a class="btn-sm voyager-link" href="https://sepolia.voyager.online/nft/0x0142712722e62a38f9c40fcc904610e1a14c70125876ecaaf25d803556734467/{planetId}" target="_blank" rel="noopener" title="View NFT on Voyager">NFT</a>
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
          epochFraction={epochFraction}
          epochsReady={epochsReady}
          epochNextIn={epochNextIn}
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
        dismissedTipIds={[...dismissedTips]}
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
          <p class="dim">Colony age: {colonyAgeEpochs} epochs</p>
          <p class="dim" style="color:#bb44ff">Final population: {planet.population}</p>
          {#if planetId != null}
            <a class="end-link voyager-end" href="https://sepolia.voyager.online/nft/0x0142712722e62a38f9c40fcc904610e1a14c70125876ecaaf25d803556734467/{planetId}" target="_blank" rel="noopener">View NFT on Voyager ↗</a>
          {/if}
          <button class="btn-primary" onclick={handleNewPlanet}>Start New Colony</button>
        </div>
      {:else if phase === 'gameover'}
        <div class="end-panel">
          <h2>Colony Lost</h2>
          <p class="hint">Your colonists are gone.</p>
          <p class="dim">Colony age: {colonyAgeEpochs} epochs</p>
          {#if planetId != null}
            <a class="end-link voyager-end" href="https://sepolia.voyager.online/nft/0x0142712722e62a38f9c40fcc904610e1a14c70125876ecaaf25d803556734467/{planetId}" target="_blank" rel="noopener">View NFT on Voyager ↗</a>
          {/if}
          <button class="btn-primary" onclick={handleNewPlanet}>Start New Colony</button>
        </div>
      {/if}
    {/if}
  </div>

  <!-- Left side panels -->
  {#if phase === 'managing' && planet}
    <div class="ui-left">
      <InvaderPanel
        {invader}
        {unassigned}
        {resources}
        cannonDamageRate={rates.cannonDamageRate}
        onfight={handleFightInvader}
        disabled={txPending}
      />

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
        {resources}
        {tcLevel}
        disabled={txPending}
        onbuildingselect={handleBuildingClick}
        onupgradebuilding={handleUpgradeBuilding}
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

  .github-btn {
    position: absolute;
    top: 1rem;
    right: 1rem;
    display: flex;
    align-items: center;
    justify-content: center;
    width: 36px;
    height: 36px;
    background: rgba(5, 5, 20, 0.85);
    border: 1px solid #1a2a3a;
    border-radius: 8px;
    text-decoration: none;
    transition: border-color 0.15s, background 0.15s;
    z-index: 20;
  }

  .github-btn:hover {
    background: rgba(15, 20, 40, 0.95);
    border-color: #2a4a6a;
  }

  .github-icon {
    width: 18px;
    height: 18px;
    fill: #446688;
    transition: fill 0.15s;
  }

  .github-btn:hover .github-icon {
    fill: #6ab4ff;
  }

  .voyager-link {
    text-decoration: none;
    color: #5566aa;
  }

  .voyager-link:hover {
    color: #8899ff;
    border-color: #4466aa;
  }

  .end-link {
    font-family: monospace;
    font-size: 0.7rem;
    text-decoration: none;
    padding: 0.3rem 0.6rem;
    border-radius: 4px;
    border: 1px solid #2a3a5a;
    transition: border-color 0.15s, color 0.15s;
  }

  .voyager-end {
    color: #5577bb;
  }

  .voyager-end:hover {
    color: #8899ff;
    border-color: #4466aa;
  }

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
