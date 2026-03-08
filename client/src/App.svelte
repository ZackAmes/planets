<script>
  import { onMount } from 'svelte'
  import { Canvas } from '@threlte/core'
  import PlanetView from './components/PlanetView.svelte'
  import ColonyPanel from './components/ColonyPanel.svelte'
  import { connect, disconnect, subscribe } from './lib/controller.js'
  import { mintGame, spawnPlanet, foundColony, constructBuilding, assignWorkers, collect, upgradeTc, upgradeBuilding, craftGear, fightInvader, waitForTx } from './lib/onchain.js'
  import { fetchDenshokanPlanets, fetchPlanet, fetchColony, fetchFullState } from './lib/contracts.js'
  import { getProvider } from './lib/contracts.js'

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

  let pendingLocation = $state(null)  // { col, row }
  let pendingMarker   = $state(null)  // [x, y, z]
  let confirmedMarker = $state(null)  // [x, y, z]

  let invader  = $state(null) // { active, strength, lon, lat, spawnedAt }
  let gear     = $state(null) // { weapons, armor }

  let buildings        = $state([])
  let buildMode        = $state(false)
  let selectedBuildType = $state(null)
  let pendingBuildSite  = $state(null) // { lon, lat, localPos }

  let lastEvents = $state([])
  let txPending  = $state(false)
  let txStatus   = $state('')

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
  // Colony founding
  // ---------------------------------------------------------------------------
  function handleLocationPick(col, row, _lon, _lat, localPos) {
    pendingLocation = { col, row }
    pendingMarker = localPos
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
  function handleBuildMode(type) {
    if (type === null) { buildMode = false; selectedBuildType = null; pendingBuildSite = null }
    else { buildMode = true; selectedBuildType = type; pendingBuildSite = null }
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
      buildMode = false; selectedBuildType = null; pendingBuildSite = null
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

  const DEV_SEED = 987654321
  const displaySeed = $derived(planet?.seed ?? DEV_SEED)
</script>

<div class="root">
  <Canvas>
    <PlanetView
      seed={displaySeed}
      canPick={phase === 'founding' && !txPending}
      canBuild={phase === 'managing' && buildMode && !txPending}
      colonyMarker={phase === 'managing' || phase === 'gameover'
        ? confirmedMarker
        : pendingMarker}
      {buildings}
      {invader}
      onlocationpick={handleLocationPick}
      onbuildpick={handleBuildPick}
    />
  </Canvas>

  <div class="ui">
    <div class="header">
      <span class="planet-label">PLANETS</span>
      {#if address}
        <span class="addr">{address.slice(0, 6)}…{address.slice(-4)}</span>
        {#if planet && (phase === 'managing' || phase === 'founding')}
          <button class="btn-sm" onclick={handleManualRefresh} disabled={txPending} title="Refresh state">⟳</button>
        {/if}
        <button class="btn-sm" onclick={handleDisconnect}>Disconnect</button>
      {/if}
    </div>

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
      <div class="pop-bar">
        <span class="pop-label">Pop</span>
        <span class="pop-value">{planet.population}</span>
        <span class="pop-label">Turn</span>
        <span class="pop-value">{planet.actionCount}</span>
      </div>

      <ColonyPanel
        {phase}
        {planet}
        {colony}
        {resources}
        {assigned}
        {unassigned}
        {invader}
        {gear}
        {buildings}
        {pendingLocation}
        {lastEvents}
        disabled={txPending}
        {buildMode}
        {pendingBuildSite}
        onconfirm={handleConfirmLocation}
        oncollect={handleCollect}
        onassign={handleAssignWorkers}
        onupgradetc={handleUpgradeTc}
        onupgradebuilding={handleUpgradeBuilding}
        oncraftgear={handleCraftGear}
        onfight={handleFightInvader}
        onbuildmode={handleBuildMode}
        onbuild={handleConfirmBuild}
      />
    {/if}
  </div>
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
    top: 1rem;
    right: 1rem;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    pointer-events: all;
    max-width: 260px;
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

  .planet-label { color: #445566; letter-spacing: 0.12em; flex: 1; }
  .addr { color: #6ab4ff; font-size: 0.7rem; }

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

  .pop-bar {
    display: flex;
    gap: 0.5rem;
    align-items: center;
    background: rgba(5, 5, 20, 0.85);
    border: 1px solid #1a2a3a;
    border-radius: 6px;
    padding: 0.35rem 0.75rem;
    font-family: monospace;
  }

  .pop-label { font-size: 0.65rem; color: #445566; text-transform: uppercase; }
  .pop-value { font-size: 0.85rem; color: #6ab4ff; font-weight: bold; margin-right: 0.5rem; }

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
</style>
