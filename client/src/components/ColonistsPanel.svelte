<script>
  import CollapsiblePanel from './CollapsiblePanel.svelte'
  import { tcUpgradeCost, COLONIST_DEFAULT_STRENGTH, COLONIST_MAX_STRENGTH } from '../lib/gameLogic.js'

  let {
    assigned,
    unassigned,
    resources,
    tcLevel = 1,
    onupgradetc,
    disabled = false,
  } = $props()

  const tcCost = $derived(tcUpgradeCost(tcLevel))
  const canUpgradeTc = $derived(
    tcLevel < 5 &&
    (resources?.iron ?? 0) >= tcCost.iron &&
    (resources?.uranium ?? 0) >= tcCost.uranium
  )

  const avgFighterStrength = $derived(
    unassigned?.count > 0
      ? Math.max(1, Math.round((unassigned?.totalStrength ?? 0) / unassigned.count))
      : COLONIST_DEFAULT_STRENGTH
  )
</script>

<CollapsiblePanel title="Colonists & TC" defaultOpen={true}>
  <div class="colonists">
    <div class="col-chip">
      <span class="label">Assigned</span>
      <span class="value">{assigned?.count ?? 0}</span>
      <span class="hint">working</span>
    </div>
    
    <div class="col-chip">
      <span class="label">Free</span>
      <span class="value">{unassigned?.count ?? 0}</span>
      <span class="hint">idle</span>
    </div>
    
    <div class="col-chip str-chip">
      <span class="label">Avg Str</span>
      <span class="value str-val">
        {avgFighterStrength}
        <span class="str-max">/{COLONIST_MAX_STRENGTH}</span>
      </span>
      <span class="hint">fighters</span>
    </div>
  </div>

  <div class="divider"></div>

  <button class="tc-btn" onclick={onupgradetc}
    disabled={!canUpgradeTc || disabled || tcLevel >= 5}>
    {#if tcLevel >= 5}
      TC Max Level
    {:else}
      Upgrade TC lv{tcLevel}→{tcLevel + 1}
      <span class="cost-detail">
        {tcCost.iron} iron{tcCost.uranium > 0 ? ` + ${tcCost.uranium} U` : ''}
      </span>
    {/if}
  </button>
</CollapsiblePanel>

<style>

  .colonists {
    display: grid;
    grid-template-columns: 1fr 1fr 1fr;
    gap: 0.3rem;
  }

  .col-chip {
    background: #0a0a18;
    border: 1px solid #1a2030;
    border-radius: 4px;
    padding: 0.3rem 0.4rem;
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
  }

  .label {
    color: #556;
    font-size: 0.58rem;
    text-transform: uppercase;
  }

  .value {
    color: #aaddff;
    font-size: 0.9rem;
    font-weight: bold;
    margin: 0.1rem 0;
  }

  .hint {
    color: #445;
    font-size: 0.55rem;
    font-style: italic;
  }

  .str-chip {
    background: #0a0a18;
    border-color: #1a2a1a;
  }

  .str-val {
    color: #4466ff;
  }

  .str-max {
    font-size: 0.6rem;
    color: #2a3a5a;
  }

  .divider {
    border-top: 1px solid #1a2a3a;
    margin: 0.1rem 0;
  }

  .tc-btn {
    background: #2a2a10;
    border: 1px solid #5a5a20;
    border-radius: 6px;
    color: #ffdd44;
    font-family: monospace;
    font-size: 0.72rem;
    padding: 0.4rem;
    cursor: pointer;
    width: 100%;
    transition: background 0.15s;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.2rem;
  }

  .tc-btn:hover:not(:disabled) {
    background: #3a3a18;
  }

  .tc-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .cost-detail {
    font-size: 0.62rem;
    color: #bb9933;
  }
</style>
