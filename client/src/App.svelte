<script>
  import { onMount } from 'svelte'
  import { Canvas } from '@threlte/core'
  import PlanetView from './components/PlanetView.svelte'
  import ColonyPanel from './components/ColonyPanel.svelte'
  import { connect, disconnect, subscribe } from './lib/controller.js'
  import { spawnPlanet, foundColony, assignOrders, txHashToSeed } from './lib/onchain.js'
  import { foundColony as localFoundColony, assignOrders as localAssignOrders } from './lib/gameLogic.js'

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
  // Game state — phases: 'connect' | 'spawn' | 'founding' | 'managing' | 'gameover'
  // ---------------------------------------------------------------------------
  let phase = $state('connect')
  let planetId = $state(1)      // will be set properly after mint; 1 for dev
  let planetName = $state('')

  let planet = $state(null)     // { seed, population, actionCount, width, height }
  let colony = $state(null)     // { col, row, food, minerals, ... }

  let pendingLocation = $state(null)  // { col, row } chosen but not confirmed
  let pendingMarker = $state(null)    // [x, y, z]
  let confirmedMarker = $state(null)  // [x, y, z]

  let lastEvents = $state([])
  let txPending = $state(false)
  let txStatus = $state('')        // status message shown in UI

  // ---------------------------------------------------------------------------
  // Wallet connect
  // ---------------------------------------------------------------------------
  async function handleConnect() {
    const acc = await connect()
    if (acc) phase = 'spawn'
  }

  async function handleDisconnect() {
    await disconnect()
    phase = 'connect'
    planet = null
    colony = null
    confirmedMarker = null
  }

  // ---------------------------------------------------------------------------
  // Spawn planet
  // ---------------------------------------------------------------------------
  async function handleSpawn() {
    if (!account || !planetName.trim()) return
    txPending = true
    txStatus = 'Spawning planet...'
    try {
      const txHash = await spawnPlanet(account, planetId, planetName.trim())
      // Transaction hash IS the seed (contract uses get_tx_info().transaction_hash)
      const seed = txHashToSeed(txHash)
      planet = {
        seed: Number(seed % BigInt(2 ** 53)), // safe JS number for planetGen
        seedFull: seed,
        population: 100,
        actionCount: 0,
        width: 50,
        height: 40,
      }
      txStatus = 'Planet spawned!'
      phase = 'founding'
    } catch (e) {
      txStatus = 'Error: ' + (e.message ?? String(e))
    } finally {
      txPending = false
    }
  }

  // ---------------------------------------------------------------------------
  // Colony founding
  // ---------------------------------------------------------------------------
  function handleLocationPick(col, row, _u, _v, localPos) {
    const { foundColony: preview } = {
      foundColony: localFoundColony(planet, col, row),
    }
    pendingLocation = { col, row }
    pendingMarker = localPos
    colony = preview
  }

  async function handleConfirmLocation() {
    if (!pendingLocation || !account) return
    txPending = true
    txStatus = 'Founding colony...'
    try {
      await foundColony(account, planetId, pendingLocation.col, pendingLocation.row)
      colony = localFoundColony(planet, pendingLocation.col, pendingLocation.row)
      confirmedMarker = pendingMarker
      pendingLocation = null
      pendingMarker = null
      phase = 'managing'
      txStatus = ''
    } catch (e) {
      txStatus = 'Error: ' + (e.message ?? String(e))
    } finally {
      txPending = false
    }
  }

  // ---------------------------------------------------------------------------
  // Turn orders
  // ---------------------------------------------------------------------------
  async function handleSubmitOrders(orders) {
    if (!colony || !account || planet.population === 0) return
    txPending = true
    txStatus = 'Submitting orders...'
    try {
      await assignOrders(account, planetId, orders)
      const result = localAssignOrders(planet, colony, orders)
      planet = result.planet
      colony = result.colony
      lastEvents = result.events
      txStatus = ''
      if (planet.population === 0) phase = 'gameover'
    } catch (e) {
      txStatus = 'Error: ' + (e.message ?? String(e))
    } finally {
      txPending = false
    }
  }

  // Seed to use for planet rendering (falls back to test seed before spawn)
  const DEV_SEED = 987654321
  const displaySeed = $derived(planet?.seed ?? DEV_SEED)
</script>

<div class="root">
  <Canvas>
    <PlanetView
      seed={displaySeed}
      canPick={phase === 'founding' && !txPending}
      colonyMarker={phase === 'managing' || phase === 'gameover'
        ? confirmedMarker
        : pendingMarker}
      onlocationpick={handleLocationPick}
    />
  </Canvas>

  <div class="ui">
    <!-- Header bar -->
    <div class="header">
      <span class="planet-label">PLANETS</span>
      {#if address}
        <span class="addr">{address.slice(0, 6)}…{address.slice(-4)}</span>
        <button class="btn-sm" onclick={handleDisconnect}>Disconnect</button>
      {/if}
    </div>

    {#if txStatus}
      <div class="status" class:error={txStatus.startsWith('Error')}>
        {txStatus}
      </div>
    {/if}

    <!-- Phase: connect -->
    {#if phase === 'connect'}
      <div class="card center">
        <h2>PLANETS</h2>
        <p>An onchain colony builder.</p>
        <button class="btn-primary" onclick={handleConnect}>
          Connect Wallet
        </button>
      </div>

    <!-- Phase: spawn -->
    {:else if phase === 'spawn'}
      <div class="card">
        <h2>Name Your Planet</h2>
        <input
          class="name-input"
          type="text"
          placeholder="Planet name…"
          maxlength="31"
          bind:value={planetName}
          onkeydown={(e) => e.key === 'Enter' && handleSpawn()}
        />
        <button class="btn-primary" onclick={handleSpawn} disabled={txPending || !planetName.trim()}>
          {txPending ? 'Spawning…' : 'Spawn Planet'}
        </button>
      </div>

    <!-- Phase: founding / managing / gameover -->
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
        pendingLocation={pendingLocation}
        lastEvents={lastEvents}
        disabled={txPending}
        onconfirm={handleConfirmLocation}
        onsubmit={handleSubmitOrders}
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

  /* Header */
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

  .planet-label {
    color: #445566;
    letter-spacing: 0.12em;
    flex: 1;
  }

  .addr {
    color: #6ab4ff;
    font-size: 0.7rem;
  }

  /* Status bar */
  .status {
    background: rgba(20, 40, 20, 0.9);
    border: 1px solid #2a5a3a;
    border-radius: 6px;
    padding: 0.4rem 0.75rem;
    font-family: monospace;
    font-size: 0.72rem;
    color: #6aff9a;
  }

  .status.error {
    background: rgba(40, 10, 10, 0.9);
    border-color: #5a2a2a;
    color: #ff6a6a;
  }

  /* Cards */
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

  .card.center {
    align-items: center;
    text-align: center;
  }

  .card h2 {
    font-size: 1.1rem;
    color: #8ecfff;
    letter-spacing: 0.15em;
    margin: 0;
  }

  .card p {
    color: #667;
    font-size: 0.8rem;
    margin: 0;
  }

  /* Name input */
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

  .name-input:focus {
    outline: none;
    border-color: #2a6aaa;
  }

  /* Pop bar */
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

  .pop-label {
    font-size: 0.65rem;
    color: #445566;
    text-transform: uppercase;
  }

  .pop-value {
    font-size: 0.85rem;
    color: #6ab4ff;
    font-weight: bold;
    margin-right: 0.5rem;
  }

  /* Buttons */
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

  .btn-primary:hover:not(:disabled) {
    background: #1f4a72;
  }

  .btn-primary:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

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

  .btn-sm:hover {
    color: #6ab4ff;
    border-color: #2a4a6a;
  }
</style>
