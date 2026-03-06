// SPDX-License-Identifier: MIT

use death_mountain::systems::adventurer::contracts::{IAdventurerSystemsDispatcher};
use death_mountain::systems::renderer::contracts::{IRendererSystemsDispatcher};
use dojo::world::{WorldStorage, WorldStorageTrait};

#[derive(Copy, Drop)]
pub struct GameLibs {
    pub renderer: IRendererSystemsDispatcher,
    pub adventurer: IAdventurerSystemsDispatcher,
}

#[generate_trait]
pub impl ImplGameLibs of IGameLib {
    fn new(world: WorldStorage) -> GameLibs {
        let (renderer_systems_address, _) = world.dns(@"renderer_systems").unwrap();
        let (adventurer_systems_address, _) = world.dns(@"adventurer_systems").unwrap();

        GameLibs {
            renderer: IRendererSystemsDispatcher { contract_address: renderer_systems_address },
            adventurer: IAdventurerSystemsDispatcher { contract_address: adventurer_systems_address },
        }
    }
}
