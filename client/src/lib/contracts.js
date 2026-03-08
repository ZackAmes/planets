/**
 * Typed starknet.js Contract instances built from manifest ABIs.
 * Use these for reading onchain state (view calls).
 * For writes, use the populate() method with account.execute.
 */

import { Contract, RpcProvider, CallData, CairoOption, CairoOptionVariant, shortString } from 'starknet'
import manifest from '../../../contracts/manifest_sepolia.json'
import denshokan from '../../denshokan.json'
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
  return new Contract({
    abi: getAbi('planets-game_token_systems'),
    address: CONFIG.gameTokenSystemsAddress,
    providerOrAccount: providerOrAccount ?? getProvider(),
  })
}

export function rendererContract(providerOrAccount) {
  return new Contract({
    abi: getAbi('planets-renderer_systems'),
    address: CONFIG.rendererSystemsAddress,
    providerOrAccount: providerOrAccount ?? getProvider(),
  })
}

export function planetContract(providerOrAccount) {
  return new Contract({
    abi: getAbi('planets-planet_systems'),
    address: CONFIG.planetSystemsAddress,
    providerOrAccount: providerOrAccount ?? getProvider(),
  })
}

export function gameContract(providerOrAccount) {
  return new Contract({
    abi: getAbi('planets-game_systems'),
    address: CONFIG.gameSystemsAddress,
    providerOrAccount: providerOrAccount ?? getProvider(),
  })
}

const DENSHOKAN_ADDRESS = denshokan[0].address

// ---------------------------------------------------------------------------
// fetchDenshokanPlanets
//
// Uses ERC721Enumerable on the Denshokan contract to get all token IDs
// owned by a player. Returns an array of BigInt token IDs.
// ---------------------------------------------------------------------------

export async function fetchDenshokanPlanets(playerAddress) {
  const provider = getProvider()

  // balance_of(owner) → u256 (low, high)
  const balRes = await provider.callContract({
    contractAddress: DENSHOKAN_ADDRESS,
    entrypoint: 'balance_of',
    calldata: [playerAddress],
  })
  const balance = Number(BigInt(balRes[0]))
  if (balance === 0) return []

  // token_of_owner_by_index(owner, index: u256) → u256
  const ids = []
  for (let i = 0; i < balance; i++) {
    const res = await provider.callContract({
      contractAddress: DENSHOKAN_ADDRESS,
      entrypoint: 'token_of_owner_by_index',
      calldata: [playerAddress, i.toString(), '0x0'],
    })
    // u256 returned as [low, high]
    const id = BigInt(res[0]) + (BigInt(res[1] ?? 0) << 128n)
    ids.push(id)
  }

  // Filter to tokens that belong to this game's token contract
  const gameAddr = BigInt(CONFIG.gameTokenSystemsAddress)
  console.log('[fetchDenshokanPlanets] expected game address:', CONFIG.gameTokenSystemsAddress)
  const filtered = []
  for (const id of ids) {
    try {
      const res = await provider.callContract({
        contractAddress: DENSHOKAN_ADDRESS,
        entrypoint: 'token_game_address',
        calldata: [id.toString()],
      })
      const tokenGameAddr = BigInt(res[0])
      const match = tokenGameAddr === gameAddr
      console.log(`[fetchDenshokanPlanets] token ${id}: game_address=0x${tokenGameAddr.toString(16)} ${match ? '✓ kept' : '✗ filtered (wrong game)'}`)
      if (match) filtered.push(id)
    } catch (e) {
      console.warn(`[fetchDenshokanPlanets] token ${id}: token_game_address failed, skipping —`, e.message)
    }
  }
  console.log('[fetchDenshokanPlanets] result:', filtered.map(String))
  return filtered
}

// ---------------------------------------------------------------------------
// mintCall — raw Call for denshokan.mint (no ABI parsing needed)
// ---------------------------------------------------------------------------

const none = () => new CairoOption(CairoOptionVariant.None)
const some = (val) => new CairoOption(CairoOptionVariant.Some, val)

export function mintCall(playerAddress, playerName) {
  const nameFelt = playerName ? shortString.encodeShortString(playerName) : null
  return {
    contractAddress: DENSHOKAN_ADDRESS,
    entrypoint: 'mint',
    calldata: CallData.compile([
      CONFIG.gameTokenSystemsAddress,     // game_address
      nameFelt ? some(nameFelt) : none(), // player_name
      none(),                             // settings_id
      none(),                             // start
      none(),                             // end
      none(),                             // objective_id
      none(),                             // context
      none(),                             // client_url
      none(),                             // renderer_address
      none(),                             // skills_address
      playerAddress,                      // to
      false,                              // soulbound
      false,                              // paymaster
      0,                                  // salt
      0,                                  // metadata
    ]),
  }
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

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

function parsePlanet(p, planetId) {
  if (!p || BigInt(p.seed) === 0n) return null
  const seedBig = BigInt(p.seed)
  return {
    planetId: Number(planetId),
    seed: seedBig,
    seedJs: Number(seedBig % BigInt(2 ** 53)),
    width: Number(p.width),
    height: Number(p.height),
    name: p.name !== 0n ? shortString.decodeShortString('0x' + BigInt(p.name).toString(16)) : '',
    population: Number(p.population),
    actionCount: Number(p.action_count),
    spawnedAt: Number(BigInt(p.spawned_at)),
    lastActionAt: Number(BigInt(p.last_action_at)),
  }
}

function parseColony(c) {
  if (!c || !c.founded) return null
  return { col: Number(c.col), row: Number(c.row), founded: true, tcLevel: Number(c.tc_level) }
}

function parseResources(r) {
  return {
    water: Number(r.water), iron: Number(r.iron),
    defense: Number(r.defense), uranium: Number(r.uranium),
    lastUpdatedAt: Number(BigInt(r.last_updated_at)),
  }
}

function parseBuildings(arr) {
  return Array.from(arr).map((b) => ({
    lon: Number(b.lon), lat: Number(b.lat),
    buildingType: Number(b.building_type),
    level: Number(b.level),
    terrainBonus: Number(b.terrain_bonus),
    workers: Number(b.workers),
    maxWorkers: Number(b.max_workers),
    outputPerWorkerEpoch: Number(b.output_per_worker_epoch),
    completesAt: Number(BigInt(b.completes_at)),
  }))
}

function parseInvader(inv) {
  return {
    active: Boolean(inv.active), strength: Number(inv.strength),
    lon: Number(inv.lon), lat: Number(inv.lat),
    spawnedAt: Number(BigInt(inv.spawned_at)),
  }
}

// ---------------------------------------------------------------------------
// fetchFullState — single call for everything, used after every action
// ---------------------------------------------------------------------------

export async function fetchFullState(planetId) {
  try {
    const s = await planetContract().get_full_state(BigInt(planetId))
    const planet = parsePlanet(s.planet, planetId)
    if (!planet) return null
    return {
      planet,
      colony:    parseColony(s.colony),
      resources: parseResources(s.resources),
      assigned:  { count: Number(s.assigned_count) },
      unassigned:{ count: Number(s.unassigned_count), totalStrength: Number(s.unassigned_total_strength) },
      buildings: parseBuildings(s.buildings),
      invader:   parseInvader(s.invader),
      gear:      { weapons: Number(s.gear.weapons), armor: Number(s.gear.armor) },
    }
  } catch (e) {
    console.warn('[fetchFullState] error:', e)
    return null
  }
}

// ---------------------------------------------------------------------------
// Individual fetches (kept for targeted refreshes)
// ---------------------------------------------------------------------------

export async function fetchPlanet(planetId) {
  try {
    const p = await planetContract().get_planet(BigInt(planetId))
    const result = parsePlanet(p, planetId)
    if (!result) console.warn('[fetchPlanet] seed is 0 — not yet spawned')
    return result
  } catch (e) {
    console.warn('[fetchPlanet] error:', e)
    return null
  }
}

export async function fetchColony(planetId) {
  try {
    return parseColony(await planetContract().get_colony(BigInt(planetId)))
  } catch { return null }
}

export async function fetchBuildings(planetId) {
  try {
    return parseBuildings(await planetContract().get_planet_buildings(BigInt(planetId)))
  } catch { return [] }
}

export async function fetchResources(planetId) {
  try {
    return parseResources(await planetContract().get_resources(BigInt(planetId)))
  } catch { return null }
}

export async function fetchColonistsAssigned(planetId) {
  try {
    const ca = await planetContract().get_colonists_assigned(BigInt(planetId))
    return { count: Number(ca.count) }
  } catch { return null }
}

export async function fetchColonistsUnassigned(planetId) {
  try {
    const cu = await planetContract().get_colonists_unassigned(BigInt(planetId))
    return { count: Number(cu.count) }
  } catch { return null }
}

export async function fetchInvader(planetId) {
  try {
    return parseInvader(await planetContract().get_invader(BigInt(planetId)))
  } catch { return null }
}

export async function fetchGear(planetId) {
  try {
    const g = await planetContract().get_gear(BigInt(planetId))
    return { weapons: Number(g.weapons), armor: Number(g.armor) }
  } catch { return null }
}

// ---------------------------------------------------------------------------
// fetchPlayerPlanets
// ---------------------------------------------------------------------------

export async function fetchPlayerPlanets(playerAddress) {
  try {
    const ids = await planetContract().get_player_planets(playerAddress)
    return Array.from(ids).map((id) => BigInt(id))
  } catch { return [] }
}
