// SPDX-License-Identifier: MIT

/// Building types.
/// Discriminant maps 1:1 to the u8 stored in Building.building_type.
///   0 = TownCenter  (auto-placed at colony founding, sets building limit)
///   1 = WaterWell   (water / worker / epoch — terrain: shallow > beach > scrubland)
///   2 = IronMine    (iron  / worker / epoch — terrain: mountain > highland)
///   3 = House       (no workers, adds 20 to max_population)
///   4 = Barracks    (defense / worker / epoch — terrain: mountain > highland)
#[derive(Introspect, Drop, Serde, Copy, PartialEq)]
pub enum BuildingType {
    TownCenter,
    WaterWell,
    IronMine,
    House,
    Barracks,
}

/// A building placed at a specific lon/lat on a planet.
///
/// Coordinates (tenths of a degree):
///   lon 0-3599   lat 0-1799
///
/// SVG canvas mapping (600x600 px):  x = lon/6,  y = lat/3
///
/// workers              : colonists currently assigned to this building.
/// max_workers          : capacity for this type (0 for TC and House).
/// output_per_worker_epoch: terrain-adjusted output per assigned worker per epoch.
///   Formula: base * (50 + terrain_bonus) / 100
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
    pub workers: u8,
    pub max_workers: u8,
    pub output_per_worker_epoch: u32,
}

/// Total building count for a planet (used for enumeration).
#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct PlanetBuildingCount {
    #[key]
    pub planet_id: u64,
    pub count: u32,
}

/// Maps sequential index to building location for a planet.
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
