/**
 * Client-side game logic mirroring the Cairo contracts.
 * Used for optimistic local state simulation; the chain is the source of truth.
 */

export const PLANET_WIDTH  = 50
export const PLANET_HEIGHT = 40

export const EPOCH_SECONDS = 600   // 10 minutes per epoch
export const MAX_EPOCHS    = 144   // cap at 24 hours

// Building type constants (must match BuildingType enum discriminants in Cairo)
export const BUILDING_TYPES = { FARM: 0, MINE: 1, BARRACKS: 2, WORKSHOP: 3 }

export const BUILDING_INFO = [
  { type: 0, name: 'Farm',     color: '#4aaa44', mineralCost: 100, buildCost: 75,  baseOutput: 20, resource: 'food',        description: 'Food / epoch (terrain: grassland > forest > marsh)' },
  { type: 1, name: 'Mine',     color: '#aaaaaa', mineralCost: 150, buildCost: 75,  baseOutput: 15, resource: 'minerals',    description: 'Minerals / epoch (terrain: mountain > highland > desert)' },
  { type: 2, name: 'Barracks', color: '#4466ff', mineralCost: 150, buildCost: 125, baseOutput: 20, resource: 'defense',     description: 'Defense / epoch (terrain: mountain > highland)' },
  { type: 3, name: 'Workshop', color: '#ffaa22', mineralCost: 200, buildCost: 150, baseOutput: 10, resource: 'buildPoints', description: 'Build pts / epoch (terrain: forest > grassland)' },
]

// Terrain type indices (mirror renderer_utils._terrain_color indices)
const TERRAIN_NAMES = [
  'Deep Ocean', 'Shallow Ocean', 'Grassland', 'Forest', 'Desert',
  'Highland', 'Mountain', 'Snow', 'Beach', 'Marsh',
]

/** 8 terrain strips on the planet, each covering lon/3600 × 450 = 450 lon units wide */
const STRIP_WIDTH_LON = 450  // 3600 / 8 strips

/** Simple hash (not cryptographic — client preview only, not identical to Poseidon). */
function clientHash(a, b) {
  let h = (a ^ (b * 0x9e3779b9)) >>> 0
  h = Math.imul(h ^ (h >>> 16), 0x45d9f3b) >>> 0
  h = Math.imul(h ^ (h >>> 16), 0x45d9f3b) >>> 0
  return (h ^ (h >>> 16)) >>> 0
}

/** Extract byte at position byteOffset from a BigInt (simulating u256 seed). */
function seedByte(seed, byteOffset) {
  return Number((seed >> BigInt(byteOffset * 8)) & 0xffn)
}

/**
 * Determine the terrain type (0-9) at a given lon (0-3599) using the planet seed.
 * Mirrors the strip generation in renderer_utils.cairo.
 */
export function terrainAt(seed, lon) {
  const stripIndex = Math.floor(lon / STRIP_WIDTH_LON)  // 0-7
  const byteVal = seedByte(BigInt(seed), stripIndex * 4)
  return byteVal % 10
}

export function terrainName(terrainType) {
  return TERRAIN_NAMES[terrainType] ?? 'Unknown'
}

/**
 * Terrain bonus (0-100) for a building type on a given terrain.
 * Mirrors _terrain_bonus() in game/contracts.cairo.
 */
export function terrainBonus(buildingType, terrainType) {
  if (buildingType === BUILDING_TYPES.FARM) {
    if (terrainType === 2) return 100   // grassland
    if (terrainType === 3) return 60    // forest
    if (terrainType === 9) return 40    // marsh
    if (terrainType === 8) return 30    // beach
    if (terrainType === 5) return 20    // highland
    if (terrainType === 4) return 10    // desert
    return 5
  }
  if (buildingType === BUILDING_TYPES.MINE) {
    if (terrainType === 6) return 100   // mountain
    if (terrainType === 5) return 70    // highland
    if (terrainType === 4) return 40    // desert
    if (terrainType === 3) return 20    // forest
    return 5
  }
  if (buildingType === BUILDING_TYPES.BARRACKS) {
    if (terrainType === 6) return 60    // mountain
    if (terrainType === 5) return 50    // highland
    if (terrainType === 7) return 40    // snow
    if (terrainType === 3) return 30    // forest
    return 20
  }
  // Workshop
  if (terrainType === 3) return 50      // forest
  if (terrainType === 2) return 40      // grassland
  if (terrainType === 8) return 30      // beach
  return 20
}

/** output per epoch = base × (50 + bonus) / 100 */
export function buildingOutputPerEpoch(buildingType, bonus) {
  const base = BUILDING_INFO[buildingType].baseOutput
  return Math.floor(base * (50 + bonus) / 100)
}

// ---------------------------------------------------------------------------
// Colony founding
// ---------------------------------------------------------------------------

export function deriveTerrainBonuses(seed, col, row) {
  const h = clientHash(clientHash(seed, col), row)
  return { fertility: h % 101, mineralRichness: Math.floor(h / 256) % 101 }
}

export function foundColony(planet, col, row) {
  const { fertility, mineralRichness } = deriveTerrainBonuses(planet.seed, col, row)
  return {
    col, row, founded: true,
    food: 500, minerals: 200, buildPoints: 0, defense: 20,
    fertility, mineralRichness,
    farms: 0, mines: 0, barracks: 0, workshops: 0,
    farmOutput: 0, mineOutput: 0, barracksOutput: 0, workshopOutput: 0,
  }
}

// ---------------------------------------------------------------------------
// Threat
// ---------------------------------------------------------------------------

/**
 * Compute the threat level (0–100).
 * Mirrors the assign_orders threat calculation in game/contracts.cairo.
 */
export function computeThreat(planet, colony, nowSeconds) {
  const EPOCH = EPOCH_SECONDS
  const timeAlive = nowSeconds - (planet.spawnedAt ?? 0)
  const timeComp   = Math.floor((timeAlive / EPOCH) / 10)
  const wealthComp = Math.floor((colony.food + colony.minerals) / 100)
  const sizeComp   = Math.floor(planet.population / 20)
  return Math.min(100, timeComp + wealthComp + sizeComp)
}

export function attackProbability(threat) {
  return Math.floor(threat * 80 / 100)
}

// ---------------------------------------------------------------------------
// Building construction preview
// ---------------------------------------------------------------------------

export function previewConstruct(colony, buildingType, seedJs, lon) {
  const info = BUILDING_INFO[buildingType]
  if (!info) return { canBuild: false, reason: 'Unknown building type' }

  const terrain = terrainAt(seedJs, lon)
  const bonus   = terrainBonus(buildingType, terrain)
  const output  = buildingOutputPerEpoch(buildingType, bonus)

  const insufficient = []
  if (colony.minerals < info.mineralCost)
    insufficient.push(`${info.mineralCost} minerals (have ${colony.minerals})`)
  if (colony.buildPoints < info.buildCost)
    insufficient.push(`${info.buildCost} build pts (have ${colony.buildPoints})`)

  return {
    canBuild: insufficient.length === 0,
    reason: insufficient.length ? `Need: ${insufficient.join(', ')}` : null,
    mineralCost: info.mineralCost,
    buildCost: info.buildCost,
    terrain, terrainName: terrainName(terrain), bonus, output,
  }
}

export function applyConstruct(colony, buildingType, terrainBonusVal, outputPerEpoch) {
  const info = BUILDING_INFO[buildingType]
  const next = {
    ...colony,
    minerals:    colony.minerals    - info.mineralCost,
    buildPoints: colony.buildPoints - info.buildCost,
  }
  if (buildingType === BUILDING_TYPES.FARM)     { next.farms++;     next.farmOutput     += outputPerEpoch }
  if (buildingType === BUILDING_TYPES.MINE)     { next.mines++;     next.mineOutput     += outputPerEpoch }
  if (buildingType === BUILDING_TYPES.BARRACKS) { next.barracks++;  next.barracksOutput += outputPerEpoch }
  if (buildingType === BUILDING_TYPES.WORKSHOP) { next.workshops++; next.workshopOutput += outputPerEpoch }
  return next
}

// ---------------------------------------------------------------------------
// Turn simulation
// ---------------------------------------------------------------------------

/**
 * Process one turn of orders given elapsed time (seconds since last action).
 * Returns { planet, colony, events, production, threat, attackProb }.
 */
export function assignOrders(planet, colony, { farming, mining, building, defense }, elapsedSeconds) {
  const total = farming + mining + building + defense
  if (total > 100) throw new Error('Orders exceed 100%')

  const elapsed = elapsedSeconds ?? EPOCH_SECONDS
  const epochsRaw = Math.floor(elapsed / EPOCH_SECONDS)
  const epochs = Math.max(1, Math.min(MAX_EPOCHS, epochsRaw))

  const events = []
  let pop = planet.population

  // Per-epoch rates
  const foodRate     = Math.floor((pop * farming * (100 + colony.fertility)) / 10000) + (colony.farmOutput ?? 0)
  const foodConsumed = pop
  const mineralRate  = Math.floor((pop * mining * (100 + colony.mineralRichness)) / 10000) + (colony.mineOutput ?? 0)
  const buildRate    = Math.floor((pop * building) / 100) + (colony.workshopOutput ?? 0)
  const defRate      = Math.floor((pop * defense) / 100) + (colony.barracksOutput ?? 0)

  // Scale by epochs
  const foodProd    = foodRate * epochs
  const foodUsed    = foodConsumed * epochs
  const mineralProd = mineralRate * epochs
  const buildProg   = buildRate * epochs
  const defGain     = defRate * epochs

  // Apply resources
  const rawFood = colony.food + foodProd
  let food = rawFood >= foodUsed ? rawFood - foodUsed : 0
  const minerals   = colony.minerals + mineralProd
  const buildPoints = (colony.buildPoints ?? 0) + buildProg
  let colonyDefense = colony.defense + defGain

  // Population
  if (food === 0) {
    const deathsPerEpoch = Math.max(1, Math.floor(pop / 10))
    const totalDeaths    = Math.floor(deathsPerEpoch * epochs / 2)
    pop = Math.max(0, pop - totalDeaths)
    events.push(`Starvation — ${totalDeaths} colonists lost over ${epochs} epoch${epochs > 1 ? 's' : ''}.`)
  } else if (food > pop * 10 * epochs) {
    const growth = Math.min(10, Math.max(1, Math.floor(pop / 20)))
    pop += growth
    events.push(`Population grew by ${growth}.`)
  }

  // Threat & attack
  const nowSeconds = (planet.lastActionAt ?? 0) + elapsed
  const threat = computeThreat({ ...planet, population: pop }, { ...colony, food, minerals }, nowSeconds)
  const attackProb = attackProbability(threat)
  const rng = clientHash(planet.seed, planet.actionCount) % 100

  if (rng < attackProb) {
    const attack = Math.min(250, threat * 3 + epochs)
    if (attack > colonyDefense) {
      const excess = attack - colonyDefense
      const casualties = Math.min(Math.floor(pop / 3), Math.floor(excess / 2))
      pop = Math.max(0, pop - casualties)
      colonyDefense = Math.max(0, colonyDefense - Math.floor(attack / 2))
      events.push(`Enemy raid! Threat ${threat}% — ${casualties} colonists lost, defense degraded.`)
    } else {
      events.push(`Enemy raid repelled. Threat level: ${threat}%.`)
    }
  }

  return {
    planet:  { ...planet,  population: pop, actionCount: planet.actionCount + 1, lastActionAt: nowSeconds },
    colony:  { ...colony,  food, minerals, buildPoints, defense: colonyDefense },
    events,
    production: { foodProd, foodUsed, mineralProd, buildProg, defGain, foodRate, mineralRate },
    threat,
    attackProb,
    epochs,
  }
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
