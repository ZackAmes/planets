// SPDX-License-Identifier: MIT

/// Building types. Discriminant maps directly to the u8 stored in Building.building_type.
#[derive(Introspect, Drop, Serde, Copy, PartialEq)]
pub enum BuildingType {
    Farm,     // 0
    Mine,     // 1
    Barracks, // 2
    Workshop, // 3
}

/// A building placed at a specific lat/lon on a planet.
///
/// Coordinates are in tenths of a degree:
///   lon 0–3599  (0.1° steps, full circle)
///   lat 0–1799  (0.1° steps, 0 = north pole, 900 = equator)
///
/// SVG canvas mapping (600×600 px):  x = lon / 6,  y = lat / 3
///
/// terrain_bonus    : 0-100 — suitability of the terrain for this building type.
/// output_per_epoch : pre-computed resource output per 600-second epoch.
///                    Formula: base × (50 + terrain_bonus) / 100
///
/// building_type: 0=Farm, 1=Mine, 2=Barracks, 3=Workshop
#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct Building {
    #[key]
    pub planet_id: u64,
    #[key]
    pub lon: u16,
    #[key]
    pub lat: u16,
    pub building_type: u8,
    pub exists: bool,
    pub terrain_bonus: u8,
    pub output_per_epoch: u32,
}

/// Total building count on a planet (for enumeration).
#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct PlanetBuildingCount {
    #[key]
    pub planet_id: u64,
    pub count: u32,
}

/// Maps sequential index → building location for a planet.
#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct PlanetBuildingEntry {
    #[key]
    pub planet_id: u64,
    #[key]
    pub index: u32,
    pub lon: u16,
    pub lat: u16,
}
