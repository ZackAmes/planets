// Contract configuration.
// Addresses come from manifest_sepolia.json (sozo migrate output).
// Override with VITE_ env vars for different deployments.
import manifest from '../../../contracts/manifest_sepolia.json'
export const CONFIG = {
  rpcUrl:
    import.meta.env.VITE_RPC_URL ??
    'https://api.cartridge.gg/x/starknet/sepolia',

  worldAddress:
    import.meta.env.VITE_WORLD_ADDRESS ??
    manifest.world.address,

  planetSystemsAddress:
    import.meta.env.VITE_PLANET_SYSTEMS_ADDRESS ??
    manifest.contracts[2].address,

  gameSystemsAddress:
    import.meta.env.VITE_GAME_SYSTEMS_ADDRESS ??
    manifest.contracts[0].address,

  gameTokenSystemsAddress:
    import.meta.env.VITE_GAME_TOKEN_SYSTEMS_ADDRESS ??
    manifest.contracts[1].address,

  rendererSystemsAddress:
    import.meta.env.VITE_RENDERER_SYSTEMS_ADDRESS ??
    manifest.contracts[3].address,

  namespace: import.meta.env.VITE_NAMESPACE ?? 'planets',
}
