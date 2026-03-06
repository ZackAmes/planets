<script>
  import { Canvas } from '@threlte/core'
  import PlanetView from './components/PlanetView.svelte'
  import ColonyPanel from './components/ColonyPanel.svelte'
  import { foundColony, assignOrders, deriveTerrainBonuses } from './lib/gameLogic.js'

  // Seed will eventually come from the onchain VRF.
  const SEED = 987654321

  // ---------------------------------------------------------------------------
  // Game state
  // ---------------------------------------------------------------------------

  // Phases: 'founding' → 'managing' → 'gameover'
  let phase = $state('founding')

  let planet = $state({
    seed: SEED,
    population: 100,
    actionCount: 0,
    width: 50,
    height: 40,
  })

  let colony = $state(null)

  // Location chosen on the sphere but not yet confirmed
  let pendingLocation = $state(null)    // { col, row }
  let pendingMarker = $state(null)      // [x, y, z] local sphere coords
  let confirmedMarker = $state(null)    // [x, y, z] local sphere coords

  let lastEvents = $state([])

  // ---------------------------------------------------------------------------
  // Handlers
  // ---------------------------------------------------------------------------

  function handleLocationPick(col, row, _u, _v, localPos) {
    // Preview the terrain bonuses before committing
    const { fertility, mineralRichness } = deriveTerrainBonuses(planet.seed, col, row)
    pendingLocation = { col, row }
    pendingMarker = localPos
    // Pre-populate colony preview so ColonyPanel can show the bonuses
    colony = { col, row, founded: false, fertility, mineralRichness, food: 0, minerals: 0, buildings: 0, defense: 0 }
  }

  function handleConfirmLocation() {
    if (!pendingLocation) return
    colony = foundColony(planet, pendingLocation.col, pendingLocation.row)
    confirmedMarker = pendingMarker
    pendingLocation = null
    pendingMarker = null
    phase = 'managing'
  }

  function handleSubmitOrders(orders) {
    if (!colony || planet.population === 0) return
    const result = assignOrders(planet, colony, orders)
    planet = result.planet
    colony = result.colony
    lastEvents = result.events

    if (planet.population === 0) {
      phase = 'gameover'
    }
  }
</script>

<div class="root">
  <Canvas>
    <PlanetView
      seed={SEED}
      canPick={phase === 'founding'}
      colonyMarker={phase === 'managing' || phase === 'gameover'
        ? confirmedMarker
        : pendingMarker}
      onlocationpick={handleLocationPick}
    />
  </Canvas>

  <div class="ui">
    <div class="title">
      <span class="planet-label">PLANET #{SEED}</span>
      {#if planet}
        <span class="pop">Pop: {planet.population}</span>
      {/if}
    </div>

    <ColonyPanel
      {phase}
      {planet}
      {colony}
      pendingLocation={pendingLocation}
      lastEvents={lastEvents}
      onconfirm={handleConfirmLocation}
      onsubmit={handleSubmitOrders}
    />
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
  }

  .title {
    display: flex;
    align-items: center;
    justify-content: space-between;
    background: rgba(5, 5, 20, 0.8);
    border: 1px solid #1a2a3a;
    border-radius: 6px;
    padding: 0.4rem 0.75rem;
    font-family: monospace;
    font-size: 0.75rem;
  }

  .planet-label {
    color: #445566;
    letter-spacing: 0.1em;
  }

  .pop {
    color: #6ab4ff;
    font-weight: bold;
  }
</style>
