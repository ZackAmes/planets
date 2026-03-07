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
 * The contract uses the transaction hash as the planet seed, so
 * transaction_hash IS the seed — no extra read needed.
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
  return transaction_hash
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
 * Process one turn. farming + mining + building + defense <= 100.
 */
export async function assignOrders(account, planetId, { farming, mining, building, defense }) {
  const { transaction_hash } = await account.execute([
    {
      contractAddress: CONFIG.gameSystemsAddress,
      entrypoint: 'assign_orders',
      calldata: [
        '0x' + BigInt(planetId).toString(16), // u64
        farming.toString(),                    // u8
        mining.toString(),                     // u8
        building.toString(),                   // u8
        defense.toString(),                    // u8
      ],
    },
  ])
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

/**
 * Convert a transaction hash (felt252 hex string) to a BigInt seed.
 * spawn_planet uses get_tx_info().transaction_hash as the planet seed.
 */
export function txHashToSeed(txHash) {
  return BigInt(txHash)
}
