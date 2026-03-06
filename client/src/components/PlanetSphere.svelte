<script>
  import { T, useTask } from '@threlte/core'
  import * as THREE from 'three'
  import { generatePlanetTexture } from '../lib/planetGen.js'
  import { PLANET_WIDTH, PLANET_HEIGHT } from '../lib/gameLogic.js'

  let { seed = 42, canPick = false, colonyMarker = null, onlocationpick = null } = $props()

  // Capture seed once at mount — texture is static for the lifetime of this component.
  // A new seed requires remounting (key={seed} on the parent Canvas).
  const initialSeed = seed
  const canvas = generatePlanetTexture(initialSeed)
  const texture = new THREE.CanvasTexture(canvas)
  texture.colorSpace = THREE.SRGBColorSpace

  let mesh = $state(null)

  // Rotate the planet ~one full turn per 60 seconds
  useTask((delta) => {
    if (mesh) mesh.rotation.y += delta * 0.1
  })

  function handleClick(event) {
    if (!canPick || !onlocationpick || !mesh) return
    const uv = event.uv
    if (!uv) return

    // UV: u=0 left → u=1 right, v=0 bottom → v=1 top in Three.js UV space.
    // Our texture was drawn with y=0 at the top (north), so v is flipped.
    const col = Math.min(PLANET_WIDTH - 1, Math.floor(uv.x * PLANET_WIDTH))
    const row = Math.min(PLANET_HEIGHT - 1, Math.floor((1 - uv.y) * PLANET_HEIGHT))

    // Compute the click position in the sphere's local space so the marker
    // can be placed as a child mesh (it will rotate with the planet).
    const localPoint = mesh.worldToLocal(event.point.clone()).normalize().multiplyScalar(8.15)

    onlocationpick(col, row, uv.x, uv.y, [localPoint.x, localPoint.y, localPoint.z])
  }
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
</T.Mesh>

<!-- Atmosphere glow (slightly larger sphere rendered from inside) -->
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
