/**
 * Contract write helpers using starknet.js typedv2 / contract.populate().
 * populate() uses the ABI to serialize named-object args — no manual calldata arrays.
 */

import { CairoCustomEnum, CallData, shortString } from 'starknet'
import { CONFIG } from './config.js'
import { mintCall, getProvider, fetchDenshokanPlanets, planetContract, gameContract } from './contracts.js'

// Cartridge VRF provider — same address on mainnet and sepolia.
// Kept as raw calldata since VRF ABI isn't in our manifest.
const VRF_ADDRESS = '0x051fea4450da9d6aee758bdeba88b2f665bcbf549d2c61421aa724e9ac0ced8f'

// ---------------------------------------------------------------------------
// denshokan — mint
// ---------------------------------------------------------------------------

let BUILDING_TYPES = [
  new CairoCustomEnum({ TownCenter: {} }),
  new CairoCustomEnum({ TownCenter: undefined, WaterWell: {} }),
  new CairoCustomEnum({ TownCenter: undefined, WaterWell: undefined, IronMine: {} }),
  new CairoCustomEnum({ TownCenter: undefined, WaterWell: undefined, IronMine: undefined, House: {} }),
  new CairoCustomEnum({ TownCenter: undefined, WaterWell: undefined, IronMine: undefined, House: undefined, Barracks: {} }),
  new CairoCustomEnum({ TownCenter: undefined, WaterWell: undefined, IronMine: undefined, House: undefined, Barracks: undefined, UraniumMine: {} }),
  new CairoCustomEnum({ TownCenter: undefined, WaterWell: undefined, IronMine: undefined, House: undefined, Barracks: undefined, UraniumMine: undefined, Spaceport: {} }),
  new CairoCustomEnum({ TownCenter: undefined, WaterWell: undefined, IronMine: undefined, House: undefined, Barracks: undefined, UraniumMine: undefined, Spaceport: undefined, Workshop: {} }),
  new CairoCustomEnum({ TownCenter: undefined, WaterWell: undefined, IronMine: undefined, House: undefined, Barracks: undefined, UraniumMine: undefined, Spaceport: undefined, Workshop: undefined, Cannon: {} }),
]
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
 * Spawn a planet. Cartridge VRF requires request_random first in the same
 * multicall. request_random uses raw calldata since VRF ABI isn't local;
 * spawn_planet uses populate() for type-safe encoding.
 */
export async function spawnPlanet(account, planetId, name) {
  const pc = planetContract()
  const calls = [
    // 1. Seed the VRF — raw calldata (external contract, no local ABI)
    {
      contractAddress: VRF_ADDRESS,
      entrypoint: 'request_random',
      calldata: CallData.compile([
        CONFIG.planetSystemsAddress, // caller: the contract that calls consume_random
        '0',                         // Source::Nonce discriminant
        account.address,             // Source::Nonce(player_address)
      ]),
    },
    // 2. Spawn — consume_random(Source::Nonce(player_address)) called internally
    pc.populate('spawn_planet', {
      planet_id: planetId,
      name: shortString.encodeShortString(name),
    }),
  ]

  console.log('[spawnPlanet] calls:', JSON.stringify(calls, null, 2))
  const result = await account.execute(calls)
  console.log('[spawnPlanet] tx hash:', result.transaction_hash)
  const receipt = await waitForTx(getProvider(), result.transaction_hash)
  console.log('[spawnPlanet] receipt:', receipt)
}

// ---------------------------------------------------------------------------
// game_systems
// ---------------------------------------------------------------------------

export async function foundColony(account, planetId, col, row) {
  const gc = gameContract()
  const { transaction_hash } = await account.execute(
    gc.populate('found_colony', { planet_id: planetId, col, row })
  )
  return transaction_hash
}

export async function constructBuilding(account, planetId, lon, lat, buildingType) {
  console.log(buildingType)
  let building = BUILDING_TYPES[buildingType]
  console.log(building)
  const gc = gameContract()
  let args = { planet_id: planetId, lon, lat, building_type: building }
  console.log(args)
  const { transaction_hash } = await account.execute({
    contractAddress: gc.address,
    entrypoint: 'construct_building',
    calldata: CallData.compile(args)
  })
  return transaction_hash
}

export async function assignWorkers(account, planetId, lon, lat, workers) {
  const gc = gameContract()
  const { transaction_hash } = await account.execute(
    gc.populate('assign_workers', { planet_id: planetId, lon, lat, workers })
  )
  await waitForTx(getProvider(), transaction_hash)
  return transaction_hash
}

export async function upgradeTc(account, planetId) {
  const gc = gameContract()
  const { transaction_hash } = await account.execute(
    gc.populate('upgrade_tc', { planet_id: planetId })
  )
  await waitForTx(getProvider(), transaction_hash)
  return transaction_hash
}

export async function upgradeBuilding(account, planetId, lon, lat) {
  const gc = gameContract()
  const { transaction_hash } = await account.execute(
    gc.populate('upgrade_building', { planet_id: planetId, lon, lat })
  )
  await waitForTx(getProvider(), transaction_hash)
  return transaction_hash
}

export async function fightInvader(account, planetId, colonists) {
  const gc = gameContract()
  const { transaction_hash } = await account.execute(
    gc.populate('fight_invader', { planet_id: planetId, colonists })
  )
  await waitForTx(getProvider(), transaction_hash)
  return transaction_hash
}

export async function collect(account, planetId) {
  const gc = gameContract()
  const { transaction_hash } = await account.execute(
    gc.populate('collect', { planet_id: planetId })
  )
  await waitForTx(getProvider(), transaction_hash)
  return transaction_hash
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

export async function waitForTx(provider, txHash) {
  return provider.waitForTransaction(txHash, {
    retryInterval: 1500,
    successStates: ['ACCEPTED_ON_L2', 'SUCCEEDED'],
  })
}
