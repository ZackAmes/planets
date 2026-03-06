This project is a fully onchain colony builder where you will land on a planet and aquire resources, build buildings and tools, grow your
population, and try to survive.

Since it is fully onchain, we want to avoid micromanaging indivual colonists, so it will be more of a macro game where you give 
higher level instructions like % of work vs recreation, % of farming vs mining vs crafting, and in general more allocating people
to tasks that can be sort of abstracted away so we don't have to do too much calculation.

The planet itself should be generated through a combination of noise and the vrf, getting a seed from the vrf that we can plug into a noise fn. There should be various regions with different properties that encourage different activities, like fertile farmland, resource rich mountains, unclaimable oceans, etc.

Then finally there needs to be a lose condition. Over time, there should be an increasing likelyhood of enemies spawning, which will 
attack your colonists and require resources to be put into defenses to stop. 

The goal is a heavily simplified and computationally streamlined rimworld-esque game.