import Controller from '@cartridge/controller'
import { CONFIG } from './config.js'

// Session policies: pre-approve the game contract calls so the player
// doesn't get a popup for every transaction.
const policies = {
  contracts: {
    [CONFIG.planetSystemsAddress]: {
      name: 'Planet Systems',
      methods: [
        { name: 'Spawn Planet', entrypoint: 'spawn_planet' },
      ],
    },
    [CONFIG.gameSystemsAddress]: {
      name: 'Game Systems',
      methods: [
        { name: 'Found Colony', entrypoint: 'found_colony' },
        { name: 'Assign Orders', entrypoint: 'assign_orders' },
        { name: 'Construct Building', entrypoint: 'construct_building' },
      ],
    },
  },
}

// Singleton controller instance
export const controller = new Controller({
  policies,
  defaultChainId: '0x534e5f5345504f4c4941', // SN_SEPOLIA
  chains: [{ rpcUrl: CONFIG.rpcUrl }],
})

// ---------------------------------------------------------------------------
// Reactive wallet state (plain JS — no Svelte store dependency)
// ---------------------------------------------------------------------------

let _account = null
let _address = null
const _listeners = new Set()

function notify() {
  _listeners.forEach((fn) => fn({ account: _account, address: _address }))
}

export function subscribe(fn) {
  _listeners.add(fn)
  // Immediately call with current state
  fn({ account: _account, address: _address })
  return () => _listeners.delete(fn)
}

export async function connect() {
  const account = await controller.connect()
  if (!account) return null
  _account = account
  _address = account.address
  notify()
  return account
}

export async function disconnect() {
  await controller.disconnect()
  _account = null
  _address = null
  notify()
}

export function getAccount() {
  return _account
}

export function getAddress() {
  return _address
}
