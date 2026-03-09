<script>
  import { T, useTask } from '@threlte/core'
  import { HTML } from '@threlte/extras'
  import * as THREE from 'three'
  import { generatePlanetTexture } from '../lib/planetGen.js'
  import { lonLatToLocal, uvToLonLat, snapToHexCenter, BUILDING_INFO } from '../lib/gameLogic.js'

  let {
    seed = 42,
    seedFull = null,          // BigInt felt252 — authoritative Poseidon terrain seed
    canPick = false,          // colony founding mode
    canBuild = false,         // building placement mode
    pendingBuildSite = null,  // { lon, lat } selected build tile
    colonyMarker = null,      // [x,y,z] in local sphere space
    buildings = [],           // [{ lon, lat, buildingType }]
    invader = null,           // { active, lon, lat } | null
    selectedBuilding = null,  // { lon, lat } of selected building
    onlocationpick = null,    // (col, row, lon, lat, localPos) => void
    onbuildpick = null,       // (lon, lat, localPos) => void
    onbuildingclick = null,   // (lon, lat) => void
  } = $props()

  function createPlanetTexture(nextSeed, nextSeedFull) {
    const canvas = generatePlanetTexture(nextSeed, nextSeedFull)
    const nextTexture = new THREE.CanvasTexture(canvas)
    nextTexture.colorSpace = THREE.SRGBColorSpace
    // Keep texture V orientation identical to event.uv coordinates.
    nextTexture.flipY = false
    return nextTexture
  }

  // Keep texture in sync with authoritative seed values.
  let texture = $state(null)
  $effect(() => {
    const nextTexture = createPlanetTexture(seed, seedFull)
    texture = nextTexture
    return () => nextTexture.dispose()
  })

  let mesh = $state(null)
  let hoveredTile = $state(null) // { col, row, lon, lat } - tile being hovered in build mode

  useTask((delta) => {
    // Pause rotation while the player is picking a location or placing a building
    if (mesh && !canPick && !canBuild) mesh.rotation.y += delta * 0.05
  })

  function handleClick(event) {
    if (!mesh) return
    // Use the already-snapped hovered tile when available so click and hover
    // always resolve to the same tile at boundaries.
    const snappedFromHover = hoveredTile
    const uv = event.uv
    if (!snappedFromHover && !uv) return
    const { lon, lat } = snappedFromHover ?? uvToLonLat(uv.x, uv.y)
    // Build + founding both snap to the same tile grid.
    if (canBuild && onbuildpick) {
      const snapped = snappedFromHover ?? snapToHexCenter(lon, lat)
      const snappedLocalPos = lonLatToLocal(snapped.lon, snapped.lat, 8.15)
      onbuildpick(snapped.lon, snapped.lat, snappedLocalPos)
      return
    }

    // Snap to tile center for colony founding
    if (canPick && onlocationpick) {
      const snapped = snappedFromHover ?? snapToHexCenter(lon, lat)
      const snappedLocalPos = lonLatToLocal(snapped.lon, snapped.lat, 8.15)
      onlocationpick(snapped.col, snapped.row, snapped.lon, snapped.lat, snappedLocalPos)
    }
  }

  function handleMouseMove(event) {
    if ((!canBuild && !canPick) || !mesh) {
      hoveredTile = null
      return
    }

    const uv = event.uv
    if (!uv) {
      hoveredTile = null
      return
    }

    const { lon, lat } = uvToLonLat(uv.x, uv.y)
    hoveredTile = snapToHexCenter(lon, lat)
  }

  // Precompute building marker positions in local sphere space
  const buildingMarkers = $derived(
    buildings.map((b) => {
      const isSelected = selectedBuilding && b.lon === selectedBuilding.lon && b.lat === selectedBuilding.lat
      const isUnderConstruction = b.completesAt && b.completesAt > Date.now() / 1000
      return {
        ...b,
        pos: lonLatToLocal(b.lon, b.lat, 8.15),
        color: BUILDING_INFO[b.buildingType]?.color ?? '#ffffff',
        isSelected,
        isUnderConstruction,
      }
    })
  )
  
  function handleBuildingClick(event, b) {
    event.stopPropagation()
    if (onbuildingclick) {
      onbuildingclick(b.lon, b.lat)
    }
  }

  const invaderPos = $derived(
    invader?.active ? lonLatToLocal(invader.lon, invader.lat, 8.15) : null
  )

  // Tile highlight position for build mode
  const tileHighlightPos = $derived(
    canBuild && pendingBuildSite
      ? (pendingBuildSite.localPos ?? lonLatToLocal(pendingBuildSite.lon, pendingBuildSite.lat, 8.15))
      : (hoveredTile ? lonLatToLocal(hoveredTile.lon, hoveredTile.lat, 8.15) : null)
  )
</script>

<!-- Main planet sphere -->
<T.Mesh
  bind:ref={mesh}
  receiveShadow
  castShadow
  onclick={handleClick}
  onpointermove={handleMouseMove}
>
  <T.SphereGeometry args={[8, 128, 64]} />
  <T.MeshStandardMaterial map={texture} roughness={0.85} metalness={0.05} />

  <!-- Colony marker (child of sphere mesh — rotates with the planet) -->
  {#if colonyMarker}
    <T.Mesh position={colonyMarker}>
      <T.SphereGeometry args={[0.28, 8, 8]} />
      <T.MeshStandardMaterial
        color="#ff4422"
        emissive="#ff2200"
        emissiveIntensity={0.9}
        roughness={0.3}
      />
    </T.Mesh>
  {/if}

  <!-- Building markers -->
  {#each buildingMarkers as b}
    <T.Mesh position={b.pos} onclick={(e) => handleBuildingClick(e, b)}>
      <T.SphereGeometry args={[b.isSelected ? 0.24 : 0.18, 8, 8]} />
      <T.MeshStandardMaterial
        color={b.isUnderConstruction ? '#ffaa00' : b.color}
        emissive={b.isUnderConstruction ? '#ff8800' : b.color}
        emissiveIntensity={b.isSelected ? 1.2 : (b.isUnderConstruction ? 0.9 : 0.6)}
        roughness={0.4}
      />
    </T.Mesh>
    
    <!-- Building label -->
    <HTML
      position={[b.pos[0] * 1.15, b.pos[1] * 1.15, b.pos[2] * 1.15]}
      center
      distanceFactor={10}
      occlude={false}
      zIndexRange={[100, 0]}
    >
      <div class="building-label" class:selected={b.isSelected} class:under-construction={b.isUnderConstruction}>
        {BUILDING_INFO[b.buildingType]?.name ?? '?'}
        {#if b.isUnderConstruction}
          <span class="construction-indicator">🏗️</span>
        {/if}
      </div>
    </HTML>
  {/each}

  <!-- Invader marker -->
  {#if invaderPos}
    <T.Mesh position={invaderPos}>
      <T.SphereGeometry args={[0.32, 8, 8]} />
      <T.MeshStandardMaterial
        color="#ff2222"
        emissive="#ff0000"
        emissiveIntensity={1.4}
        roughness={0.2}
      />
    </T.Mesh>
  {/if}

  <!-- Tile highlight for build mode or colony founding -->
  {#if tileHighlightPos && (canBuild || canPick)}
    <T.Mesh position={tileHighlightPos}>
      <T.SphereGeometry args={[0.22, 12, 12]} />
      <T.MeshStandardMaterial
        color={canPick ? "#ff8844" : "#66ff88"}
        emissive={canPick ? "#ff6622" : "#44ff66"}
        emissiveIntensity={0.8}
        roughness={0.3}
        transparent
        opacity={0.6}
      />
    </T.Mesh>
  {/if}
</T.Mesh>

<!-- Atmosphere glow -->
<T.Mesh>
  <T.SphereGeometry args={[8.5, 64, 32]} />
  <T.MeshStandardMaterial
    color="#4a8fd4"
    transparent
    opacity={0.08}
    side={THREE.BackSide}
    depthWrite={false}
  />
</T.Mesh>

<style>
  :global(.building-label) {
    background: rgba(5, 5, 20, 0.85);
    border: 1px solid #1a2a3a;
    border-radius: 4px;
    padding: 0.2rem 0.4rem;
    font-family: monospace;
    font-size: 0.65rem;
    color: #aaddff;
    white-space: nowrap;
    pointer-events: none;
    user-select: none;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.3);
  }

  :global(.building-label.selected) {
    background: rgba(10, 30, 50, 0.95);
    border-color: #6ab4ff;
    color: #6ab4ff;
    font-weight: bold;
  }

  :global(.building-label.under-construction) {
    color: #ffaa00;
    border-color: #ff8800;
    animation: pulse 1.5s ease-in-out infinite;
  }

  @keyframes pulse {
    0%, 100% {
      opacity: 1;
      text-shadow: 0 0 4px rgba(255, 170, 0, 0.6);
    }
    50% {
      opacity: 0.7;
      text-shadow: 0 0 8px rgba(255, 136, 0, 0.9);
    }
  }

  :global(.construction-indicator) {
    margin-left: 0.25rem;
    font-size: 0.8em;
  }
</style>
