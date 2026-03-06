// Contract configuration.
// Addresses come from `sozo migrate` output (manifest_sepolia.json).
// Override these via VITE_ env vars for different deployments.

export const CONFIG = {
  rpcUrl:
    import.meta.env.VITE_RPC_URL ??
    'https://api.cartridge.gg/x/starknet/sepolia',

  worldAddress:
    import.meta.env.VITE_WORLD_ADDRESS ??
    '0x5551f4fa08f4313d5c43d5a8607e711bf01eb732717947b9579ce7d19d464ae',

  // System contract addresses (from manifest_sepolia.json, namespace: starnet)
  planetSystemsAddress:
    import.meta.env.VITE_PLANET_SYSTEMS_ADDRESS ??
    '0x68bd0cc6e8a3fc10f0ec410b1d136f12501a4b02f082045c76187f74cc68810',

  gameSystemsAddress:
    import.meta.env.VITE_GAME_SYSTEMS_ADDRESS ??
    '0x18e59dff859e8cedb12a389ec82d6f6ff5790c71aec49824c8066535581f076',

  gameTokenSystemsAddress:
    import.meta.env.VITE_GAME_TOKEN_SYSTEMS_ADDRESS ??
    '0x76a32edec6a0ba7a7e067e1832e07a80fb8d1f96748b6d5c527f2947294d5ce',

  // Namespace used in this deployment
  namespace: import.meta.env.VITE_NAMESPACE ?? 'starnet',
}
