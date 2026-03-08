/**
 * Contract interaction helpers.
 * Each write function takes a starknet.js WalletAccount and returns
 * transaction_hash on success, or throws on failure.
 */

import { shortString } from 'starknet'
import { CONFIG } from './config.js'
import { mintCall, getProvider, fetchDenshokanPlanets } from './contracts.js'

// ---------------------------------------------------------------------------
// denshokan — mint
// ---------------------------------------------------------------------------

/**
 * Mint a game token via the Denshokan contract.
 * Waits for the tx, then fetches the player's planet list to get the new tokenId.
 * Returns { transaction_hash, tokenId }.
 */
export async function mintGame(account, playerName) {
  const call = mintCall(account.address, playerName)
  const { transaction_hash } = await account.execute([call])
  await waitForTx(getProvider(), transaction_hash)
  const ids = await fetchDenshokanPlanets(account.address)
  const tokenId = ids.length > 0 ? ids[ids.length - 1] : null
  return { transaction_hash, tokenId }
}

// ---------------------------------------------------------------------------
// planet_systems
// ---------------------------------------------------------------------------

/**
 * Initialize a planet for the given token id.
 * The seed is assigned by the Cartridge VRF onchain, so we wait for the tx
 * to be confirmed and let the caller fetch the planet to get the seed.
 */
export async function spawnPlanet(account, planetId, name) {
  const nameFelt = shortString.encodeShortString(name)
  const { transaction_hash } = await account.execute([
    {
      contractAddress: CONFIG.planetSystemsAddress,
      entrypoint: 'spawn_planet',
      calldata: [
        '0x' + BigInt(planetId).toString(16), // u64
        nameFelt,                              // felt252
      ],
    },
  ])
  await waitForTx(getProvider(), transaction_hash)
}

// ---------------------------------------------------------------------------
// game_systems
// ---------------------------------------------------------------------------

/**
 * Place the colony at (col, row) on the planet.
 */
export async function foundColony(account, planetId, col, row) {
  const { transaction_hash } = await account.execute([
    {
      contractAddress: CONFIG.gameSystemsAddress,
      entrypoint: 'found_colony',
      calldata: [
        '0x' + BigInt(planetId).toString(16), // u64
        col.toString(),                        // u32
        row.toString(),                        // u32
      ],
    },
  ])
  return transaction_hash
}

/**
 * Construct a building at (lon, lat) on the planet.
 * buildingType: 0=Farm, 1=Mine, 2=Barracks, 3=Workshop
 * lon 0-359, lat 0-179
 */
export async function constructBuilding(account, planetId, lon, lat, buildingType) {
  const { transaction_hash } = await account.execute([
    {
      contractAddress: CONFIG.gameSystemsAddress,
      entrypoint: 'construct_building',
      calldata: [
        '0x' + BigInt(planetId).toString(16), // u64
        lon.toString(),                        // u16
        lat.toString(),                        // u16
        buildingType.toString(),               // BuildingType enum discriminant (felt252)
      ],
    },
  ])
  return transaction_hash
}

/**
 * Assign workers to a building at (lon, lat).
 * workers: total workers to assign (not delta). 0 to remove all.
 */
export async function assignWorkers(account, planetId, lon, lat, workers) {
  const { transaction_hash } = await account.execute([
    {
      contractAddress: CONFIG.gameSystemsAddress,
      entrypoint: 'assign_workers',
      calldata: [
        '0x' + BigInt(planetId).toString(16), // u64
        lon.toString(),                        // u16
        lat.toString(),                        // u16
        workers.toString(),                    // u8
      ],
    },
  ])
  await waitForTx(getProvider(), transaction_hash)
  return transaction_hash
}

/**
 * Tick resources and collect (no-op if called too soon).
 */
export async function collect(account, planetId) {
  const { transaction_hash } = await account.execute([
    {
      contractAddress: CONFIG.gameSystemsAddress,
      entrypoint: 'collect',
      calldata: [
        '0x' + BigInt(planetId).toString(16), // u64
      ],
    },
  ])
  await waitForTx(getProvider(), transaction_hash)
  return transaction_hash
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Wait for a transaction to be accepted on L2.
 */
export async function waitForTx(provider, txHash) {
  return provider.waitForTransaction(txHash, {
    retryInterval: 1500,
    successStates: ['ACCEPTED_ON_L2', 'SUCCEEDED'],
  })
}

