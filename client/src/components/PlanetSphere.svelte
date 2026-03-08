<script>
  import { T, useTask } from '@threlte/core'
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
    onlocationpick = null,    // (col, row, lon, lat, localPos) => void
    onbuildpick = null,       // (lon, lat, localPos) => void
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
    buildings.map((b) => ({
      ...b,
      pos: lonLatToLocal(b.lon, b.lat, 8.15),
      color: BUILDING_INFO[b.buildingType]?.color ?? '#ffffff',
    }))
  )

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
    <T.Mesh position={b.pos}>
      <T.SphereGeometry args={[0.18, 6, 6]} />
      <T.MeshStandardMaterial
        color={b.color}
        emissive={b.color}
        emissiveIntensity={0.6}
        roughness={0.4}
      />
    </T.Mesh>
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
