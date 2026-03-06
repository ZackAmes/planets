// SPDX-License-Identifier: MIT

use planets::models::planet::Planet;
use planets::utils::renderer::encoding::{U256BytesUsedTraitImpl, bytes_base64_encode};
use game_components_minigame::structs::GameDetail;
use graffiti::json::JsonImpl;

// ---------------------------------------------------------------------------
// Public entry points
// ---------------------------------------------------------------------------

pub fn create_metadata(planet_id: u64, planet: Planet, planet_name: felt252) -> ByteArray {
    // Read fields before planet is moved into the SVG builder
    let pop = planet.population;
    let seed_val = planet.seed;

    let svg = _build_rotating_planet_svg(planet, planet_name, planet_id);
    let base64_image = format!("data:image/svg+xml;base64,{}", bytes_base64_encode(svg));

    let _id = format!("{}", planet_id);
    let _pop = format!("{}", pop);
    let _seed = format!("{}", seed_val);
    let _name = _felt_to_ba(planet_name);

    let mut metadata = JsonImpl::new()
        .add("name", "Planet #" + _id.clone())
        .add("description", "An onchain colony builder planet.")
        .add("image", base64_image);

    let name_attr: ByteArray = JsonImpl::new()
        .add("trait", "Name")
        .add("value", _name)
        .build();
    let pop_attr: ByteArray = JsonImpl::new()
        .add("trait", "Population")
        .add("value", _pop)
        .build();
    let seed_attr: ByteArray = JsonImpl::new()
        .add("trait", "Seed")
        .add("value", _seed)
        .build();
    let attributes = array![name_attr, pop_attr, seed_attr].span();

    let metadata = metadata.add_array("attributes", attributes).build();
    format!("data:application/json;base64,{}", bytes_base64_encode(metadata))
}

pub fn generate_svg(planet_id: u64, planet: Planet, planet_name: felt252) -> ByteArray {
    let svg = _build_rotating_planet_svg(planet, planet_name, planet_id);
    format!("data:image/svg+xml;base64,{}", bytes_base64_encode(svg))
}

pub fn generate_details(planet: Planet) -> Span<GameDetail> {
    let pop = format!("{}", planet.population);
    let actions = format!("{}", planet.action_count);
    let seed = format!("{}", planet.seed);

    array![
        GameDetail { name: "Population", value: pop },
        GameDetail { name: "Turns", value: actions },
        GameDetail { name: "Seed", value: seed },
    ]
        .span()
}

// ---------------------------------------------------------------------------
// Animated rotating planet SVG
//
// Layout: 600x600 canvas, planet circle centred at (300,300) r=255.
// Terrain is 8 vertical strips (75px each) repeated twice (1200px total).
// An animateTransform slides the strips -600px over 12 s for seamless spin.
// Lighting + atmosphere overlays are applied on top of the clip group.
// ---------------------------------------------------------------------------

fn _build_rotating_planet_svg(
    planet: Planet, planet_name: felt252, planet_id: u64,
) -> ByteArray {
    let seed: u256 = planet.seed.into();
    let _name = _felt_to_ba(planet_name);
    let _id = format!("{}", planet_id);
    let _pop = format!("{}", planet.population);

    let strips = _build_terrain_strips(seed);

    // Polar cap color: icy if seed byte 30 is even, ochre if odd
    let polar_byte: u32 = ((seed / _pow256(30)) % 256).try_into().unwrap_or(0);
    let polar_color: ByteArray = if polar_byte % 2 == 0 {
        "#dde8ec"
    } else {
        "#c8b87a"
    };

    "<svg xmlns='http://www.w3.org/2000/svg' width='600' height='600'>"
        // -- defs -------------------------------------------------------
        + "<defs>"
        + "<clipPath id='pc'><circle cx='300' cy='300' r='255'/></clipPath>"
        // lit side (top-left highlight)
        + "<radialGradient id='lit' cx='35%' cy='28%' r='65%'>"
        + "<stop offset='0%' stop-color='#fff' stop-opacity='0.28'/>"
        + "<stop offset='100%' stop-color='#000' stop-opacity='0'/>"
        + "</radialGradient>"
        // dark side shadow
        + "<radialGradient id='shad' cx='78%' cy='78%' r='55%'>"
        + "<stop offset='30%' stop-color='#000' stop-opacity='0'/>"
        + "<stop offset='100%' stop-color='#000' stop-opacity='0.72'/>"
        + "</radialGradient>"
        + "</defs>"
        // -- space background -------------------------------------------
        + "<rect width='600' height='600' fill='#050510'/>"
        // -- planet surface (clipped) -----------------------------------
        + "<g clip-path='url(#pc)'>"
        // scrolling terrain
        + "<g>"
        + "<animateTransform attributeName='transform' type='translate' "
        + "from='0,0' to='-600,0' dur='12s' repeatCount='indefinite'/>"
        + strips
        + "</g>"
        // polar caps (static — not inside the scrolling group)
        + "<ellipse cx='300' cy='48' rx='255' ry='55' fill='"
        + polar_color.clone()
        + "' opacity='0.88'/>"
        + "<ellipse cx='300' cy='552' rx='255' ry='55' fill='"
        + polar_color
        + "' opacity='0.88'/>"
        + "</g>"
        // -- lighting overlays ------------------------------------------
        + "<circle cx='300' cy='300' r='255' fill='url(#lit)'/>"
        + "<circle cx='300' cy='300' r='255' fill='url(#shad)'/>"
        // atmosphere rim
        + "<circle cx='300' cy='300' r='255' fill='none' "
        + "stroke='#4a8fd4' stroke-width='4' opacity='0.35'/>"
        // -- labels -----------------------------------------------------
        + "<text x='300' y='578' text-anchor='middle' fill='#6ab4ff' "
        + "font-size='18' font-family='monospace'>"
        + _name
        + "</text>"
        + "<text x='300' y='22' text-anchor='middle' fill='#445566' "
        + "font-size='13' font-family='monospace'>PLANET #"
        + _id
        + "</text>"
        + "</svg>"
}

// ---------------------------------------------------------------------------
// Terrain strip generation
// Extract 8 bytes from the seed (at offsets 0,4,8,...28 bytes) and map each
// to a terrain colour.  Two copies are placed side by side (copy 2 at x+600)
// so the 12-second scroll animation can loop seamlessly.
// ---------------------------------------------------------------------------

fn _build_terrain_strips(seed: u256) -> ByteArray {
    let mut result: ByteArray = "";
    let mut i: u32 = 0;
    loop {
        if i >= 8 {
            break;
        }
        // byte at position (i*4) from the LSB
        let byte_val: u32 = ((seed / _pow256(i * 4)) % 256).try_into().unwrap_or(0);
        let color = _terrain_color(byte_val % 10);

        let x1 = i * 75;
        let x2 = x1 + 600;
        let x1s = format!("{}", x1);
        let x2s = format!("{}", x2);

        result +=
            "<rect x='" + x1s + "' y='0' width='75' height='600' fill='" + color.clone() + "'/>";
        result +=
            "<rect x='" + x2s + "' y='0' width='75' height='600' fill='" + color + "'/>";

        i += 1;
    };
    result
}

// 256^n — used to extract individual bytes from the u256 seed.
fn _pow256(n: u32) -> u256 {
    let mut r: u256 = 1;
    let mut i: u32 = 0;
    loop {
        if i >= n {
            break;
        }
        r *= 256;
        i += 1;
    };
    r
}

fn _terrain_color(idx: u32) -> ByteArray {
    match idx {
        0 => "#1a5f7a", // deep ocean
        1 => "#2a85a0", // shallow ocean
        2 => "#4a7c39", // grassland
        3 => "#1e4d1a", // forest
        4 => "#c8972a", // desert
        5 => "#7a6a5a", // highland
        6 => "#5a5a6a", // mountain
        7 => "#dde8ec", // snow
        8 => "#c8b87a", // beach / scrubland
        _ => "#2a7a5a", // marsh / swamp
    }
}

fn _felt_to_ba(name: felt252) -> ByteArray {
    let mut out: ByteArray = Default::default();
    if name != 0 {
        out.append_word(name, U256BytesUsedTraitImpl::bytes_used(name.into()).into());
    }
    out
}
