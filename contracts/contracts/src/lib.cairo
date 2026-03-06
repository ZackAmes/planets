// SPDX-License-Identifier: UNLICENSED

pub mod systems {
    pub mod game {
        pub mod contracts;
    }
    pub mod renderer {
        pub mod contracts;
    }
    pub mod adventurer {
        pub mod contracts;
    }
    pub mod game_token {
        pub mod contracts;
    }
    pub mod settings {
        pub mod contracts;
    }
    pub mod objectives {
        pub mod contracts;
    }
}

pub mod models {
    pub mod adventurer {
        pub mod adventurer;
    }
    pub mod game;
    pub mod objectives;
}

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
    pub mod game;
    pub mod settings;
}
