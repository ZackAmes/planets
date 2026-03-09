/**
 * Client-side game logic mirroring the Cairo contracts.
 * Used for optimistic local state simulation; the chain is the source of truth.
 */

import { hash } from 'starknet'

export const PLANET_WIDTH  = 50
export const PLANET_HEIGHT = 40

// Hex grid for colony placement (50x40)
export const LON_PER_HEX = 72   // 3600 / 50
export const LAT_PER_HEX = 45   // 1800 / 40

export const EPOCH_SECONDS = 120   // 2 minutes per epoch
export const MAX_EPOCHS    = 720   // cap at 24 hours

// Building type constants (must match BuildingType enum discriminants in Cairo)
export const BUILDING_TYPES = { TOWN_CENTER: 0, WATER_WELL: 1, IRON_MINE: 2, HOUSE: 3, BARRACKS: 4, URANIUM_MINE: 5, SPACEPORT: 6, WORKSHOP: 7, CANNON: 8 }

export const BUILDING_INFO = [
  { type: 0, name: 'Town Center',  color: '#ffdd44', ironCost: 0,   waterCost: 0,  uraniumCost: 0,   maxWorkers: 0, baseOutput: 0, resource: null,      minTcLevel: 1, description: 'Colony hub. Upgrade to expand building slots and raise max building level.' },
  { type: 1, name: 'Water Well',   color: '#44aaff', ironCost: 50,  waterCost: 0,  uraniumCost: 0,   maxWorkers: 1, baseOutput: 15, resource: 'water',  minTcLevel: 1, description: 'Water / worker / epoch (terrain: beach > plains > forest). Worker cap scales with level: 1 -> 2 -> 3.' },
  { type: 2, name: 'Iron Mine',    color: '#aaaaaa', ironCost: 80,  waterCost: 0,  uraniumCost: 0,   maxWorkers: 3, baseOutput: 8,  resource: 'iron',   minTcLevel: 1, description: 'Iron / worker / epoch (terrain: mountain > desert > forest)' },
  { type: 3, name: 'House',        color: '#44ff88', ironCost: 60,  waterCost: 50, uraniumCost: 0,   maxWorkers: 0, baseOutput: 0,  resource: null,     minTcLevel: 1, description: 'Spawns 1 new colonist immediately (requires pop below cap).' },
  { type: 4, name: 'Barracks',     color: '#4466ff', ironCost: 100, waterCost: 0,  uraniumCost: 0,   maxWorkers: 3, baseOutput: 0,  resource: null,     minTcLevel: 1, description: 'Trains assigned colonists: +level strength/epoch, up to max 10. Stronger fighters deal more damage in combat.' },
  { type: 5, name: 'Uranium Mine', color: '#bb44ff', ironCost: 200, waterCost: 0,  uraniumCost: 0,   maxWorkers: 3, baseOutput: 3,  resource: 'uranium',minTcLevel: 3, description: 'Uranium / worker / epoch. Required for high-tier upgrades. (terrain: mountain > desert)' },
  { type: 6, name: 'Spaceport',    color: '#ffffff', ironCost: 500, waterCost: 0,  uraniumCost: 0,   maxWorkers: 0, baseOutput: 0,  resource: null,     minTcLevel: 3, description: 'WIN CONDITION — launch your colony to the stars. Requires TC level 3.' },
  { type: 7, name: 'Workshop',     color: '#ff9933', ironCost: 120, waterCost: 0,  uraniumCost: 0,   maxWorkers: 0, baseOutput: 0,  resource: null,     minTcLevel: 2, description: 'Provides a passive defense bonus to your colony.' },
  { type: 8, name: 'Cannon',       color: '#ff4400', ironCost: 120, waterCost: 0,  uraniumCost: 0,   maxWorkers: 3, baseOutput: 6,  resource: 'defense',minTcLevel: 1, description: 'Produces defense/ep AND fires on active invaders each epoch, reducing their strength. (terrain: mountain > snow > plains)' },
]

/** Iron cost to upgrade TC from tcLevel → tcLevel+1 (max TC level 3) */
export function tcUpgradeCost(tcLevel) {
  return { iron: tcLevel * 100 }
}

/** Iron cost to upgrade a building from level → level+1 (max level 3) */
export function upgradeBuildingCost(level) {
  return { iron: 80 * level }
}

// Terrain type indices (match terrain.cairo) — simplified 7-biome set
// Types 0, 5, 9 are no longer generated but kept for array alignment
const TERRAIN_NAMES = [
  'Deep Ocean',  // 0 (unused)
  'Ocean',       // 1
  'Plains',      // 2 (merged grassland + scrubland)
  'Forest',      // 3
  'Desert',      // 4
  'Highland',    // 5 (unused — merged into mountain)
  'Mountain',    // 6 (merged highland + mountain)
  'Snow',        // 7
  'Beach',       // 8
  'Scrubland',   // 9 (unused — merged into plains)
]

// Unified client terrain grid (50x40)
const TERRAIN_GRID_COLS = PLANET_WIDTH
const TERRAIN_GRID_ROWS = PLANET_HEIGHT
const LON_PER_COL = LON_PER_HEX
const LAT_PER_ROW = LAT_PER_HEX

/**
 * Snap lon/lat to the colony hex center (50x40), used by found_colony(col,row).
 */
export function snapToHexCenter(lon, lat) {
  const safeLon = Math.min(3599, Math.max(0, lon))
  const safeLat = Math.min(1799, Math.max(0, lat))
  
  const col = Math.floor(safeLon / LON_PER_HEX)
  const row = Math.floor(safeLat / LAT_PER_HEX)
  const clampedCol = Math.min(PLANET_WIDTH - 1, Math.max(0, col))
  const clampedRow = Math.min(PLANET_HEIGHT - 1, Math.max(0, row))
  
  const centerLon = clampedCol * LON_PER_HEX + Math.floor(LON_PER_HEX / 2)
  const centerLat = clampedRow * LAT_PER_HEX + Math.floor(LAT_PER_HEX / 2)
  
  return { lon: centerLon, lat: centerLat, col: clampedCol, row: clampedRow }
}

/** Build/founding both use the same tile snap now. */
export const snapToTerrainTileCenter = snapToHexCenter

/** Get the four corners of a terrain tile in lon/lat. */
export function getTileBounds(col, row) {
  return {
    minLon: col * LON_PER_COL,
    maxLon: (col + 1) * LON_PER_COL,
    minLat: row * LAT_PER_ROW,
    maxLat: (row + 1) * LAT_PER_ROW,
  }
}

/**
 * Exact JS mirror of terrain.cairo's _cell_noise.
 * Uses starknet.js Poseidon so results are identical to the contract.
 * seed must be a BigInt (full felt252 planet seed).
 */
function cellNoise(seed, col, row, period) {
  const wrapped = BigInt(col % period)
  const h = hash.computePoseidonHashOnElements([seed, wrapped, BigInt(row)])
  return Number(BigInt(h) % 256n)
}

function gridElevation(seed, col, row) {
  const eContinent = cellNoise(seed,      Math.floor(col / 4), Math.floor(row / 4), 10) // coarse 2D
  const eRegional  = cellNoise(seed + 3n, col, row, 8)                                   // medium 2D
  const eLocal     = cellNoise(seed + 1n, col, row, TERRAIN_GRID_COLS)                   // fine 2D
  return Math.floor((eContinent * 5 + eRegional * 3 + eLocal * 2) / 10)
}

function gridMoisture(seed, col, row) {
  const mCoarse = cellNoise(seed + 7n,  col, Math.floor(row / 2), 10)
  const mMid    = cellNoise(seed + 11n, col, row, 5)
  const mFine   = cellNoise(seed + 13n, col, row, TERRAIN_GRID_COLS)
  return Math.floor((mCoarse * 5 + mMid * 3 + mFine * 2) / 10)
}

function classifyTerrainInt(elevation, moisture, row) {
  const polarBoost = (row === 0  || row === 39) ? 120
                   : (row === 1  || row === 38) ? 70
                   : (row === 2  || row === 37) ? 35
                   : (row === 3  || row === 36) ? 15
                   : 0
  const elev = Math.min(255, elevation + polarBoost)

  const tempFactor = (row === 0  || row === 39) ? 15
                   : (row === 1  || row === 38) ? 30
                   : (row === 2  || row === 37) ? 55
                   : (row === 3  || row === 36) ? 75
                   : (row === 4  || row === 35) ? 90
                   : 100
  const adjMoisture = Math.floor(moisture * tempFactor / 100)

  if (elev < 72)  return 1  // ocean
  if (elev < 87)  return 8  // beach
  if (elev < 210) {
    if (adjMoisture < 70)  return 4  // desert
    if (adjMoisture < 160) return 2  // plains
    return 3                         // forest
  }
  if (elev < 240) return 6  // mountain
  return 7  // snow
}

/**
 * Terrain type (0-9) at a given lon/lat on the unified client grid.
 * seed must be a BigInt (planet.seedFull — the full felt252 planet seed).
 * lat defaults to equator (900) for callers that don't have lat yet.
 */
export function terrainAt(seed, lon, lat = 900) {
  const s = typeof seed === 'bigint' ? seed : BigInt(seed)
  const col = Math.floor(lon / LON_PER_COL)
  const row = Math.floor(lat / LAT_PER_ROW)
  const elevation = gridElevation(s, col, row)
  const moisture  = gridMoisture(s, col, row)
  return classifyTerrainInt(elevation, moisture, row)
}

export function terrainName(terrainType) {
  return TERRAIN_NAMES[terrainType] ?? 'Unknown'
}

/** Returns false for ocean (type 1) — all other terrain is buildable. */
export function terrainCanBuild(terrainType) {
  return terrainType !== 1
}

/**
 * Terrain bonus (0-100) for a building type on a given terrain.
 * Mirrors terrain_bonus() in terrain.cairo.
 */
export function terrainBonus(buildingType, terrainType) {
  if (buildingType === BUILDING_TYPES.WATER_WELL) {
    if (terrainType === 8) return 100  // beach
    if (terrainType === 2) return 60   // plains
    if (terrainType === 3) return 30   // forest
    return 10
  }
  if (buildingType === BUILDING_TYPES.IRON_MINE) {
    if (terrainType === 6) return 100  // mountain
    if (terrainType === 4) return 40   // desert
    if (terrainType === 3) return 20   // forest
    return 5
  }
  if (buildingType === BUILDING_TYPES.CANNON) {
    if (terrainType === 6) return 70   // mountain
    if (terrainType === 7) return 40   // snow
    if (terrainType === 2) return 20   // plains
    return 10
  }
  if (buildingType === BUILDING_TYPES.URANIUM_MINE) {
    if (terrainType === 6) return 100  // mountain
    if (terrainType === 4) return 40   // desert
    return 5
  }
  return 0  // TownCenter, House, Spaceport have no terrain bonus
}

/** output per worker per epoch = base * (50 + bonus) / 100 */
export function buildingOutputPerWorkerEpoch(buildingType, bonus) {
  const base = BUILDING_INFO[buildingType]?.baseOutput ?? 0
  if (base === 0) return 0
  return Math.floor(base * (50 + bonus) / 100)
}

// ---------------------------------------------------------------------------
// Threat
// ---------------------------------------------------------------------------

/**
 * Compute the threat level (0-100).
 * Mirrors the threat calculation in game/contracts.cairo.
 */
export function computeThreat(planet, resources, nowSeconds) {
  const timeAlive = nowSeconds - (planet.spawnedAt ?? 0)
  // Threat builds faster - time component doubled (was /10, now /5)
  const timeComp   = Math.floor((timeAlive / EPOCH_SECONDS) / 5)
  // Resources matter more - wealth component doubled (was /100, now /50)
  const wealthComp = Math.floor((resources?.iron ?? 0) / 50)
  // Population matters more (was /20, now /3 to match contract)
  const sizeComp   = Math.floor(planet.population / 3)
  return Math.min(100, timeComp + wealthComp + sizeComp)
}

export function attackProbability(threat) {
  // Spawn threshold is now 50% of threat (was 33%)
  return Math.floor(threat * 50 / 100)
}

// ---------------------------------------------------------------------------
// Building construction preview
// ---------------------------------------------------------------------------

export function previewConstruct(resources, buildingType, seedFull, lon, lat) {
  const info = BUILDING_INFO[buildingType]
  if (!info) return { canBuild: false, reason: 'Unknown building type' }

  const terrain = terrainAt(seedFull, lon, lat)

  if (!terrainCanBuild(terrain)) {
    return { canBuild: false, reason: 'Cannot build on ocean', terrain, terrainName: terrainName(terrain), bonus: 0, output: 0 }
  }

  const bonus   = terrainBonus(buildingType, terrain)
  const output  = buildingOutputPerWorkerEpoch(buildingType, bonus)

  const hasIron    = (resources?.iron    ?? 0) >= info.ironCost
  const hasWater   = (resources?.water   ?? 0) >= (info.waterCost   ?? 0)
  const hasUranium = (resources?.uranium ?? 0) >= (info.uraniumCost ?? 0)
  const canBuild   = hasIron && hasWater && hasUranium
  const reason = !hasIron    ? `Need ${info.ironCost} iron (have ${resources?.iron ?? 0})`
               : !hasWater   ? `Need ${info.waterCost} water (have ${resources?.water ?? 0})`
               : !hasUranium ? `Need ${info.uraniumCost} uranium (have ${resources?.uranium ?? 0})`
               : null
  return {
    canBuild, reason,
    ironCost: info.ironCost, uraniumCost: info.uraniumCost ?? 0,
    terrain, terrainName: terrainName(terrain), bonus, output,
  }
}

// ---------------------------------------------------------------------------
// Production rates (computed client-side from buildings)
// ---------------------------------------------------------------------------

export function computeRates(buildings, population) {
  let waterRate = 0, ironRate = 0, defenseRate = 0, uraniumRate = 0, cannonDamageRate = 0
  for (const b of buildings) {
    const w = b.workers ?? 0
    if (b.buildingType === 1) waterRate   += w * (b.outputPerWorkerEpoch ?? 0)
    if (b.buildingType === 2) ironRate    += w * (b.outputPerWorkerEpoch ?? 0)
    if (b.buildingType === 5) uraniumRate += w * (b.outputPerWorkerEpoch ?? 0)
    if (b.buildingType === 8) {
      defenseRate      += w * (b.outputPerWorkerEpoch ?? 0)
      cannonDamageRate += w * (b.outputPerWorkerEpoch ?? 0)
    }
  }
  const waterConsumed = (population ?? 0) * 5
  return { waterRate, ironRate, defenseRate, uraniumRate, cannonDamageRate, waterConsumed, netWater: waterRate - waterConsumed }
}

// ---------------------------------------------------------------------------
// Combat
// ---------------------------------------------------------------------------

export const COLONIST_DEFAULT_STRENGTH = 2
export const COLONIST_MAX_STRENGTH = 10

/**
 * Preview fight outcome before sending the tx.
 * avgStrength: average strength of unassigned colonists (default COLONIST_DEFAULT_STRENGTH).
 * Returns { willWin, fighterPower, invaderStrength, estimatedCasualties }.
 */
export function previewFight(invader, colonists, avgStrength) {
  const str = avgStrength ?? COLONIST_DEFAULT_STRENGTH
  const fighterPower = colonists * str
  const willWin = fighterPower >= invader.strength
  const estimatedCasualties = willWin
    ? Math.floor(invader.strength / 20)
    : Math.min(colonists, Math.floor((invader.strength - fighterPower) / 5) + 1)
  return { willWin, fighterPower, invaderStrength: invader.strength, estimatedCasualties }
}

// ---------------------------------------------------------------------------
// Coordinate utilities
// ---------------------------------------------------------------------------

export function lonLatToLocal(lon, lat, radius = 8.15) {
  // Convert lon/lat (in the range 0-3599 and 0-1799) to radians
  // lon: 0-3599 maps to 0-2π (full circle around equator)
  // lat: 0-1799 maps to π-0 (from north pole to south pole in scene orientation)
  // Add π/2 offset to phi to align with texture UV mapping
  const phi   = (lon / 3600) * Math.PI * 2 + Math.PI / 2  // longitude: 0 to 2π, offset by 90°
  const theta = (1 - lat / 1800) * Math.PI                 // latitude: 0 (north) to π (south)
  
  return [
    -Math.sin(phi) * Math.sin(theta) * radius,
     Math.cos(theta) * radius,
     Math.cos(phi) * Math.sin(theta) * radius,
  ]
}

export function uvToLonLat(uvX, uvY) {
  // UV coordinates: uvX (0-1) is longitude, uvY (0-1) is latitude
  // Match lonLatToLocal(): uvY=0 => lat=0 (north pole), uvY=1 => lat=1799 (south pole)
  // Flip uvX so longitude increases left-to-right (west to east)
  // Use 3599 and 1799 as max to ensure we stay in bounds (0-3599, 0-1799)
  const lon = Math.min(3599, Math.max(0, Math.floor((1 - uvX) * 3600)))
  const lat = Math.min(1799, Math.max(0, Math.floor(uvY * 1800)))
  return { lon, lat }
}

export function formatLonLat(lon, lat) {
  return `${(lon / 10).toFixed(1)}°E · ${(lat / 10).toFixed(1)}°`
}
