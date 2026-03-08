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

/// Row-only (1D) noise value 0-255 — same for all columns in the same row.
/// Used for the coarse elevation octave to create horizontal latitude bands.
fn _row_noise(seed: felt252, row: u32) -> u32 {
    let h: felt252 = poseidon_hash_span(array![seed, row.into()].span());
    let h256: u256 = h.into();
    (h256 % 256).try_into().unwrap_or(128)
}

// ---------------------------------------------------------------------------
// Public noise API
// ---------------------------------------------------------------------------

/// Three-octave elevation noise 0-255.
/// Coarse octave is row-only (same value for all columns in a row-pair),
/// creating horizontal latitude bands. Mid and fine octaves add 2D variation
/// that breaks the bands into continents and local detail.
pub fn terrain_elevation(seed: felt252, col: u32, row: u32) -> u32 {
    let e_lat  = _row_noise(seed, row / 2);           // row-only: horizontal bands
    let e_mid  = _cell_noise(seed + 3, col, row, 5);  // 2D regional (4 col groups)
    let e_fine = _cell_noise(seed + 1, col, row, GRID_COLS); // 2D local detail
    (e_lat * 5 + e_mid * 3 + e_fine * 2) / 10
}

/// Three-octave moisture noise 0-255 (primarily 2D for longitudinal wet/dry variation).
pub fn terrain_moisture(seed: felt252, col: u32, row: u32) -> u32 {
    let m_coarse = _cell_noise(seed + 7,  col, row / 2, 10); // semi-coarse 2D
    let m_mid    = _cell_noise(seed + 11, col, row,     5);   // medium 2D
    let m_fine   = _cell_noise(seed + 13, col, row,     GRID_COLS); // fine detail
    (m_coarse * 5 + m_mid * 3 + m_fine * 2) / 10
}

/// Map (elevation 0-255, moisture 0-255, latitude row 0-9) to terrain type.
///
/// Simplified 7-biome set (types 0, 5, 9 are never produced):
///   1 = ocean    2 = plains    3 = forest    4 = desert
///   6 = mountain    7 = snow    8 = beach
///
/// Polar rows get an elevation boost for snow/ice. A latitude temperature
/// factor reduces effective moisture at high latitudes, creating natural
/// biome banding (tropical forest → plains → desert → tundra → ice).
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

    let temp_factor: u32 = if row == 0 || row == 9 {
        20_u32
    } else if row == 1 || row == 8 {
        40_u32
    } else if row == 2 || row == 7 {
        65_u32
    } else if row == 3 || row == 6 {
        85_u32
    } else {
        100_u32
    };
    let adj_moisture: u32 = moisture * temp_factor / 100;

    if elev < 85 {
        return 1_u32; // ocean (merged deep + shallow)
    }
    if elev < 100 {
        return 8_u32; // beach / coast
    }
    if elev < 200 {
        // land zone
        if adj_moisture < 70 {
            return 4_u32; // desert
        }
        if adj_moisture < 160 {
            return 2_u32; // plains (merged grassland + scrubland)
        }
        return 3_u32; // forest
    }
    if elev < 235 {
        return 6_u32; // mountain (merged highland + mountain)
    }
    7_u32 // snow / ice
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
/// Matches the simplified 7-biome set: ocean(1) beach(8) plains(2) forest(3)
/// desert(4) mountain(6) snow(7). Highland merged into mountain; scrubland/grassland
/// merged into plains.
pub fn terrain_bonus(building_type: u8, terrain_type: u32) -> u8 {
    if building_type == 1 {
        // WaterWell
        if terrain_type == 1 { return 100_u8; } // ocean / coastal
        if terrain_type == 8 { return 80_u8; }  // beach
        if terrain_type == 2 { return 50_u8; }  // plains
        if terrain_type == 3 { return 30_u8; }  // forest
        return 10_u8;
    }
    if building_type == 2 {
        // IronMine — rocky terrain (highland now part of mountain)
        if terrain_type == 6 { return 100_u8; } // mountain
        if terrain_type == 4 { return 40_u8; }  // desert
        if terrain_type == 3 { return 20_u8; }  // forest
        return 5_u8;
    }
    if building_type == 4 {
        // Barracks — defensible high ground (highland merged in → higher mountain bonus)
        if terrain_type == 6 { return 70_u8; }  // mountain
        if terrain_type == 7 { return 40_u8; }  // snow
        if terrain_type == 3 { return 30_u8; }  // forest cover
        return 20_u8;
    }
    if building_type == 5 {
        // UraniumMine — deep-rock deposits
        if terrain_type == 6 { return 100_u8; } // mountain
        if terrain_type == 4 { return 40_u8; }  // desert
        return 5_u8;
    }
    // TownCenter (0), House (3), Spaceport (6) — no terrain bonus
    0_u8
}
