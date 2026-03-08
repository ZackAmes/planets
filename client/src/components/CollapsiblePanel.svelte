<script>
  let { children, title, defaultOpen = true, color = '#7a9' } = $props()
  let isOpen = $state(defaultOpen)
</script>

<div class="collapsible-panel">
  <button class="panel-header" onclick={() => isOpen = !isOpen} style="--title-color:{color}">
    <h3>{title}</h3>
    <span class="toggle">{isOpen ? '−' : '+'}</span>
  </button>
  {#if isOpen}
    <div class="panel-content">
      {@render children()}
    </div>
  {/if}
</div>

<style>
  .collapsible-panel {
    background: rgba(5, 5, 20, 0.85);
    border: 1px solid #1a2a3a;
    border-radius: 8px;
    color: #ccd;
    font-family: monospace;
    font-size: 0.8rem;
    overflow: hidden;
  }

  .panel-header {
    width: 100%;
    display: flex;
    align-items: center;
    justify-content: space-between;
    background: rgba(10, 15, 25, 0.5);
    border: none;
    padding: 0.75rem 1rem;
    cursor: pointer;
    transition: background 0.15s;
  }

  .panel-header:hover {
    background: rgba(15, 20, 30, 0.6);
  }

  h3 {
    font-size: 0.7rem;
    color: var(--title-color);
    text-transform: uppercase;
    letter-spacing: 0.1em;
    margin: 0;
  }

  .toggle {
    font-size: 1rem;
    color: #556;
    line-height: 1;
    user-select: none;
  }

  .panel-content {
    padding: 0.5rem 1rem 1rem;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }
</style>
