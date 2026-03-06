// SPDX-License-Identifier: MIT

use planets::models::planet::Planet;
use dojo::model::ModelStorage;
use dojo::world::WorldStorage;

#[derive(Copy, Drop)]
pub struct GameLibs {
    pub world: WorldStorage,
}

#[generate_trait]
pub impl ImplGameLibs of IGameLib {
    fn new(world: WorldStorage) -> GameLibs {
        GameLibs { world }
    }

    fn get_planet(self: GameLibs, planet_id: u64) -> Planet {
        self.world.read_model(planet_id)
    }
}
