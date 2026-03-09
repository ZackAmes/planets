<script>
  import { previewFight, COLONIST_DEFAULT_STRENGTH } from '../lib/gameLogic.js'

  let {
    invader,
    unassigned,
    resources,
    cannonDamageRate = 0,
    onfight,
    disabled = false,
  } = $props()

  let fightColonists = $state(1)

  const avgFighterStrength = $derived(
    unassigned?.count > 0
      ? Math.max(1, Math.round((unassigned?.totalStrength ?? 0) / unassigned.count))
      : COLONIST_DEFAULT_STRENGTH
  )

  const fightPreview = $derived(
    invader?.active
      ? previewFight(invader, fightColonists, avgFighterStrength)
      : null
  )

  const canFight = $derived(
    invader?.active &&
    fightColonists > 0 &&
    fightColonists <= (unassigned?.count ?? 0)
  )

  const rawDmg = $derived(invader?.active ? Math.floor((invader.strength ?? 0) / 20) + 1 : 0)
  const defAbsorb = $derived(Math.min(Math.floor(rawDmg / 2) + 1, resources?.defense ?? 0))
  const netDmg = $derived(Math.max(1, rawDmg - defAbsorb))
</script>

{#if invader?.active}
  {@const passiveDmg = Math.floor(invader.strength / 20) + 1}
  {@const netInvDmg = Math.max(0, passiveDmg - cannonDamageRate)}
  
  <div class="panel danger">
    <h3 class="threat-title">⚠ INVADERS ATTACKING</h3>
    
    <div class="invader-stats">
      <div class="inv-stat">
        <span class="inv-label">Strength</span>
        <span class="inv-val danger">{invader.strength}</span>
      </div>
      <div class="inv-stat">
        <span class="inv-label">Attacks In</span>
        <span class="inv-val" class:critical={invader.epochsUntilAttack <= 1}>
          {invader.epochsUntilAttack} epoch{invader.epochsUntilAttack !== 1 ? 's' : ''}
        </span>
      </div>
      {#if cannonDamageRate > 0}
        <div class="inv-stat">
          <span class="inv-label">Cannon</span>
          <span class="inv-val safe">-{cannonDamageRate}/ep</span>
        </div>
      {/if}
    </div>

    <div class="attack-warning" class:critical={invader.epochsUntilAttack <= 1}>
      <p class="attack-message">
        {#if invader.epochsUntilAttack === 0}
          ⚠️ ATTACK IMMINENT! ~{netDmg} casualties this epoch!
        {:else if invader.epochsUntilAttack === 1}
          ⚠️ Attack next epoch! ~{netDmg} casualties expected!
        {:else}
          Attacks in {invader.epochsUntilAttack} epochs — ~{netDmg} casualties/attack
        {/if}
      </p>
      {#if cannonDamageRate > 0}
        <p class="cannon-hint">Cannons reduce strength by {cannonDamageRate}/ep</p>
      {/if}
    </div>

    <div class="fight-setup">
      <div class="fight-row">
        <span class="fight-label">
          Colonists <span class="str-hint">(str {avgFighterStrength} each)</span>
        </span>
        <div class="fight-ctrl">
          <button class="adj" onclick={() => fightColonists = Math.max(1, fightColonists - 1)} disabled={disabled}>-</button>
          <span class="wcount">{fightColonists}/{unassigned?.count ?? 0}</span>
          <button class="adj" onclick={() => fightColonists = Math.min(unassigned?.count ?? 0, fightColonists + 1)} disabled={disabled}>+</button>
        </div>
      </div>
    </div>

    {#if fightPreview}
      <div class="fight-preview" class:win={fightPreview.willWin} class:lose={!fightPreview.willWin}>
        <span>Power ~{fightPreview.fighterPower} (±25%)</span>
        <span class="vs-label">vs {fightPreview.invaderStrength}</span>
        <span class="outcome">
          {fightPreview.willWin ? 'WIN' : 'LOSE'} · ~{fightPreview.estimatedCasualties} cas.
        </span>
      </div>
    {/if}

    <button class="fight-btn" onclick={() => onfight?.(fightColonists)}
      disabled={!canFight || disabled}>
      {disabled ? 'Fighting…' : 'Send Fighters'}
    </button>
  </div>
{/if}

<style>
  @keyframes danger-pulse {
    0%, 100% { border-color: #6a1a1a; box-shadow: 0 0 0 0 rgba(180, 20, 20, 0); }
    50% { border-color: #cc2222; box-shadow: 0 0 12px 2px rgba(180, 20, 20, 0.25); }
  }

  .panel {
    background: rgba(30, 5, 5, 0.9);
    border: 1px solid #8a2020;
    border-radius: 8px;
    padding: 1rem;
    color: #ccd;
    font-family: monospace;
    font-size: 0.8rem;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .panel.danger {
    animation: danger-pulse 2s ease-in-out infinite;
  }

  h3 {
    font-size: 0.75rem;
    color: #ff4444;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    margin: 0;
  }

  .threat-title {
    text-align: center;
  }

  .invader-stats {
    display: flex;
    gap: 0.3rem;
    justify-content: space-around;
  }

  .inv-stat {
    background: #0a0308;
    border: 1px solid #2a0a0a;
    border-radius: 3px;
    padding: 0.2rem 0.4rem;
    display: flex;
    flex-direction: column;
    align-items: center;
    flex: 1;
  }

  .inv-label {
    font-size: 0.55rem;
    color: #664;
    text-transform: uppercase;
  }

  .inv-val {
    font-size: 0.8rem;
    font-weight: bold;
    color: #aaa;
    margin-top: 0.1rem;
  }

  .inv-val.danger {
    color: #ff4444;
  }

  .inv-val.safe {
    color: #44cc66;
  }

  .inv-val.critical {
    color: #ff4444;
    animation: danger-pulse 1s ease-in-out infinite;
  }

  .attack-warning {
    background: #1a0a00;
    border: 1px solid #4a2a00;
    border-radius: 4px;
    padding: 0.5rem;
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
  }

  .attack-warning.critical {
    background: #1a0000;
    border-color: #6a1a1a;
    animation: danger-pulse 1.5s ease-in-out infinite;
  }

  .attack-message {
    font-size: 0.7rem;
    color: #cc8844;
    margin: 0;
    text-align: center;
    font-weight: bold;
  }

  .attack-warning.critical .attack-message {
    color: #ff4444;
  }

  .cannon-hint {
    font-size: 0.6rem;
    color: #44aa66;
    margin: 0;
    text-align: center;
    font-style: italic;
  }

  .defense-warn {
    font-size: 0.65rem;
    color: #cc8844;
    margin: 0;
    padding: 0.25rem 0.4rem;
    border-radius: 3px;
    background: #1a0a00;
    border: 1px solid #4a2a00;
    text-align: center;
  }

  .defense-warn.critical {
    color: #ff4444;
    background: #1a0000;
    border-color: #6a1a1a;
  }

  .defense-ok {
    font-size: 0.63rem;
    color: #44aa66;
    margin: 0;
    text-align: center;
  }

  .fight-setup {
    display: flex;
    flex-direction: column;
    gap: 0.4rem;
  }

  .fight-row {
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
  }

  .fight-label {
    color: #889;
    font-size: 0.65rem;
  }

  .str-hint {
    color: #4466ff;
    font-size: 0.6rem;
  }

  .fight-ctrl {
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
    min-width: 40px;
    text-align: center;
  }

  .fight-preview {
    font-size: 0.65rem;
    margin: 0;
    padding: 0.3rem 0.5rem;
    border-radius: 4px;
    background: #0a0a18;
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 0.3rem;
  }

  .fight-preview.win {
    border: 1px solid #1a4a2a;
  }

  .fight-preview.lose {
    border: 1px solid #4a1a1a;
  }

  .vs-label {
    color: #556;
  }

  .outcome {
    font-weight: bold;
  }

  .fight-preview.win .outcome {
    color: #6aff9a;
  }

  .fight-preview.lose .outcome {
    color: #ff6a6a;
  }

  .fight-btn {
    background: #3a1a1a;
    border: 1px solid #7a2a2a;
    border-radius: 6px;
    color: #ff8888;
    font-family: monospace;
    font-size: 0.8rem;
    padding: 0.5rem;
    cursor: pointer;
    width: 100%;
    letter-spacing: 0.05em;
    transition: background 0.15s;
  }

  .fight-btn:hover:not(:disabled) {
    background: #5a2020;
    border-color: #aa3030;
  }

  .fight-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }
</style>
