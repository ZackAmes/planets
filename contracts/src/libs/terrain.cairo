// SPDX-License-Identifier: MIT

// ---------------------------------------------------------------------------
// Seamless 2D hash-based terrain generation
//
// Grid: GRID_COLS x GRID_ROWS cells mapped over lon/lat.
// Horizontal wrapping: hash keys use col % GRID_COLS so the left and right
// edges of the planet always produce identical terrain (no seam).
//
// Two-octave value noise: a coarse pass gives continental shapes; a fine pass
// adds local detail.  Both octaves are seamlessly periodic.
//
// Terrain types (match client gameLogic.js):
//   0 = deep ocean   1 = shallow ocean   2 = grassland   3 = forest
//   4 = desert       5 = highland        6 = mountain    7 = snow
//   8 = beach        9 = scrubland
// ---------------------------------------------------------------------------

use core::poseidon::poseidon_hash_span;

pub const GRID_COLS: u32 = 20;
pub const GRID_ROWS: u32 = 10;
// lon 0-3599 / 20 cols = 180 units per col
pub const LON_PER_COL: u32 = 180;
// lat 0-1799 / 10 rows = 180 units per row
pub const LAT_PER_ROW: u32 = 180;

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Deterministic noise value 0-255 at grid cell (col % period, row).
fn _cell_noise(seed: felt252, col: u32, row: u32, period: u32) -> u32 {
    let wrapped: felt252 = (col % period).into();
    let h: felt252 = poseidon_hash_span(array![seed, wrapped, row.into()].span());
    let h256: u256 = h.into();
    (h256 % 256).try_into().unwrap_or(128)
}

// ---------------------------------------------------------------------------
// Public noise API
// ---------------------------------------------------------------------------

/// Two-octave elevation noise 0-255.
/// Coarse octave (period 5) gives continental shapes;
/// fine octave (period 20) adds local variation.
pub fn terrain_elevation(seed: felt252, col: u32, row: u32) -> u32 {
    let e_coarse = _cell_noise(seed, col * 5 / GRID_COLS, row / 2, 5);
    let e_fine = _cell_noise(seed + 1, col, row, GRID_COLS);
    (e_coarse * 6 + e_fine * 4) / 10
}

/// Two-octave moisture noise 0-255.
pub fn terrain_moisture(seed: felt252, col: u32, row: u32) -> u32 {
    let m_coarse = _cell_noise(seed + 7, col * 5 / GRID_COLS, row / 2, 5);
    let m_fine = _cell_noise(seed + 13, col, row, GRID_COLS);
    (m_coarse * 7 + m_fine * 3) / 10
}

/// Map (elevation 0-255, moisture 0-255, latitude row 0-9) to terrain type 0-9.
/// Polar rows (0,1,8,9) receive an elevation boost to produce snow/ice near
/// the poles without needing temperature simulation.
pub fn classify_terrain(elevation: u32, moisture: u32, row: u32) -> u32 {
    let polar_boost: u32 = if row == 0 || row == 9 {
        100_u32
    } else if row == 1 || row == 8 {
        50_u32
    } else if row == 2 || row == 7 {
        20_u32
    } else {
        0_u32
    };
    let elev: u32 = if elevation + polar_boost > 255 {
        255_u32
    } else {
        elevation + polar_boost
    };

    // Thresholds mirror client classifyTerrain (float 0-1 scaled x256):
    //   ocean < 0.25  -> 64    shallow < 0.32 -> 82    beach < 0.38 -> 97
    //   land  < 0.75  -> 192   mountain < 0.87 -> 222   else snow
    if elev < 64 {
        return 0_u32; // deep ocean
    }
    if elev < 82 {
        return 1_u32; // shallow ocean
    }
    if elev < 97 {
        return 8_u32; // beach
    }
    if elev < 192 {
        // land zone
        if moisture < 64 {
            return 4_u32; // desert
        }
        if moisture < 102 {
            return 9_u32; // scrubland
        }
        if moisture < 140 {
            if elev > 153 {
                return 5_u32; // highland
            }
            return 2_u32; // grassland
        }
        return 3_u32; // forest
    }
    if elev < 222 {
        return 6_u32; // mountain
    }
    7_u32 // snow
}

/// Terrain type 0-9 at a lon/lat position on a planet with the given seed.
pub fn terrain_at(seed: felt252, lon: u16, lat: u16) -> u32 {
    let col: u32 = lon.into() / LON_PER_COL;
    let row: u32 = lat.into() / LAT_PER_ROW;
    let elevation = terrain_elevation(seed, col, row);
    let moisture = terrain_moisture(seed, col, row);
    classify_terrain(elevation, moisture, row)
}

/// Building suitability bonus for a terrain type (0 = poor, 100 = ideal).
/// building_type: 0=TownCenter, 1=WaterWell, 2=IronMine, 3=House, 4=Barracks
pub fn terrain_bonus(building_type: u8, terrain_type: u32) -> u8 {
    if building_type == 1 {
        // WaterWell — needs water sources nearby
        if terrain_type == 1 {
            return 100_u8; // shallow ocean (coastal)
        }
        if terrain_type == 8 {
            return 80_u8; // beach
        }
        if terrain_type == 9 {
            return 60_u8; // scrubland (moisture)
        }
        if terrain_type == 2 {
            return 40_u8; // grassland
        }
        if terrain_type == 3 {
            return 30_u8; // forest
        }
        return 10_u8;
    }
    if building_type == 2 {
        // IronMine — best in rocky terrain
        if terrain_type == 6 {
            return 100_u8; // mountain
        }
        if terrain_type == 5 {
            return 70_u8; // highland
        }
        if terrain_type == 4 {
            return 40_u8; // desert
        }
        if terrain_type == 3 {
            return 20_u8; // forest
        }
        return 5_u8;
    }
    if building_type == 4 {
        // Barracks — defensible high ground
        if terrain_type == 6 {
            return 60_u8; // mountain
        }
        if terrain_type == 5 {
            return 50_u8; // highland
        }
        if terrain_type == 7 {
            return 40_u8; // snow
        }
        if terrain_type == 3 {
            return 30_u8; // forest cover
        }
        return 20_u8;
    }
    // TownCenter (0) and House (3) — no terrain output
    0_u8
}
