// SPDX-License-Identifier: MIT

/// Individual colonist.
/// building_lon/lat are 0,0 when unassigned (no real building sits at 0,0
/// because the TC is placed at the hex center, not the origin).
#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct Colonist {
    #[key]
    pub planet_id: u64,
    #[key]
    pub colonist_id: u32,
    pub is_assigned: bool,
    pub building_lon: u16,
    pub building_lat: u16,
}

/// Total colonists ever spawned for a planet.
/// next_id = count (IDs are 0..count-1).
#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct PlanetColonistCount {
    #[key]
    pub planet_id: u64,
    pub count: u32,
}

// ---------------------------------------------------------------------------
// Assigned colonist enumeration (count + forward entries + reverse index)
// Supports O(1) add, O(1) remove via swap-and-pop.
// ---------------------------------------------------------------------------

#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct ColonistsAssigned {
    #[key]
    pub planet_id: u64,
    pub count: u32,
}

#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct ColonistAssignedEntry {
    #[key]
    pub planet_id: u64,
    #[key]
    pub index: u32,
    pub colonist_id: u32,
}

/// Reverse index: colonist_id → position in the assigned list.
#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct ColonistAssignedIdx {
    #[key]
    pub planet_id: u64,
    #[key]
    pub colonist_id: u32,
    pub index: u32,
}

// ---------------------------------------------------------------------------
// Unassigned colonist enumeration (same pattern)
// ---------------------------------------------------------------------------

#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct ColonistsUnassigned {
    #[key]
    pub planet_id: u64,
    pub count: u32,
}

#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct ColonistUnassignedEntry {
    #[key]
    pub planet_id: u64,
    #[key]
    pub index: u32,
    pub colonist_id: u32,
}

/// Reverse index: colonist_id → position in the unassigned list.
#[derive(Introspect, Drop, Serde)]
#[dojo::model]
pub struct ColonistUnassignedIdx {
    #[key]
    pub planet_id: u64,
    #[key]
    pub colonist_id: u32,
    pub index: u32,
}
