<script>
  import { T } from '@threlte/core'
  import { OrbitControls, interactivity } from '@threlte/extras'
  import PlanetSphere from './PlanetSphere.svelte'

  let { seed = 42, canPick = false, colonyMarker = null, onlocationpick = null } = $props()

  // Enable pointer event handling for the whole scene
  interactivity()
</script>

<!-- Camera — pulled back enough to see the full sphere -->
<T.PerspectiveCamera makeDefault position={[0, 6, 24]} fov={50}>
  <OrbitControls
    enableDamping
    dampingFactor={0.08}
    minDistance={12}
    maxDistance={60}
  />
</T.PerspectiveCamera>

<!-- Sunlight from one side — gives the planet a lit/dark hemisphere -->
<T.DirectionalLight position={[30, 15, 20]} intensity={2.2} castShadow />

<!-- Very dim ambient so the dark side isn't pure black -->
<T.AmbientLight intensity={0.08} />

<!-- Planet -->
<PlanetSphere {seed} {canPick} {colonyMarker} {onlocationpick} />
