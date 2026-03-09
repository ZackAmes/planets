import { createNoise3D } from 'simplex-noise'
import { terrainAt } from './gameLogic.js'

// Seeded PRNG (mulberry32) — used only for within-cell detail variation
function mulberry32(seed) {
  return function () {
    let t = (seed += 0x6d2b79f5)
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

// Base RGB colors per terrain type — matches terrain.cairo type IDs
const TERRAIN_RGB = {
  1: [26,  107, 138],  // ocean
  2: [61,  122,  42],  // plains
  3: [22,   61,  18],  // forest
  4: [196, 125,  21],  // desert
  6: [74,   58,  44],  // mountain
  7: [232, 242, 245],  // snow
  8: [196, 168,  92],  // beach
}
const FALLBACK_RGB = [100, 100, 100]

// Unified client terrain grid constants (50x40)
const TERRAIN_COLS = 50
const TERRAIN_ROWS = 40
const LON_PER_COL  = 72    // 3600 / 50
const LAT_PER_ROW  = 45    // 1800 / 40

/**
 * Generates an equirectangular canvas texture for the planet sphere.
 *
 * seedFull: BigInt felt252 VRF seed — used to compute deterministic terrain
 *   on the same client grid used for selection/build preview.
 *
 * seed: JS number — used only for simplex detail noise (subtle shading within
 *   each terrain cell so the texture doesn't look like a flat pixel grid).
 *
 * If seedFull is null the function falls back to a generic seed for dev use.
 */
export function generatePlanetTexture(seed, seedFull = null, texWidth = 1024, texHeight = 512) {
  const effectiveSeedFull = seedFull ?? BigInt(seed)

  // --- Precompute the unified 50x40 terrain grid ---
  const grid = new Uint8Array(TERRAIN_COLS * TERRAIN_ROWS)
  for (let row = 0; row < TERRAIN_ROWS; row++) {
    for (let col = 0; col < TERRAIN_COLS; col++) {
      // Sample at the center of each grid cell
      const lon = col * LON_PER_COL + Math.floor(LON_PER_COL / 2)
      const lat = row * LAT_PER_ROW + Math.floor(LAT_PER_ROW / 2)
      grid[row * TERRAIN_COLS + col] = terrainAt(effectiveSeedFull, lon, lat)
    }
  }

  // --- Simplex detail noise for within-cell shading ---
  const rand = mulberry32(seed)
  const detailNoise = createNoise3D(rand)

  const canvas = document.createElement('canvas')
  canvas.width  = texWidth
  canvas.height = texHeight
  const ctx = canvas.getContext('2d')
  const imageData = ctx.createImageData(texWidth, texHeight)

  const TWO_PI = Math.PI * 2

  for (let y = 0; y < texHeight; y++) {
    for (let x = 0; x < texWidth; x++) {
      // Pixel → lon/lat (integer), matching uvToLonLat + lonLatToLocal orientation.
      const lon = Math.min(3599, Math.max(0, Math.floor((1 - x / texWidth) * 3600)))
      const lat = Math.min(1799, Math.max(0, Math.floor((y / texHeight) * 1800)))

      // Grid cell lookup (O(1))
      const col         = Math.min(TERRAIN_COLS - 1, Math.floor(lon / LON_PER_COL))
      const row         = Math.min(TERRAIN_ROWS - 1, Math.floor(lat / LAT_PER_ROW))
      const terrainType = grid[row * TERRAIN_COLS + col]
      const base        = TERRAIN_RGB[terrainType] ?? FALLBACK_RGB

      // Seamless horizontal detail noise (±20 lightness variation)
      const nx    = x / texWidth
      const nz    = y / texHeight
      const angle = nx * TWO_PI
      const d     = detailNoise(Math.cos(angle) * 5, Math.sin(angle) * 5, nz * 5)
      const v     = Math.round(d * 20)

      const idx = (y * texWidth + x) * 4
      imageData.data[idx]     = Math.max(0, Math.min(255, base[0] + v))
      imageData.data[idx + 1] = Math.max(0, Math.min(255, base[1] + v))
      imageData.data[idx + 2] = Math.max(0, Math.min(255, base[2] + v))
      imageData.data[idx + 3] = 255
    }
  }

  ctx.putImageData(imageData, 0, 0)
  return canvas
}
