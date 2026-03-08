<script>
  import { T, useTask } from '@threlte/core'
  import { HTML } from '@threlte/extras'
  import * as THREE from 'three'
  import { generatePlanetTexture } from '../lib/planetGen.js'
  import { PLANET_WIDTH, PLANET_HEIGHT, lonLatToLocal, uvToLonLat, BUILDING_INFO } from '../lib/gameLogic.js'

  let {
    seed = 42,
    seedFull = null,          // BigInt felt252 — authoritative Poseidon terrain seed
    canPick = false,          // colony founding mode
    canBuild = false,         // building placement mode
    colonyMarker = null,      // [x,y,z] in local sphere space
    buildings = [],           // [{ lon, lat, buildingType }]
    invader = null,           // { active, lon, lat } | null
    selectedBuilding = null,  // { lon, lat } of selected building
    onlocationpick = null,    // (col, row, lon, lat, localPos) => void
    onbuildpick = null,       // (lon, lat, localPos) => void
    onbuildingclick = null,   // (lon, lat) => void
  } = $props()

  // Capture seeds once at mount — texture is static for the lifetime of this component.
  // A new seed requires remounting (key={seed} on the parent Canvas).
  const initialSeed     = seed
  const initialSeedFull = seedFull
  const canvas = generatePlanetTexture(initialSeed, initialSeedFull)
  const texture = new THREE.CanvasTexture(canvas)
  texture.colorSpace = THREE.SRGBColorSpace

  let mesh = $state(null)

  useTask((delta) => {
    // Pause rotation while the player is picking a location or placing a building
    if (mesh && !canPick && !canBuild) mesh.rotation.y += delta * 0.05
  })

  function handleClick(event) {
    if (!mesh) return
    const uv = event.uv
    if (!uv) return

    const localPoint = mesh.worldToLocal(event.point.clone()).normalize().multiplyScalar(8.15)
    const localPos = [localPoint.x, localPoint.y, localPoint.z]
    const { lon, lat } = uvToLonLat(uv.x, uv.y)

    if (canBuild && onbuildpick) {
      onbuildpick(lon, lat, localPos)
      return
    }

    if (canPick && onlocationpick) {
      const col = Math.min(PLANET_WIDTH - 1, Math.floor(uv.x * PLANET_WIDTH))
      const row = Math.min(PLANET_HEIGHT - 1, Math.floor((1 - uv.y) * PLANET_HEIGHT))
      onlocationpick(col, row, lon, lat, localPos)
    }
  }

  // Precompute building marker positions in local sphere space
  const buildingMarkers = $derived(
    buildings.map((b) => {
      const isSelected = selectedBuilding && b.lon === selectedBuilding.lon && b.lat === selectedBuilding.lat
      return {
        ...b,
        pos: lonLatToLocal(b.lon, b.lat, 8.15),
        color: BUILDING_INFO[b.buildingType]?.color ?? '#ffffff',
        isSelected,
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
</script>

<!-- Main planet sphere -->
<T.Mesh
  bind:ref={mesh}
  receiveShadow
  castShadow
  onclick={handleClick}
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
        color={b.color}
        emissive={b.color}
        emissiveIntensity={b.isSelected ? 1.2 : 0.6}
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
      <div class="building-label" class:selected={b.isSelected}>
        {BUILDING_INFO[b.buildingType]?.name ?? '?'}
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
</style>
