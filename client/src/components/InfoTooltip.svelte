<script>
  let { show = false } = $props()
</script>

{#if show}
  <div class="info-tooltip">
    <div class="tooltip-header">💡 Quick Tips</div>
    <ul class="tooltip-list">
      <li><strong>Workers Required:</strong> Buildings need assigned workers to produce!</li>
      <li><strong>Epoch = 30 seconds:</strong> Resources generate every 30 seconds</li>
      <li><strong>Click Buildings:</strong> Select on planet to assign/remove workers</li>
      <li><strong>Water = Life:</strong> Each colonist needs 10 water per epoch or they die</li>
      <li><strong>Houses = Growth:</strong> Only way to increase population</li>
      <li><strong>Resources = Danger:</strong> High stored resources attract invaders</li>
    </ul>
    <div class="tooltip-footer">Buildings without workers produce NOTHING!</div>
  </div>
{/if}

<style>
  .info-tooltip {
    background: rgba(5, 10, 20, 0.95);
    border: 1px solid #2a4a6a;
    border-radius: 6px;
    padding: 0.75rem;
    font-family: monospace;
    font-size: 0.7rem;
    margin-top: 0.5rem;
  }

  .tooltip-header {
    color: #6ab4ff;
    font-weight: bold;
    font-size: 0.75rem;
    margin-bottom: 0.5rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .tooltip-list {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: 0.4rem;
  }

  .tooltip-list li {
    color: #8ac;
    line-height: 1.4;
  }

  .tooltip-list strong {
    color: #6ab4ff;
  }

  .tooltip-footer {
    margin-top: 0.5rem;
    padding-top: 0.5rem;
    border-top: 1px solid #1a2a3a;
    color: #667;
    font-size: 0.65rem;
    font-style: italic;
    text-align: center;
  }
</style>
