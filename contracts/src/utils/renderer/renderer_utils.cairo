// SPDX-License-Identifier: MIT

use planets::models::planet::Planet;
use planets::models::building::Building;
use planets::utils::renderer::encoding::{U256BytesUsedTraitImpl, bytes_base64_encode};
use planets::libs::terrain::{terrain_elevation, terrain_moisture, classify_terrain};
use game_components_interfaces::GameDetail;
use graffiti::json::JsonImpl;

// ---------------------------------------------------------------------------
// Public entry points
// ---------------------------------------------------------------------------

pub fn create_metadata(
    planet_id: u64, planet: Planet, planet_name: felt252, buildings: Span<Building>,
) -> ByteArray {
    let pop = planet.population;
    let seed_val = planet.seed;

    let svg = _build_rotating_planet_svg(planet, planet_name, planet_id, buildings);
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

pub fn generate_svg(
    planet_id: u64, planet: Planet, planet_name: felt252, buildings: Span<Building>,
) -> ByteArray {
    let svg = _build_rotating_planet_svg(planet, planet_name, planet_id, buildings);
    format!("data:image/svg+xml;base64,{}", bytes_base64_encode(svg))
}

pub fn generate_details(planet: Planet) -> Span<GameDetail> {
    array![
        GameDetail { name: 'Population', value: planet.population.into() },
        GameDetail { name: 'Turns', value: planet.action_count.into() },
        GameDetail { name: 'Seed', value: planet.seed },
    ]
        .span()
}

// ---------------------------------------------------------------------------
// Animated rotating planet SVG
// ---------------------------------------------------------------------------

fn _build_rotating_planet_svg(
    planet: Planet,
    planet_name: felt252,
    planet_id: u64,
    buildings: Span<Building>,
) -> ByteArray {
    let _name = _felt_to_ba(planet_name);
    let _id = format!("{}", planet_id);

    let strips = _build_terrain_grid(planet.seed);
    let building_markers = _build_building_markers(buildings);

    "<svg xmlns='http://www.w3.org/2000/svg' width='600' height='600'>"
        + "<defs>"
        + "<clipPath id='pc'><circle cx='300' cy='300' r='255'/></clipPath>"
        + "<radialGradient id='lit' cx='35%' cy='28%' r='65%'>"
        + "<stop offset='0%' stop-color='#fff' stop-opacity='0.28'/>"
        + "<stop offset='100%' stop-color='#000' stop-opacity='0'/>"
        + "</radialGradient>"
        + "<radialGradient id='shad' cx='78%' cy='78%' r='55%'>"
        + "<stop offset='30%' stop-color='#000' stop-opacity='0'/>"
        + "<stop offset='100%' stop-color='#000' stop-opacity='0.72'/>"
        + "</radialGradient>"
        + "</defs>"
        + "<rect width='600' height='600' fill='#050510'/>"
        + "<g clip-path='url(#pc)'>"
        // Scrolling terrain + building markers share the same animating group
        + "<g>"
        + "<animateTransform attributeName='transform' type='translate' "
        + "from='0,0' to='-600,0' dur='20s' repeatCount='indefinite'/>"
        + strips
        + building_markers
        + "</g>"
        // Polar ice-cap overlays (rows 0+1 and 8+9 of the grid are snowy,
        // but the ellipses add a smooth spherical look over the flat grid).
        + "<ellipse cx='300' cy='60' rx='255' ry='70' fill='#dde8ec' opacity='0.72'/>"
        + "<ellipse cx='300' cy='540' rx='255' ry='70' fill='#dde8ec' opacity='0.72'/>"
        + "</g>"
        + "<circle cx='300' cy='300' r='255' fill='url(#lit)'/>"
        + "<circle cx='300' cy='300' r='255' fill='url(#shad)'/>"
        + "<circle cx='300' cy='300' r='255' fill='none' "
        + "stroke='#4a8fd4' stroke-width='4' opacity='0.35'/>"
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
// Building markers
//
// Each building is rendered as a small labelled circle at its terrain
// position, duplicated at x+600 so it loops with the 12-second scroll.
//
// Coordinate mapping (600px canvas):
//   x = lon / 6    (lon 0-3599 → x 0-599)
//   y = lat / 3    (lat 0-1799 → y 0-599)
// ---------------------------------------------------------------------------

fn _build_building_markers(buildings: Span<Building>) -> ByteArray {
    let mut result: ByteArray = "";
    let mut i: u32 = 0;
    loop {
        if i >= buildings.len() {
            break;
        }
        let b = buildings.at(i);
        let lon: u16 = *b.lon;
        let lat: u16 = *b.lat;
        let bt: u8 = *b.building_type;

        let x: u32 = lon.into() / 6_u32;
        let y: u32 = lat.into() / 3_u32;
        let x2: u32 = x + 600;

        let xs = format!("{}", x);
        let ys = format!("{}", y);
        let x2s = format!("{}", x2);

        let (fill, letter): (ByteArray, ByteArray) = if bt == 0 {
            ("#4aaa44", "F") // Farm — green
        } else if bt == 1 {
            ("#999999", "M") // Mine — gray
        } else if bt == 2 {
            ("#4466ee", "B") // Barracks — blue
        } else {
            ("#ddaa22", "W") // Workshop — gold
        };

        let dot = "<circle r='6' fill='"
            + fill.clone()
            + "' stroke='#111' stroke-width='1' opacity='0.92'/>"
            + "<text dy='0.38em' text-anchor='middle' fill='#fff' "
            + "font-size='6' font-weight='bold' font-family='monospace'>"
            + letter.clone()
            + "</text>";

        result += "<g transform='translate("
            + xs.clone()
            + ","
            + ys.clone()
            + ")'>"
            + dot.clone()
            + "</g>"
            + "<g transform='translate("
            + x2s
            + ","
            + ys
            + ")'>"
            + dot
            + "</g>";

        i += 1;
    };
    result
}

// ---------------------------------------------------------------------------
// Terrain grid generation
//
// Renders a 20-column x 10-row grid of terrain cells, each 30x60 px.
// The grid is duplicated (columns rendered at x and x+600) so the
// animateTransform scroll from 0 to -600 loops seamlessly.
// ---------------------------------------------------------------------------

fn _build_terrain_grid(seed: felt252) -> ByteArray {
    let mut result: ByteArray = "";
    // Iterate col-major: col 0-19, row 0-9 per col.
    let mut i: u32 = 0;
    loop {
        if i >= 200 {
            break;
        }
        let col: u32 = i / 10;
        let row: u32 = i % 10;

        let x: u32 = col * 30;
        let y: u32 = row * 60;
        let x2: u32 = x + 600;

        let elevation = terrain_elevation(seed, col, row);
        let moisture = terrain_moisture(seed, col, row);
        let terrain_type = classify_terrain(elevation, moisture, row);
        let color = _terrain_color(terrain_type);

        let xs = format!("{}", x);
        let ys = format!("{}", y);
        let x2s = format!("{}", x2);

        result += "<rect x='"
            + xs
            + "' y='"
            + ys.clone()
            + "' width='30' height='60' fill='"
            + color.clone()
            + "'/>";
        result += "<rect x='"
            + x2s
            + "' y='"
            + ys
            + "' width='30' height='60' fill='"
            + color
            + "'/>";

        i += 1;
    };
    result
}

fn _terrain_color(idx: u32) -> ByteArray {
    match idx {
        0 => "#1a5f7a", // deep ocean
        1 => "#2a85a0", // shallow ocean
        2 => "#4a7c39", // grassland
        3 => "#1e4d1a", // forest
        4 => "#c8972a", // desert
        5 => "#7a6a5a", // highland
        6 => "#5a4a3a", // mountain
        7 => "#dde8ec", // snow
        8 => "#c8b87a", // beach
        _ => "#8a7a50", // scrubland (idx 9)
    }
}

fn _felt_to_ba(name: felt252) -> ByteArray {
    let mut out: ByteArray = Default::default();
    if name != 0 {
        out.append_word(name, U256BytesUsedTraitImpl::bytes_used(name.into()).into());
    }
    out
}
