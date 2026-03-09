<script>
  import { BUILDING_INFO, formatLonLat, upgradeBuildingCost } from '../lib/gameLogic.js'

  let {
    buildings = [],
    colonists = { assigned: null, unassigned: null },
    resources = null,
    tcLevel = 1,
    disabled = false,
    onbuildingselect,
    onupgradebuilding,
  } = $props()

  let activeTab = $state('buildings')

  const workerBuildings = $derived(buildings.filter(b => b.maxWorkers > 0))
  const utilityBuildings = $derived(buildings.filter(b => b.maxWorkers === 0))
  
  function selectBuilding(lon, lat) {
    onbuildingselect?.(lon, lat)
  }

  function canUpgradeBuilding(b) {
    const level = b.level ?? 1
    if ((b.maxWorkers ?? 0) === 0) return false
    if (level >= 3) return false
    if (level >= tcLevel) return false
    const cost = upgradeBuildingCost(level)
    return (resources?.iron ?? 0) >= cost.iron
  }

  function handleUpgradeClick(event, b) {
    event.stopPropagation()
    if (!canUpgradeBuilding(b) || disabled) return
    onupgradebuilding?.(b.lon, b.lat)
  }
</script>

<div class="lists-container">
  <div class="tabs">
    <button 
      class="tab" 
      class:active={activeTab === 'buildings'}
      onclick={() => activeTab = 'buildings'}>
      Buildings ({buildings.length})
    </button>
    <button 
      class="tab"
      class:active={activeTab === 'colonists'}
      onclick={() => activeTab = 'colonists'}>
      Colonists
    </button>
  </div>

  <div class="tab-content">
    {#if activeTab === 'buildings'}
      {#if buildings.length === 0}
        <p class="empty">No buildings yet. Enter Build Mode to construct!</p>
      {:else}
        {#if workerBuildings.length > 0}
          <div class="section">
            <h4>Production Buildings</h4>
            {#each workerBuildings as b}
              {@const info = BUILDING_INFO[b.buildingType]}
              {@const upCost = upgradeBuildingCost(b.level ?? 1)}
              <div class="list-item" role="button" tabindex="0" onclick={() => selectBuilding(b.lon, b.lat)} onkeydown={(e) => (e.key === 'Enter' || e.key === ' ') && selectBuilding(b.lon, b.lat)}>
                <span class="building-icon" style="background:{info?.color}"></span>
                <div class="item-info">
                  <span class="item-name">{info?.name}</span>
                  <span class="item-detail">lv{b.level ?? 1} · {b.workers}/{b.maxWorkers}w · {formatLonLat(b.lon, b.lat)}</span>
                </div>
                {#if (b.level ?? 1) < 3}
                  <button
                    class="upgrade-mini"
                    onclick={(e) => handleUpgradeClick(e, b)}
                    disabled={disabled || !canUpgradeBuilding(b)}
                    title="Upgrade ({upCost.iron} iron)"
                  >
                    +lv
                  </button>
                {/if}
              </div>
            {/each}
          </div>
        {/if}

        {#if utilityBuildings.length > 0}
          <div class="section">
            <h4>Utility Buildings</h4>
            {#each utilityBuildings as b}
              {@const info = BUILDING_INFO[b.buildingType]}
              <div class="list-item" role="button" tabindex="0" onclick={() => selectBuilding(b.lon, b.lat)} onkeydown={(e) => (e.key === 'Enter' || e.key === ' ') && selectBuilding(b.lon, b.lat)}>
                <span class="building-icon" style="background:{info?.color}"></span>
                <div class="item-info">
                  <span class="item-name">{info?.name}</span>
                  <span class="item-detail">lv{b.level ?? 1} · {formatLonLat(b.lon, b.lat)}</span>
                </div>
              </div>
            {/each}
          </div>
        {/if}
      {/if}
    {:else}
      <div class="section">
        <h4>Population</h4>
        <div class="colonist-stats">
          <div class="stat-row">
            <span class="stat-label">Assigned Workers</span>
            <span class="stat-value">{colonists.assigned?.count ?? 0}</span>
          </div>
          <div class="stat-row">
            <span class="stat-label">Free Colonists</span>
            <span class="stat-value">{colonists.unassigned?.count ?? 0}</span>
          </div>
          <div class="stat-row">
            <span class="stat-label">Total Strength</span>
            <span class="stat-value">{(colonists.assigned?.totalStrength ?? 0) + (colonists.unassigned?.totalStrength ?? 0)}</span>
          </div>
          <div class="stat-row">
            <span class="stat-label">Avg Fighter Strength</span>
            <span class="stat-value">
              {colonists.unassigned?.count > 0 
                ? Math.round((colonists.unassigned.totalStrength ?? 0) / colonists.unassigned.count)
                : 1}
            </span>
          </div>
        </div>
      </div>
    {/if}
  </div>
</div>

<style>
  .lists-container {
    background: rgba(5, 5, 20, 0.85);
    border: 1px solid #1a2a3a;
    border-radius: 8px;
    color: #ccd;
    font-family: monospace;
    font-size: 0.8rem;
    overflow: hidden;
  }
  .tabs {
    display: flex;
    gap: 0;
    border-bottom: 1px solid #1a2a3a;
  }

  .tab {
    flex: 1;
    background: rgba(10, 15, 25, 0.3);
    border: none;
    border-bottom: 2px solid transparent;
    padding: 0.6rem;
    color: #667;
    font-family: monospace;
    font-size: 0.7rem;
    cursor: pointer;
    transition: all 0.15s;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .tab:hover {
    background: rgba(15, 20, 30, 0.4);
    color: #8ac;
  }

  .tab.active {
    color: #6ab4ff;
    border-bottom-color: #6ab4ff;
    background: rgba(15, 25, 40, 0.5);
  }

  .tab-content {
    max-height: 400px;
    overflow-y: auto;
    padding: 0.75rem;
  }

  .tab-content::-webkit-scrollbar {
    width: 4px;
  }

  .tab-content::-webkit-scrollbar-track {
    background: rgba(10, 10, 20, 0.3);
  }

  .tab-content::-webkit-scrollbar-thumb {
    background: rgba(100, 120, 140, 0.5);
    border-radius: 2px;
  }

  .empty {
    color: #667;
    font-size: 0.7rem;
    margin: 1rem 0;
    text-align: center;
    font-style: italic;
  }

  .section {
    display: flex;
    flex-direction: column;
    gap: 0.3rem;
    margin-bottom: 0.5rem;
  }

  .section:last-child {
    margin-bottom: 0;
  }

  h4 {
    font-size: 0.62rem;
    color: #667;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    margin: 0 0 0.2rem 0;
  }

  .list-item {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    background: #0a0a18;
    border: 1px solid #1a2030;
    border-radius: 4px;
    padding: 0.4rem 0.5rem;
    cursor: pointer;
    transition: all 0.15s;
    text-align: left;
  }

  .upgrade-mini {
    background: #1a2a1a;
    border: 1px solid #3a6a3a;
    border-radius: 3px;
    color: #6aff6a;
    font-family: monospace;
    font-size: 0.58rem;
    padding: 0.1rem 0.3rem;
    cursor: pointer;
    margin-left: 0.35rem;
  }

  .upgrade-mini:hover:not(:disabled) {
    background: #253525;
  }

  .upgrade-mini:disabled {
    opacity: 0.35;
    cursor: not-allowed;
  }

  .list-item:hover {
    background: #0e0e22;
    border-color: #2a3a5a;
  }

  .building-icon {
    width: 12px;
    height: 12px;
    border-radius: 50%;
    flex-shrink: 0;
  }

  .item-info {
    display: flex;
    flex-direction: column;
    gap: 0.1rem;
    flex: 1;
  }

  .item-name {
    font-size: 0.72rem;
    color: #aaddff;
    font-weight: bold;
  }

  .item-detail {
    font-size: 0.6rem;
    color: #667;
  }

  .colonist-stats {
    display: flex;
    flex-direction: column;
    gap: 0.3rem;
  }

  .stat-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    background: #0a0a18;
    border: 1px solid #1a2030;
    border-radius: 4px;
    padding: 0.35rem 0.5rem;
  }

  .stat-label {
    font-size: 0.68rem;
    color: #667;
  }

  .stat-value {
    font-size: 0.75rem;
    color: #aaddff;
    font-weight: bold;
  }
</style>
