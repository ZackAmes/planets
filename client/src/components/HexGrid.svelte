<script>
  import { T } from '@threlte/core'
  import * as THREE from 'three'

  let { tiles } = $props()

  const HEX_SIZE = 1.0
  const HEX_GAP = 0.97 // slight gap between hexes

  // Cache materials per color to avoid redundant allocations
  const materialCache = new Map()
  function getMaterial(color) {
    if (!materialCache.has(color)) {
      materialCache.set(color, new THREE.MeshStandardMaterial({ color }))
    }
    return materialCache.get(color)
  }

  // Pointy-top hex: rotate cylinder by PI/6 on Y so flat edge faces camera
  const hexRotation = new THREE.Euler(0, Math.PI / 6, 0)
</script>

{#each tiles as tile (tile.col + '_' + tile.row)}
  <T.Mesh
    position={[tile.x, tile.height / 2, tile.z]}
    rotation={hexRotation}
    receiveShadow
    castShadow
  >
    <T.CylinderGeometry args={[HEX_SIZE * HEX_GAP, HEX_SIZE * HEX_GAP, tile.height, 6]} />
    <T is={getMaterial(tile.color)} />
  </T.Mesh>
{/each}
