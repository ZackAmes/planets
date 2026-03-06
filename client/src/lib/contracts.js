/**
 * Typed starknet.js Contract instances built from manifest ABIs.
 * Use these for reading onchain state (view calls).
 * For writes, use the populate() method with account.execute.
 */

import { Contract, RpcProvider, CairoOption, CairoOptionVariant, shortString } from 'starknet'
import manifest from '../../../contracts/manifest_sepolia.json'
import { CONFIG } from './config.js'

// ---------------------------------------------------------------------------
// Provider singleton
// ---------------------------------------------------------------------------

let _provider = null
export function getProvider() {
  if (!_provider) _provider = new RpcProvider({ nodeUrl: CONFIG.rpcUrl })
  return _provider
}

// ---------------------------------------------------------------------------
// ABI helpers
// ---------------------------------------------------------------------------

function getAbi(tag) {
  const entry = manifest.contracts.find((c) => c.tag === tag)
  if (!entry) throw new Error(`Contract not found in manifest: ${tag}`)
  return entry.abi
}

// ---------------------------------------------------------------------------
// Contract factories
// ---------------------------------------------------------------------------

export function gameTokenContract(providerOrAccount) {
  return new Contract(
    getAbi('planets-game_token_systems'),
    CONFIG.gameTokenSystemsAddress,
    providerOrAccount ?? getProvider(),
  )
}

export function rendererContract(providerOrAccount) {
  return new Contract(
    getAbi('planets-renderer_systems'),
    CONFIG.rendererSystemsAddress,
    providerOrAccount ?? getProvider(),
  )
}

// ---------------------------------------------------------------------------
// None helper — CairoOption::None for any type
// ---------------------------------------------------------------------------

const None = new CairoOption(CairoOptionVariant.None)

// ---------------------------------------------------------------------------
// mint_game
//
// Returns { call, tokenId }:
//   call    — populated Call object ready for account.execute
//   tokenId — BigInt token ID (from view simulation, deterministic)
//
// mint_game is view (self: @ContractState) and dispatches to the token
// contract externally, so we can sim-call it to get the token ID before
// executing the transaction.
// ---------------------------------------------------------------------------

export async function prepareMintGame(account, playerName) {
  const nameFelt = playerName ? shortString.encodeShortString(playerName) : null
  const salt = Math.floor(Date.now() / 1000) % 65536  // u16, changes once/sec

  const args = [
    nameFelt ? new CairoOption(CairoOptionVariant.Some, nameFelt) : None, // player_name
    None, // settings_id
    None, // start
    None, // end
    None, // objective_id
    None, // context
    None, // client_url
    None, // renderer_address
    None, // skills_address
    account.address,  // to
    false,            // soulbound
    false,            // paymaster
    salt,             // salt
    0,                // metadata
  ]

  // View call to get the deterministic token ID
  const contract = gameTokenContract(getProvider())
  const tokenIdFelt = await contract.mint_game(...args)
  const tokenId = BigInt(tokenIdFelt)

  // Build the Call for account.execute
  const call = gameTokenContract(account).populate('mint_game', args)

  return { call, tokenId, salt }
}

// ---------------------------------------------------------------------------
// fetchPlanetDetails
//
// Reads planet state from renderer_systems.game_details (GameDetail array).
// Returns { population, turns, seed } or null.
// ---------------------------------------------------------------------------

export async function fetchPlanetDetails(planetId) {
  try {
    const contract = rendererContract()
    const details = await contract.game_details(BigInt(planetId))
    const result = {}
    for (const d of details) {
      const name = shortString.decodeShortString('0x' + d.name.toString(16))
      result[name.toLowerCase()] = Number(d.value)
    }
    return result  // { population: N, turns: N, seed: N }
  } catch {
    return null
  }
}

// ---------------------------------------------------------------------------
// fetchPlanet
//
// Reads the full Planet model from renderer_systems.get_planet.
// Returns a plain JS object or null if the planet hasn't been spawned.
// ---------------------------------------------------------------------------

export async function fetchPlanet(planetId) {
  try {
    const contract = rendererContract()
    const p = await contract.get_planet(BigInt(planetId))
    if (!p || BigInt(p.population) === 0n && BigInt(p.seed) === 0n) return null
    return {
      planetId: Number(planetId),
      seed: p.seed,
      seedJs: Number(BigInt(p.seed) % BigInt(2 ** 53)),
      width: Number(p.width),
      height: Number(p.height),
      name: shortString.decodeShortString('0x' + BigInt(p.name).toString(16)),
      population: Number(p.population),
      actionCount: Number(p.action_count),
      spawnedAt: Number(BigInt(p.spawned_at)),
      lastActionAt: Number(BigInt(p.last_action_at)),
    }
  } catch {
    return null
  }
}

// ---------------------------------------------------------------------------
// fetchColony
//
// Reads the Colony model from renderer_systems.get_colony.
// Returns a plain JS object or null if the colony hasn't been founded.
// ---------------------------------------------------------------------------

export async function fetchColony(planetId) {
  try {
    const contract = rendererContract()
    const c = await contract.get_colony(BigInt(planetId))
    if (!c || !c.founded) return null
    return {
      col: Number(c.col),
      row: Number(c.row),
      founded: Boolean(c.founded),
      food: Number(c.food),
      minerals: Number(c.minerals),
      buildPoints: Number(c.build_points),
      defense: Number(c.defense),
      fertility: Number(c.fertility),
      mineralRichness: Number(c.mineral_richness),
      farms: Number(c.farms),
      mines: Number(c.mines),
      barracks: Number(c.barracks),
      workshops: Number(c.workshops),
      farmOutput: Number(c.farm_output),
      mineOutput: Number(c.mine_output),
      barracksOutput: Number(c.barracks_output),
      workshopOutput: Number(c.workshop_output),
    }
  } catch {
    return null
  }
}

// ---------------------------------------------------------------------------
// fetchBuildings
//
// Reads all buildings on a planet from renderer_systems.get_planet_buildings.
// Returns an array of { lon, lat, buildingType } objects.
// buildingType: 0=Farm, 1=Mine, 2=Barracks, 3=Workshop
// ---------------------------------------------------------------------------

export async function fetchBuildings(planetId) {
  try {
    const contract = rendererContract()
    const buildings = await contract.get_planet_buildings(BigInt(planetId))
    return Array.from(buildings).map((b) => ({
      lon: Number(b.lon),
      lat: Number(b.lat),
      buildingType: Number(b.building_type),
      terrainBonus: Number(b.terrain_bonus),
      outputPerEpoch: Number(b.output_per_epoch),
    }))
  } catch {
    return []
  }
}

// ---------------------------------------------------------------------------
// fetchPlayerPlanets
//
// Reads all planet IDs for a player from renderer_systems.get_player_planets.
// Returns an array of BigInt planet IDs, or [] if none.
// ---------------------------------------------------------------------------

export async function fetchPlayerPlanets(playerAddress) {
  try {
    const contract = rendererContract()
    const ids = await contract.get_player_planets(playerAddress)
    // ids is an Array<bigint> from the contract
    return Array.from(ids).map((id) => BigInt(id))
  } catch {
    return []
  }
}
