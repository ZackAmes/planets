<script>
  import { T } from '@threlte/core'
  import { OrbitControls, interactivity } from '@threlte/extras'
  import PlanetSphere from './PlanetSphere.svelte'

  let {
    seed = 42,
    canPick = false,
    canBuild = false,
    colonyMarker = null,
    buildings = [],
    onlocationpick = null,
    onbuildpick = null,
  } = $props()

  interactivity()
</script>

<T.PerspectiveCamera makeDefault position={[0, 6, 24]} fov={50}>
  <OrbitControls
    enableDamping
    dampingFactor={0.08}
    minDistance={12}
    maxDistance={60}
  />
</T.PerspectiveCamera>

<T.DirectionalLight position={[30, 15, 20]} intensity={2.2} castShadow />
<T.AmbientLight intensity={0.08} />

<PlanetSphere
  {seed}
  {canPick}
  {canBuild}
  {colonyMarker}
  {buildings}
  {onlocationpick}
  {onbuildpick}
/>
