// SPDX-License-Identifier: MIT

/// Building types.
/// Discriminant maps 1:1 to the u8 stored in Building.building_type.
///   0 = TownCenter   (auto-placed, no workers — controls building limit and max building level)
///   1 = WaterWell    (water / worker / epoch)
///   2 = IronMine     (iron  / worker / epoch)
///   3 = House        (no workers, spawns 1 colonist on build — costs iron + water)
///   4 = Barracks     (defense / worker / epoch)
///   5 = UraniumMine  (uranium / worker / epoch — unlocked at TC level 3)
///   6 = Spaceport    (no workers, win condition — requires TC level 5)
#[derive(Introspect, Drop, Serde, Copy, PartialEq)]
pub enum BuildingType {
    TownCenter,
    WaterWell,
    IronMine,
    House,
    Barracks,
    UraniumMine,
    Spaceport,
}

/// A building placed at a specific lon/lat on a planet.
///
/// level: current upgrade level (1–5, capped by tc_level).
/// output_per_worker_epoch is recomputed on each upgrade:
///   base * (50 + terrain_bonus) / 100 * level_factor / 100
#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct Building {
    #[key]
    pub planet_id: felt252,
    #[key]
    pub lon: u16,
    #[key]
    pub lat: u16,
    pub building_type: u8,
    pub exists: bool,
    pub terrain_bonus: u8,
    pub level: u8,
    pub workers: u8,
    pub max_workers: u8,
    pub output_per_worker_epoch: u32,
}

/// Total building count for a planet (used for enumeration).
#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct PlanetBuildingCount {
    #[key]
    pub planet_id: felt252,
    pub count: u32,
}

/// Maps sequential index to building location for a planet.
#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct PlanetBuildingEntry {
    #[key]
    pub planet_id: felt252,
    #[key]
    pub index: u32,
    pub lon: u16,
    pub lat: u16,
}
