/**
 * Client-side game logic mirroring the Cairo contracts.
 * Used for local state simulation; the onchain contracts are the source of truth.
 */

const PLANET_WIDTH = 50
const PLANET_HEIGHT = 40
const STARTING_FOOD = 500
const STARTING_MINERALS = 200
const STARTING_DEFENSE = 20

/** Simple u32 Poseidon-like hash (not cryptographic — just for client preview). */
function clientHash(a, b) {
  // mulberry32-based mixing of two numbers
  let h = (a ^ (b * 0x9e3779b9)) >>> 0
  h = Math.imul(h ^ (h >>> 16), 0x45d9f3b) >>> 0
  h = Math.imul(h ^ (h >>> 16), 0x45d9f3b) >>> 0
  return (h ^ (h >>> 16)) >>> 0
}

/**
 * Derive terrain bonuses for a colony location.
 * Mirrors the Poseidon hash logic in game/contracts.cairo.
 * Returns { fertility: 0-100, mineralRichness: 0-100 }.
 */
export function deriveTerrainBonuses(seed, col, row) {
  const h = clientHash(clientHash(seed, col), row)
  const fertility = h % 101
  const mineralRichness = Math.floor(h / 256) % 101
  return { fertility, mineralRichness }
}

/**
 * Create initial colony state after founding.
 */
export function foundColony(planet, col, row) {
  const { fertility, mineralRichness } = deriveTerrainBonuses(planet.seed, col, row)
  return {
    col,
    row,
    founded: true,
    food: STARTING_FOOD,
    minerals: STARTING_MINERALS,
    buildings: 0,
    defense: STARTING_DEFENSE,
    fertility,
    mineralRichness,
  }
}

/**
 * Process one turn of orders.
 * Returns { planet, colony, events } where events is an array of narrative strings.
 */
export function assignOrders(planet, colony, { farming, mining, building, defense }) {
  const total = farming + mining + building + defense
  if (total > 100) throw new Error('Orders exceed 100%')

  const events = []
  let pop = planet.population

  // --- Production ---
  const foodProd = Math.floor((pop * farming * (100 + colony.fertility)) / 10000)
  const foodConsumed = pop
  const mineralProd = Math.floor((pop * mining * (100 + colony.mineralRichness)) / 10000)
  const buildProg = Math.floor((pop * building) / 100)
  const defGain = Math.floor((pop * defense) / 100)

  // --- Apply resources ---
  let food = colony.food + foodProd
  food = food >= foodConsumed ? food - foodConsumed : 0
  const minerals = colony.minerals + mineralProd
  const buildings = colony.buildings + buildProg
  let colonyDefense = colony.defense + defGain

  // --- Population dynamics ---
  if (food === 0) {
    const deaths = Math.max(1, Math.floor(pop / 10))
    pop = Math.max(0, pop - deaths)
    events.push(`Starvation killed ${deaths} colonists.`)
  } else if (food > pop * 10) {
    const growth = Math.min(10, Math.max(1, Math.floor(pop / 20)))
    pop += growth
    events.push(`Population grew by ${growth}.`)
  }

  // --- Enemy attack ---
  const rng = clientHash(planet.seed, planet.actionCount) % 100
  if (rng < 20) {
    const attack = Math.min(150, planet.actionCount * 3)
    if (attack > colonyDefense) {
      const excess = attack - colonyDefense
      const casualties = Math.min(Math.floor(pop / 3), Math.floor(excess / 2))
      pop = Math.max(0, pop - casualties)
      colonyDefense = Math.max(0, colonyDefense - Math.floor(attack / 2))
      events.push(`Enemy raid! ${casualties} colonists lost. Defense degraded.`)
    } else {
      events.push('Enemy raid repelled by your defenses.')
    }
  }

  return {
    planet: { ...planet, population: pop, actionCount: planet.actionCount + 1 },
    colony: { ...colony, food, minerals, buildings, defense: colonyDefense },
    events,
    production: { foodProd, foodConsumed, mineralProd, buildProg, defGain },
  }
}

export { PLANET_WIDTH, PLANET_HEIGHT }
