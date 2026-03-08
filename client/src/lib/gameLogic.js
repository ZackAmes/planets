/**
 * Client-side game logic mirroring the Cairo contracts.
 * Used for optimistic local state simulation; the chain is the source of truth.
 */

import { hash } from 'starknet'

export const PLANET_WIDTH  = 50
export const PLANET_HEIGHT = 40

export const EPOCH_SECONDS = 600   // 10 minutes per epoch
export const MAX_EPOCHS    = 144   // cap at 24 hours

// Building type constants (must match BuildingType enum discriminants in Cairo)
export const BUILDING_TYPES = { TOWN_CENTER: 0, WATER_WELL: 1, IRON_MINE: 2, HOUSE: 3, BARRACKS: 4 }

export const BUILDING_INFO = [
  { type: 0, name: 'Town Center', color: '#ffdd44', ironCost: 0,   waterCost: 0,  maxWorkers: 0, baseOutput: 0,  resource: null,      description: 'Colony hub. Upgrade to raise the population cap.' },
  { type: 1, name: 'Water Well',  color: '#44aaff', ironCost: 50,  waterCost: 0,  maxWorkers: 3, baseOutput: 10, resource: 'water',   description: 'Water / worker / epoch (terrain: coastal > beach > scrubland)' },
  { type: 2, name: 'Iron Mine',   color: '#aaaaaa', ironCost: 80,  waterCost: 0,  maxWorkers: 3, baseOutput: 8,  resource: 'iron',    description: 'Iron / worker / epoch (terrain: mountain > highland > desert)' },
  { type: 3, name: 'House',       color: '#44ff88', ironCost: 60,  waterCost: 50, maxWorkers: 0, baseOutput: 0,  resource: null,      description: 'Spawns 1 new colonist immediately (requires pop below cap).' },
  { type: 4, name: 'Barracks',    color: '#4466ff', ironCost: 100, waterCost: 0,  maxWorkers: 3, baseOutput: 8,  resource: 'defense', description: 'Defense / worker / epoch (terrain: mountain > highland)' },
]

export const TC_UPGRADE_COST = (tcLevel) => tcLevel * 100 // iron cost to upgrade TC

// Terrain type indices (match terrain.cairo)
const TERRAIN_NAMES = [
  'Deep Ocean', 'Shallow Ocean', 'Grassland', 'Forest', 'Desert',
  'Highland', 'Mountain', 'Snow', 'Beach', 'Scrubland',
]

// Grid dimensions — must match terrain.cairo constants
const TERRAIN_GRID_COLS = 20
const TERRAIN_GRID_ROWS = 10
const LON_PER_COL = 180  // 3600 / 20
const LAT_PER_ROW = 180  // 1800 / 10

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
  const cCol = Math.floor(col * 5 / TERRAIN_GRID_COLS)
  const cRow = Math.floor(row / 2)
  const eCoarse = cellNoise(seed,        cCol, cRow, 5)
  const eFine   = cellNoise(seed + 1n,   col,  row,  TERRAIN_GRID_COLS)
  return Math.floor((eCoarse * 6 + eFine * 4) / 10)
}

function gridMoisture(seed, col, row) {
  const cCol = Math.floor(col * 5 / TERRAIN_GRID_COLS)
  const cRow = Math.floor(row / 2)
  const mCoarse = cellNoise(seed + 7n,  cCol, cRow, 5)
  const mFine   = cellNoise(seed + 13n, col,  row,  TERRAIN_GRID_COLS)
  return Math.floor((mCoarse * 7 + mFine * 3) / 10)
}

function classifyTerrainInt(elevation, moisture, row) {
  const polarBoost = (row === 0 || row === 9) ? 100
                   : (row === 1 || row === 8) ? 50
                   : (row === 2 || row === 7) ? 20
                   : 0
  const elev = Math.min(255, elevation + polarBoost)
  if (elev < 64)  return 0  // deep ocean
  if (elev < 82)  return 1  // shallow ocean
  if (elev < 97)  return 8  // beach
  if (elev < 192) {
    if (moisture < 64)  return 4  // desert
    if (moisture < 102) return 9  // scrubland
    if (moisture < 140) return elev > 153 ? 5 : 2  // highland or grassland
    return 3  // forest
  }
  if (elev < 222) return 6  // mountain
  return 7  // snow
}

/**
 * Terrain type (0-9) at a given lon/lat. Exact match to terrain.cairo terrain_at().
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

/**
 * Terrain bonus (0-100) for a building type on a given terrain.
 * Mirrors terrain_bonus() in terrain.cairo.
 */
export function terrainBonus(buildingType, terrainType) {
  if (buildingType === BUILDING_TYPES.WATER_WELL) {
    if (terrainType === 1) return 100  // shallow ocean (coastal)
    if (terrainType === 8) return 80   // beach
    if (terrainType === 9) return 60   // scrubland
    if (terrainType === 2) return 40   // grassland
    if (terrainType === 3) return 30   // forest
    return 10
  }
  if (buildingType === BUILDING_TYPES.IRON_MINE) {
    if (terrainType === 6) return 100  // mountain
    if (terrainType === 5) return 70   // highland
    if (terrainType === 4) return 40   // desert
    if (terrainType === 3) return 20   // forest
    return 5
  }
  if (buildingType === BUILDING_TYPES.BARRACKS) {
    if (terrainType === 6) return 60   // mountain
    if (terrainType === 5) return 50   // highland
    if (terrainType === 7) return 40   // snow
    if (terrainType === 3) return 30   // forest
    return 20
  }
  return 0  // TownCenter and House have no terrain bonus
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
  const timeComp   = Math.floor((timeAlive / EPOCH_SECONDS) / 10)
  const wealthComp = Math.floor((resources?.iron ?? 0) / 100)
  const sizeComp   = Math.floor(planet.population / 20)
  return Math.min(100, timeComp + wealthComp + sizeComp)
}

export function attackProbability(threat) {
  return Math.floor(threat * 80 / 100)
}

// ---------------------------------------------------------------------------
// Building construction preview
// ---------------------------------------------------------------------------

export function previewConstruct(resources, buildingType, seedFull, lon, lat) {
  const info = BUILDING_INFO[buildingType]
  if (!info) return { canBuild: false, reason: 'Unknown building type' }

  const terrain = terrainAt(seedFull, lon, lat)
  const bonus   = terrainBonus(buildingType, terrain)
  const output  = buildingOutputPerWorkerEpoch(buildingType, bonus)

  const hasIron  = (resources?.iron  ?? 0) >= info.ironCost
  const hasWater = (resources?.water ?? 0) >= (info.waterCost ?? 0)
  const canBuild = hasIron && hasWater
  const reason = !hasIron  ? `Need ${info.ironCost} iron (have ${resources?.iron ?? 0})`
               : !hasWater ? `Need ${info.waterCost} water (have ${resources?.water ?? 0})`
               : null
  return {
    canBuild, reason,
    ironCost: info.ironCost,
    terrain, terrainName: terrainName(terrain), bonus, output,
  }
}

// ---------------------------------------------------------------------------
// Production rates (computed client-side from buildings)
// ---------------------------------------------------------------------------

export function computeRates(buildings, population) {
  let waterRate = 0, ironRate = 0, defenseRate = 0
  for (const b of buildings) {
    const w = b.workers ?? 0
    if (b.buildingType === 1) waterRate  += w * (b.outputPerWorkerEpoch ?? 0)
    if (b.buildingType === 2) ironRate   += w * (b.outputPerWorkerEpoch ?? 0)
    if (b.buildingType === 4) defenseRate += w * (b.outputPerWorkerEpoch ?? 0)
  }
  const waterConsumed = population ?? 0
  return { waterRate, ironRate, defenseRate, waterConsumed, netWater: waterRate - waterConsumed }
}

// ---------------------------------------------------------------------------
// Gear / combat
// ---------------------------------------------------------------------------

export const WEAPON_COST = 20   // iron
export const ARMOR_COST  = 30   // iron

export const COLONIST_BASE_POWER = 10
export const WEAPON_POWER = 5
export const ARMOR_POWER  = 3

/**
 * Preview fight outcome before sending the tx.
 * Returns { willWin, fighterPower, invaderStrength, estimatedCasualties }.
 */
export function previewFight(invader, colonists, weapons, armor) {
  const fighterPower = colonists * COLONIST_BASE_POWER + weapons * WEAPON_POWER + armor * ARMOR_POWER
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
  const phi   = (lon / 3600) * Math.PI * 2
  const theta = (lat / 1800) * Math.PI
  return [
    -Math.sin(phi) * Math.sin(theta) * radius,
     Math.cos(theta) * radius,
     Math.cos(phi) * Math.sin(theta) * radius,
  ]
}

export function uvToLonLat(uvX, uvY) {
  return {
    lon: Math.min(3599, Math.floor(uvX * 3600)),
    lat: Math.min(1799, Math.floor((1 - uvY) * 1800)),
  }
}

export function formatLonLat(lon, lat) {
  return `${(lon / 10).toFixed(1)}°E · ${(lat / 10).toFixed(1)}°`
}
