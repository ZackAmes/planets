/**
 * Contract interaction helpers.
 * Each function takes a starknet.js WalletAccount and returns
 * { transaction_hash } on success, or throws on failure.
 *
 * Cairo u64/u32/u8 values all serialize as single felt252 in calldata.
 * felt252 (e.g. names) can be passed as hex strings or BigInts.
 */

import { shortString } from 'starknet'
import { CONFIG } from './config.js'

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
 * Terrain bonuses are derived onchain from poseidon(seed, col, row).
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
 * Returns the receipt.
 */
export async function waitForTx(provider, txHash) {
  return provider.waitForTransaction(txHash, {
    retryInterval: 1500,
    successStates: ['ACCEPTED_ON_L2', 'SUCCEEDED'],
  })
}

/**
 * Convert a transaction hash (felt252 hex string) to a BigInt seed.
 * This is valid because spawn_planet uses get_tx_info().transaction_hash as seed.
 */
export function txHashToSeed(txHash) {
  return BigInt(txHash)
}
