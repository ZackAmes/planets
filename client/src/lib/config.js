// Contract configuration.
// Addresses come from manifest_sepolia.json (sozo migrate output).
// Override with VITE_ env vars for different deployments.

export const CONFIG = {
  rpcUrl:
    import.meta.env.VITE_RPC_URL ??
    'https://api.cartridge.gg/x/starknet/sepolia',

  worldAddress:
    import.meta.env.VITE_WORLD_ADDRESS ??
    '0x12b55ae1212a82042368b6181b8665965db3cf17772bf6e969b3995b6e3d2c7',

  planetSystemsAddress:
    import.meta.env.VITE_PLANET_SYSTEMS_ADDRESS ??
    '0x2615dcba9124015cdee699bc6c7f39aa8e7672ce3453f48e1135576b6454b8e',

  gameSystemsAddress:
    import.meta.env.VITE_GAME_SYSTEMS_ADDRESS ??
    '0xbb0ebfcead0f39a436a05d57808547691857578b278373632a123f3408cbc4',

  gameTokenSystemsAddress:
    import.meta.env.VITE_GAME_TOKEN_SYSTEMS_ADDRESS ??
    '0x3653f97fd11362456254b77daede479bec99ac45754125ad26f94ba03cbe03c',

  rendererSystemsAddress:
    import.meta.env.VITE_RENDERER_SYSTEMS_ADDRESS ??
    '0x6dd2531d4c3ec35756466e71c7f28afe99eed763e35f0f88a96a986a92c9c45',

  namespace: import.meta.env.VITE_NAMESPACE ?? 'planets',
}
