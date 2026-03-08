<script>
  import { T } from '@threlte/core'
  import { OrbitControls, interactivity } from '@threlte/extras'
  import PlanetSphere from './PlanetSphere.svelte'

  let {
    seed = 42,
    seedFull = null,
    canPick = false,
    canBuild = false,
    colonyMarker = null,
    buildings = [],
    invader = null,
    selectedBuilding = null,
    onlocationpick = null,
    onbuildpick = null,
    onbuildingclick = null,
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

<T.DirectionalLight position={[12, 10, 22]} intensity={1.6} castShadow />
<T.AmbientLight intensity={0.45} />

<PlanetSphere
  {seed}
  {seedFull}
  {canPick}
  {canBuild}
  {colonyMarker}
  {buildings}
  {invader}
  {selectedBuilding}
  {onlocationpick}
  {onbuildpick}
  {onbuildingclick}
/>
