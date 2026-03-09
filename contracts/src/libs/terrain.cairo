// SPDX-License-Identifier: MIT

// ---------------------------------------------------------------------------
// Seamless 2D hash-based terrain generation
//
// Grid: GRID_COLS x GRID_ROWS cells mapped over lon/lat.
// Horizontal wrapping: hash keys use col % period so left and right edges
// always match (no seam).
//
// Three-octave approach inspired by simplex noise:
//   continental (coarse 2D) + regional (medium 2D) + local (fine 2D)
//   All three octaves are 2D, giving organic continent shapes rather than
//   rigid latitude bands.  Polar boost + temperature factor still produce
//   natural ice caps and biome banding.
//
// Terrain types:
//   1 = ocean    2 = plains    3 = forest    4 = desert
//   6 = mountain    7 = snow    8 = beach
// ---------------------------------------------------------------------------

use core::poseidon::poseidon_hash_span;

pub const GRID_COLS: u32 = 50;
pub const GRID_ROWS: u32 = 40;
// lon 0-3599 / 50 cols = 72 units per col
pub const LON_PER_COL: u32 = 72;
// lat 0-1799 / 40 rows = 45 units per row
pub const LAT_PER_ROW: u32 = 45;

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

/// Three-octave elevation noise 0-255.
///
/// All octaves are 2D, producing organic continent shapes:
///   continental  — sampled at 1/4 resolution (period 10), creates large landmasses
///   regional     — medium frequency (period 8), carves coastlines and highlands
///   local        — full grid resolution, adds local variation
///
/// 5:3:2 weighting keeps large-scale structure dominant while allowing
/// significant longitudinal variation within any latitude band.
pub fn terrain_elevation(seed: felt252, col: u32, row: u32) -> u32 {
    let e_continental = _cell_noise(seed,     col / 4, row / 4, 10); // coarse 2D
    let e_regional    = _cell_noise(seed + 3, col,     row,     8);  // medium 2D
    let e_local       = _cell_noise(seed + 1, col,     row,     GRID_COLS); // fine 2D
    (e_continental * 5 + e_regional * 3 + e_local * 2) / 10
}

/// Three-octave moisture noise 0-255.
pub fn terrain_moisture(seed: felt252, col: u32, row: u32) -> u32 {
    let m_coarse = _cell_noise(seed + 7,  col, row / 2, 10);
    let m_mid    = _cell_noise(seed + 11, col, row,     5);
    let m_fine   = _cell_noise(seed + 13, col, row,     GRID_COLS);
    (m_coarse * 5 + m_mid * 3 + m_fine * 2) / 10
}

/// Map (elevation 0-255, moisture 0-255, latitude row 0-39) to terrain type.
///
/// Biomes:  1=ocean  2=plains  3=forest  4=desert  6=mountain  7=snow  8=beach
///
/// Polar boost pushes high-latitude cells into mountain/snow.
/// Temperature factor reduces effective moisture near poles, producing
/// tundra and desert bands naturally.
pub fn classify_terrain(elevation: u32, moisture: u32, row: u32) -> u32 {
    // Polar elevation boost — graduated over the 40 rows
    let polar_boost: u32 = if row == 0 || row == 39 {
        120_u32
    } else if row == 1 || row == 38 {
        70_u32
    } else if row == 2 || row == 37 {
        35_u32
    } else if row == 3 || row == 36 {
        15_u32
    } else {
        0_u32
    };
    let elev: u32 = if elevation + polar_boost > 255 { 255_u32 } else { elevation + polar_boost };

    // Temperature factor: cold poles reduce effective moisture
    let temp_factor: u32 = if row == 0 || row == 39 {
        15_u32
    } else if row == 1 || row == 38 {
        30_u32
    } else if row == 2 || row == 37 {
        55_u32
    } else if row == 3 || row == 36 {
        75_u32
    } else if row == 4 || row == 35 {
        90_u32
    } else {
        100_u32
    };
    let adj_moisture: u32 = moisture * temp_factor / 100;

    if elev < 72 {
        return 1_u32; // ocean
    }
    if elev < 87 {
        return 8_u32; // beach / coast
    }
    if elev < 210 {
        if adj_moisture < 70 {
            return 4_u32; // desert
        }
        if adj_moisture < 160 {
            return 2_u32; // plains
        }
        return 3_u32; // forest
    }
    if elev < 240 {
        return 6_u32; // mountain
    }
    7_u32 // snow / ice
}

/// Returns true if a building can be placed on this terrain type.
/// Ocean (1) is the only unbuildable type.
pub fn is_buildable(terrain_type: u32) -> bool {
    terrain_type != 1
}

/// Terrain type at a lon/lat position on a planet with the given seed.
pub fn terrain_at(seed: felt252, lon: u16, lat: u16) -> u32 {
    let col: u32 = lon.into() / LON_PER_COL;
    let row: u32 = lat.into() / LAT_PER_ROW;
    let elevation = terrain_elevation(seed, col, row);
    let moisture = terrain_moisture(seed, col, row);
    classify_terrain(elevation, moisture, row)
}

/// Building suitability bonus for a terrain type (0-100).
pub fn terrain_bonus(building_type: u8, terrain_type: u32) -> u8 {
    if building_type == 1 {
        // WaterWell
        if terrain_type == 8 { return 100_u8; } // beach
        if terrain_type == 2 { return 60_u8; }  // plains
        if terrain_type == 3 { return 30_u8; }  // forest
        return 10_u8;
    }
    if building_type == 2 {
        // IronMine
        if terrain_type == 6 { return 100_u8; } // mountain
        if terrain_type == 4 { return 40_u8; }  // desert
        if terrain_type == 3 { return 20_u8; }  // forest
        return 5_u8;
    }
    if building_type == 4 {
        // Barracks
        if terrain_type == 6 { return 70_u8; }  // mountain
        if terrain_type == 7 { return 40_u8; }  // snow
        if terrain_type == 3 { return 30_u8; }  // forest
        return 20_u8;
    }
    if building_type == 5 {
        // UraniumMine
        if terrain_type == 6 { return 100_u8; } // mountain
        if terrain_type == 4 { return 40_u8; }  // desert
        return 5_u8;
    }
    if building_type == 8 {
        // Cannon
        if terrain_type == 6 { return 70_u8; }  // mountain
        if terrain_type == 7 { return 40_u8; }  // snow
        if terrain_type == 2 { return 20_u8; }  // plains
        return 10_u8;
    }
    0_u8
}
