import { createNoise2D } from 'simplex-noise'

// Seeded PRNG (mulberry32) so the same seed always produces the same planet
function mulberry32(seed) {
  return function () {
    let t = (seed += 0x6d2b79f5)
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

const TERRAIN = {
  ocean:     { color: '#1a5f7a', height: 0.05 },
  shallow:   { color: '#2a85a0', height: 0.15 },
  beach:     { color: '#c8b87a', height: 0.25 },
  grassland: { color: '#4a7c39', height: 0.45 },
  farmland:  { color: '#6aaa40', height: 0.45 },
  forest:    { color: '#1e4d1a', height: 0.65 },
  highland:  { color: '#7a6a5a', height: 0.90 },
  mountain:  { color: '#5a4a3a', height: 1.20 },
  snow:      { color: '#dde8ec', height: 1.40 },
  desert:    { color: '#c8972a', height: 0.35 },
  scrubland: { color: '#8a7a50', height: 0.40 },
}

function classifyTerrain(elevation, moisture) {
  if (elevation < 0.25) return 'ocean'
  if (elevation < 0.32) return 'shallow'
  if (elevation < 0.38) return 'beach'
  if (elevation < 0.75) {
    if (moisture < 0.25) return 'desert'
    if (moisture < 0.40) return 'scrubland'
    if (moisture < 0.55) return elevation > 0.60 ? 'highland' : 'grassland'
    if (moisture < 0.75) return elevation > 0.58 ? 'forest' : 'farmland'
    return 'forest'
  }
  if (elevation < 0.87) return 'mountain'
  return 'snow'
}

const HEX_SIZE = 1.0
const SQRT3 = Math.sqrt(3)

// Pointy-top hex grid layout
function hexPosition(col, row, width, height) {
  const x = SQRT3 * HEX_SIZE * (col + 0.5 * (row & 1)) - (SQRT3 * HEX_SIZE * width) / 2
  const z = 1.5 * HEX_SIZE * row - (1.5 * HEX_SIZE * height) / 2
  return { x, z }
}

/**
 * Generates an equirectangular canvas texture for a sphere.
 * Same noise as generatePlanet but mapped to UV space.
 */
export function generatePlanetTexture(seed, texWidth = 1024, texHeight = 512) {
  const rand = mulberry32(seed)
  const elevationNoise = createNoise2D(rand)
  const moistureNoise = createNoise2D(rand)

  const canvas = document.createElement('canvas')
  canvas.width = texWidth
  canvas.height = texHeight
  const ctx = canvas.getContext('2d')
  const imageData = ctx.createImageData(texWidth, texHeight)

  for (let y = 0; y < texHeight; y++) {
    for (let x = 0; x < texWidth; x++) {
      const nx = x / texWidth
      const nz = y / texHeight

      const e =
        0.60 * ((elevationNoise(nx * 2, nz * 2) + 1) / 2) +
        0.25 * ((elevationNoise(nx * 4, nz * 4) + 1) / 2) +
        0.10 * ((elevationNoise(nx * 8, nz * 8) + 1) / 2) +
        0.05 * ((elevationNoise(nx * 16, nz * 16) + 1) / 2)

      const m =
        0.70 * ((moistureNoise(nx * 3 + 100, nz * 3 + 100) + 1) / 2) +
        0.20 * ((moistureNoise(nx * 6 + 100, nz * 6 + 100) + 1) / 2) +
        0.10 * ((moistureNoise(nx * 12 + 100, nz * 12 + 100) + 1) / 2)

      const terrain = classifyTerrain(e, m)
      const hex = TERRAIN[terrain].color
      const r = parseInt(hex.slice(1, 3), 16)
      const g = parseInt(hex.slice(3, 5), 16)
      const b = parseInt(hex.slice(5, 7), 16)

      const idx = (y * texWidth + x) * 4
      imageData.data[idx]     = r
      imageData.data[idx + 1] = g
      imageData.data[idx + 2] = b
      imageData.data[idx + 3] = 255
    }
  }

  ctx.putImageData(imageData, 0, 0)
  return canvas
}

export function generatePlanet(seed, width = 50, height = 40) {
  const rand = mulberry32(seed)
  const elevationNoise = createNoise2D(rand)
  const moistureNoise = createNoise2D(rand)

  const tiles = []

  for (let row = 0; row < height; row++) {
    for (let col = 0; col < width; col++) {
      // Multi-octave noise for more natural terrain
      const nx = col / width
      const nz = row / height

      const e =
        0.60 * ((elevationNoise(nx * 2, nz * 2) + 1) / 2) +
        0.25 * ((elevationNoise(nx * 4, nz * 4) + 1) / 2) +
        0.10 * ((elevationNoise(nx * 8, nz * 8) + 1) / 2) +
        0.05 * ((elevationNoise(nx * 16, nz * 16) + 1) / 2)

      const m =
        0.70 * ((moistureNoise(nx * 3 + 100, nz * 3 + 100) + 1) / 2) +
        0.20 * ((moistureNoise(nx * 6 + 100, nz * 6 + 100) + 1) / 2) +
        0.10 * ((moistureNoise(nx * 12 + 100, nz * 12 + 100) + 1) / 2)

      const terrain = classifyTerrain(e, m)
      const { x, z } = hexPosition(col, row, width, height)
      const terrainData = TERRAIN[terrain]

      tiles.push({
        col,
        row,
        x,
        z,
        terrain,
        color: terrainData.color,
        height: terrainData.height,
        elevation: e,
      })
    }
  }

  return { tiles, width, height, seed }
}
