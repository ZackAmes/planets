// SPDX-License-Identifier: UNLICENSED

pub mod systems {
    pub mod planet {
        pub mod contracts;
    }
    pub mod game {
        pub mod contracts;
    }
    pub mod renderer {
        pub mod contracts;
    }
    pub mod game_token {
        pub mod contracts;
    }
}

pub mod models {
    pub mod planet;
    pub mod colony;
    pub mod resources;
    pub mod colonists;
    pub mod player_planets;
    pub mod building;
    pub mod invader;
    pub mod gear;
}

pub use models::colonists::{
    Colonist, PlanetColonistCount,
    ColonistsAssigned, ColonistAssignedEntry, ColonistAssignedIdx,
    ColonistsUnassigned, ColonistUnassignedEntry, ColonistUnassignedIdx,
};

pub mod utils {
    pub mod renderer {
        pub mod encoding;
        pub mod renderer_utils;
    }
    #[cfg(test)]
    pub mod setup_denshokan;
    pub mod vrf;
}

pub mod constants {
    pub mod world;
}

pub mod libs {
    pub mod terrain;
}
