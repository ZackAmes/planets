<script>
  import CollapsiblePanel from './CollapsiblePanel.svelte'
  import { WEAPON_COST, ARMOR_COST } from '../lib/gameLogic.js'

  let {
    gear,
    resources,
    buildings = [],
    oncraftgear,
    disabled = false,
  } = $props()

  let craftWeapons = $state(1)
  let craftArmor = $state(0)

  const hasWorkshop = $derived(
    buildings.some(b => b.buildingType === 7)
  )

  const craftIronCost = $derived(craftWeapons * WEAPON_COST + craftArmor * ARMOR_COST)
  const canCraftAfford = $derived(
    hasWorkshop && (resources?.iron ?? 0) >= craftIronCost && craftIronCost > 0
  )
</script>

<CollapsiblePanel title="Gear Crafting" defaultOpen={false} color="#ff9933">
  <div class="gear-stock">
    <div class="stock-item">
      <span class="stock-label">Weapons</span>
      <span class="stock-value">{gear?.weapons ?? 0}</span>
    </div>
    <div class="stock-item">
      <span class="stock-label">Armor</span>
      <span class="stock-value">{gear?.armor ?? 0}</span>
    </div>
  </div>

  {#if !hasWorkshop}
    <p class="workshop-req">
      Build a Workshop (TC lv2) to unlock gear crafting.
    </p>
  {:else}
    <div class="craft-controls">
      <div class="craft-row">
        <span class="craft-label">Weapons ({WEAPON_COST} iron)</span>
        <div class="craft-ctrl">
          <button class="adj" onclick={() => craftWeapons = Math.max(0, craftWeapons - 1)} {disabled}>-</button>
          <span class="wcount">{craftWeapons}</span>
          <button class="adj" onclick={() => craftWeapons++} {disabled}>+</button>
        </div>
      </div>
      
      <div class="craft-row">
        <span class="craft-label">Armor ({ARMOR_COST} iron)</span>
        <div class="craft-ctrl">
          <button class="adj" onclick={() => craftArmor = Math.max(0, craftArmor - 1)} {disabled}>-</button>
          <span class="wcount">{craftArmor}</span>
          <button class="adj" onclick={() => craftArmor++} {disabled}>+</button>
        </div>
      </div>
    </div>

    <button class="craft-btn" onclick={() => oncraftgear?.(craftWeapons, craftArmor)}
      disabled={!canCraftAfford || disabled}>
      Craft ({craftIronCost} iron)
    </button>
  {/if}
</CollapsiblePanel>

<style>

  .gear-stock {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.3rem;
  }

  .stock-item {
    background: #0a0a18;
    border: 1px solid #1a2030;
    border-radius: 4px;
    padding: 0.3rem 0.5rem;
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  .stock-label {
    color: #556;
    font-size: 0.58rem;
    text-transform: uppercase;
  }

  .stock-value {
    color: #ff9933;
    font-size: 0.9rem;
    font-weight: bold;
    margin-top: 0.1rem;
  }

  .workshop-req {
    font-size: 0.65rem;
    color: #665;
    margin: 0;
    font-style: italic;
    line-height: 1.4;
  }

  .craft-controls {
    display: flex;
    flex-direction: column;
    gap: 0.4rem;
  }

  .craft-row {
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
  }

  .craft-label {
    color: #889;
    font-size: 0.65rem;
  }

  .craft-ctrl {
    display: flex;
    align-items: center;
    gap: 0.3rem;
  }

  .adj {
    background: #1a1a2a;
    border: 1px solid #2a2a4a;
    border-radius: 3px;
    color: #8ecfff;
    font-family: monospace;
    font-size: 0.8rem;
    width: 24px;
    height: 24px;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
  }

  .adj:disabled {
    opacity: 0.3;
    cursor: not-allowed;
  }

  .wcount {
    font-size: 0.8rem;
    color: #aac;
    min-width: 30px;
    text-align: center;
  }

  .craft-btn {
    background: #1a2a1a;
    border: 1px solid #2a5a2a;
    border-radius: 5px;
    color: #88cc88;
    font-family: monospace;
    font-size: 0.75rem;
    padding: 0.4rem;
    cursor: pointer;
    width: 100%;
    transition: background 0.15s;
  }

  .craft-btn:hover:not(:disabled) {
    background: #203520;
  }

  .craft-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }
</style>
