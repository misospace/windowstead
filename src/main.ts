import './style.css'

type Resource = 'wood' | 'stone'
type TaskKind = 'gather' | 'haul' | 'build'
type StructureKind = 'hut' | 'workshop' | 'garden'
type TileKind = 'ground' | 'tree' | 'rock' | 'stockpile' | 'foundation' | 'hut' | 'workshop' | 'garden'

type PriorityMap = Record<TaskKind, number>
type Inventory = Record<Resource, number>

type Vec2 = { x: number; y: number }

type Worker = {
  id: number
  name: string
  pos: Vec2
  carrying: Partial<Record<Resource, number>>
  task: TaskAssignment | null
  mood: number
}

type Tile = {
  kind: TileKind
  resource?: Resource
  amount?: number
  buildKind?: StructureKind
  stored?: Partial<Record<Resource, number>>
  progress?: number
}

type BuildPlan = {
  id: number
  kind: StructureKind
  pos: Vec2
  delivered: Inventory
  progress: number
  complete: boolean
}

type TaskAssignment = {
  id: string
  kind: TaskKind
  target: Vec2
  buildId?: number
  resource?: Resource
}

type EventEntry = {
  at: number
  text: string
}

type GameState = {
  tick: number
  resources: Inventory
  priorities: PriorityMap
  workers: Worker[]
  map: Tile[][]
  builds: BuildPlan[]
  events: EventEntry[]
  nextBuildId: number
  ambientMood: number
}

const GRID_W = 16
const GRID_H = 10
const TILE = 42
const SAVE_KEY = 'windowstead-save-v1'
const TICK_MS = 250
const STOCKPILE_POS = { x: 7, y: 4 }
const BUILD_COSTS: Record<StructureKind, Inventory> = {
  hut: { wood: 6, stone: 2 },
  workshop: { wood: 4, stone: 6 },
  garden: { wood: 3, stone: 1 },
}

const WORKER_NAMES = ['Jun', 'Mara']

const rootEl = document.querySelector<HTMLDivElement>('#app')
if (!rootEl) throw new Error('App root missing')
const root: HTMLDivElement = rootEl

let state = loadGame() ?? createInitialState()
let lastTick = performance.now()

render()
setInterval(simTick, TICK_MS)
window.addEventListener('beforeunload', () => saveGame(state))

function createInitialState(): GameState {
  const map: Tile[][] = Array.from({ length: GRID_H }, (_, y) =>
    Array.from({ length: GRID_W }, (_, x) => ({ kind: 'ground', ...(seedTile(x, y)) })),
  )
  map[STOCKPILE_POS.y][STOCKPILE_POS.x] = { kind: 'stockpile', stored: {} }

  return {
    tick: 0,
    resources: { wood: 8, stone: 4 },
    priorities: { gather: 3, haul: 2, build: 3 },
    workers: WORKER_NAMES.map((name, index) => ({
      id: index + 1,
      name,
      pos: { x: 6 + index, y: 5 },
      carrying: {},
      task: null,
      mood: 0.7,
    })),
    map,
    builds: [],
    events: [
      { at: 0, text: 'Windowstead wakes up. The tiny crew gets to work.' },
      { at: 0, text: 'Tip: queue a hut, workshop, or garden and let the workers sort themselves out.' },
    ],
    nextBuildId: 1,
    ambientMood: 0.74,
  }
}

function seedTile(x: number, y: number): Partial<Tile> {
  const key = (x * 13 + y * 7 + x * y) % 11
  if (key === 0 || key === 3) return { kind: 'tree', resource: 'wood', amount: 6 }
  if (key === 6 || key === 8) return { kind: 'rock', resource: 'stone', amount: 5 }
  return {}
}

function simTick() {
  const now = performance.now()
  if (now - lastTick < TICK_MS - 5) return
  lastTick = now
  state.tick += 1
  maybeTriggerEvent()
  for (const worker of state.workers) {
    worker.task ??= pickTask(worker)
    if (worker.task) stepWorker(worker)
  }
  render()
}

function pickTask(worker: Worker): TaskAssignment | null {
  const candidates: TaskAssignment[] = []
  const buildTasks = gatherBuildTasks()
  const haulTasks = gatherHaulTasks()
  const gatherTasks = gatherGatherTasks()

  if (state.priorities.build > 0) candidates.push(...buildTasks)
  if (state.priorities.haul > 0) candidates.push(...haulTasks)
  if (state.priorities.gather > 0) candidates.push(...gatherTasks)
  if (!candidates.length) return null

  const weighted = candidates
    .map((task) => ({ task, score: scoreTask(worker, task) }))
    .sort((a, b) => b.score - a.score)

  return weighted[0]?.task ?? null
}

function gatherBuildTasks(): TaskAssignment[] {
  return state.builds
    .filter((build) => !build.complete && hasDeliveredCost(build))
    .map((build) => ({ id: `build-${build.id}`, kind: 'build' as const, target: build.pos, buildId: build.id }))
}

function gatherHaulTasks(): TaskAssignment[] {
  return state.builds.flatMap((build) => {
    if (build.complete) return []
    const needed: TaskAssignment[] = []
    for (const resource of Object.keys(BUILD_COSTS[build.kind]) as Resource[]) {
      const required = BUILD_COSTS[build.kind][resource]
      const delivered = build.delivered[resource]
      if (delivered < required && state.resources[resource] > 0) {
        needed.push({
          id: `haul-${build.id}-${resource}`,
          kind: 'haul',
          target: STOCKPILE_POS,
          buildId: build.id,
          resource,
        })
      }
    }
    return needed
  })
}

function gatherGatherTasks(): TaskAssignment[] {
  const tasks: TaskAssignment[] = []
  forEachTile((tile, pos) => {
    if ((tile.kind === 'tree' || tile.kind === 'rock') && (tile.amount ?? 0) > 0 && tile.resource) {
      tasks.push({ id: `gather-${pos.x}-${pos.y}`, kind: 'gather', target: pos, resource: tile.resource })
    }
  })
  return tasks
}

function scoreTask(worker: Worker, task: TaskAssignment): number {
  const priority = state.priorities[task.kind]
  const distance = manhattan(worker.pos, task.target)
  const haulBoost = task.kind === 'haul' ? 0.6 : 0
  const buildBoost = task.kind === 'build' ? 0.4 : 0
  return priority * 10 - distance + haulBoost + buildBoost
}

function stepWorker(worker: Worker) {
  const task = worker.task
  if (!task) return

  const destination = task.kind === 'haul' && worker.carrying[task.resource ?? 'wood'] ? buildById(task.buildId)?.pos ?? task.target : task.target
  if (!samePos(worker.pos, destination)) {
    worker.pos = moveToward(worker.pos, destination)
    return
  }

  if (task.kind === 'gather') doGather(worker, task)
  if (task.kind === 'haul') doHaul(worker, task)
  if (task.kind === 'build') doBuild(worker, task)
}

function doGather(worker: Worker, task: TaskAssignment) {
  const tile = tileAt(task.target)
  if (!tile || !tile.resource || !tile.amount) {
    worker.task = null
    return
  }
  tile.amount -= 1
  worker.carrying[tile.resource] = (worker.carrying[tile.resource] ?? 0) + 1
  if (tile.amount <= 0) tileAt(task.target)!.kind = 'ground'
  worker.task = { id: `return-${worker.id}-${task.resource}`, kind: 'haul', target: STOCKPILE_POS, resource: tile.resource }
}

function doHaul(worker: Worker, task: TaskAssignment) {
  const resource = task.resource
  if (!resource) {
    worker.task = null
    return
  }

  const carryingAmount = worker.carrying[resource] ?? 0
  if (carryingAmount > 0) {
    if (task.buildId) {
      const build = buildById(task.buildId)
      if (!build || build.complete) {
        state.resources[resource] += carryingAmount
      } else {
        build.delivered[resource] += carryingAmount
      }
      worker.carrying[resource] = 0
      worker.task = null
      return
    }

    state.resources[resource] += carryingAmount
    worker.carrying[resource] = 0
    worker.task = null
    return
  }

  if (samePos(worker.pos, STOCKPILE_POS) && state.resources[resource] > 0 && task.buildId) {
    state.resources[resource] -= 1
    worker.carrying[resource] = 1
    const build = buildById(task.buildId)
    if (build) {
      worker.task = { ...task, target: build.pos }
    } else {
      worker.task = null
    }
    return
  }

  worker.task = null
}

function doBuild(worker: Worker, task: TaskAssignment) {
  const build = buildById(task.buildId)
  if (!build || build.complete) {
    worker.task = null
    return
  }
  build.progress += 0.25
  if (build.progress >= 1) {
    build.complete = true
    const tile = tileAt(build.pos)
    if (tile) {
      tile.kind = build.kind
      tile.progress = undefined
      tile.buildKind = undefined
    }
    pushEvent(`${prettyStructure(build.kind)} finished. The place feels a little more lived in.`)
  }
  worker.task = null
}

function maybeTriggerEvent() {
  if (state.tick % 40 !== 0) return
  const entries = [
    'A kettle clicks somewhere offscreen. Morale rises a notch.',
    'A breeze nudges the tiny settlement. Everyone keeps moving.',
    'The crew pauses, then settles back into their little rhythm.',
  ]
  const text = entries[(state.tick / 40) % entries.length]
  state.ambientMood = Math.min(0.95, state.ambientMood + 0.02)
  pushEvent(text)
}

function hasDeliveredCost(build: BuildPlan) {
  return (Object.keys(BUILD_COSTS[build.kind]) as Resource[]).every((resource) => build.delivered[resource] >= BUILD_COSTS[build.kind][resource])
}

function buildById(id?: number) {
  return state.builds.find((build) => build.id === id)
}

function forEachTile(fn: (tile: Tile, pos: Vec2) => void) {
  state.map.forEach((row, y) => row.forEach((tile, x) => fn(tile, { x, y })))
}

function tileAt(pos: Vec2) {
  return state.map[pos.y]?.[pos.x]
}

function moveToward(from: Vec2, to: Vec2): Vec2 {
  if (from.x !== to.x) return { x: from.x + Math.sign(to.x - from.x), y: from.y }
  if (from.y !== to.y) return { x: from.x, y: from.y + Math.sign(to.y - from.y) }
  return from
}

function samePos(a: Vec2, b: Vec2) {
  return a.x === b.x && a.y === b.y
}

function manhattan(a: Vec2, b: Vec2) {
  return Math.abs(a.x - b.x) + Math.abs(a.y - b.y)
}

function queueBuild(kind: StructureKind) {
  const pos = findOpenGround()
  if (!pos) return
  const build: BuildPlan = {
    id: state.nextBuildId++,
    kind,
    pos,
    delivered: { wood: 0, stone: 0 },
    progress: 0,
    complete: false,
  }
  state.builds.push(build)
  state.map[pos.y][pos.x] = { kind: 'foundation', buildKind: kind, progress: 0 }
  pushEvent(`${prettyStructure(kind)} queued. The crew will haul materials when they can.`)
  render()
}

function findOpenGround(): Vec2 | null {
  for (let y = 0; y < GRID_H; y++) {
    for (let x = 0; x < GRID_W; x++) {
      const tile = state.map[y][x]
      if (tile.kind === 'ground' && manhattan({ x, y }, STOCKPILE_POS) > 3) return { x, y }
    }
  }
  return null
}

function setPriority(kind: TaskKind, delta: number) {
  state.priorities[kind] = Math.max(1, Math.min(5, state.priorities[kind] + delta))
  render()
}

function saveGame(current: GameState) {
  localStorage.setItem(SAVE_KEY, JSON.stringify(current))
}

function loadGame(): GameState | null {
  const raw = localStorage.getItem(SAVE_KEY)
  if (!raw) return null
  try {
    return JSON.parse(raw) as GameState
  } catch {
    return null
  }
}

function resetGame() {
  state = createInitialState()
  saveGame(state)
  render()
}

function pushEvent(text: string) {
  state.events.unshift({ at: state.tick, text })
  state.events = state.events.slice(0, 8)
}

function prettyStructure(kind: StructureKind) {
  return kind[0].toUpperCase() + kind.slice(1)
}

function render() {
  root.innerHTML = `
    <div class="shell">
      <section class="playfield">
        <div class="topbar">
          <div>
            <h1>Windowstead</h1>
            <p>Tiny ambient colony sim, intentionally kept on a short leash.</p>
          </div>
          <div class="resource-strip">
            <span>🪵 ${state.resources.wood}</span>
            <span>🪨 ${state.resources.stone}</span>
            <span>☕ ${(state.ambientMood * 100).toFixed(0)}%</span>
          </div>
        </div>
        <div class="map" style="grid-template-columns: repeat(${GRID_W}, ${TILE}px)">
          ${state.map
            .map((row, y) =>
              row
                .map((tile, x) => `<button class="tile ${tile.kind}">${renderTile(tile, { x, y })}${renderWorkers({ x, y })}</button>`)
                .join(''),
            )
            .join('')}
        </div>
      </section>
      <aside class="sidebar">
        <div class="panel">
          <h2>Queue builds</h2>
          <div class="build-actions">
            ${(['hut', 'workshop', 'garden'] as StructureKind[])
              .map(
                (kind) => `<button data-build="${kind}">${prettyStructure(kind)}<small>${BUILD_COSTS[kind].wood} wood / ${BUILD_COSTS[kind].stone} stone</small></button>`,
              )
              .join('')}
          </div>
        </div>
        <div class="panel">
          <h2>Priorities</h2>
          <div class="priority-list">
            ${(['gather', 'haul', 'build'] as TaskKind[])
              .map(
                (kind) => `<div class="priority-row"><span>${kind}</span><div><button data-priority="${kind}:down">−</button><strong>${state.priorities[kind]}</strong><button data-priority="${kind}:up">+</button></div></div>`,
              )
              .join('')}
          </div>
        </div>
        <div class="panel">
          <h2>Crew</h2>
          ${state.workers
            .map(
              (worker) => `<div class="worker-card"><strong>${worker.name}</strong><span>${worker.task ? worker.task.kind : 'idle'}</span><small>${describeCarry(worker)}</small></div>`,
            )
            .join('')}
        </div>
        <div class="panel">
          <h2>Settlement log</h2>
          <ul class="events">${state.events.map((event) => `<li><small>t${event.at}</small>${event.text}</li>`).join('')}</ul>
        </div>
        <div class="panel panel-actions">
          <button data-action="save">Save</button>
          <button data-action="reset" class="danger">Reset</button>
        </div>
      </aside>
    </div>
  `

  root.querySelectorAll<HTMLButtonElement>('[data-build]').forEach((button) => {
    button.onclick = () => queueBuild(button.dataset.build as StructureKind)
  })
  root.querySelectorAll<HTMLButtonElement>('[data-priority]').forEach((button) => {
    button.onclick = () => {
      const [kind, dir] = (button.dataset.priority ?? '').split(':') as [TaskKind, 'up' | 'down']
      setPriority(kind, dir === 'up' ? 1 : -1)
    }
  })
  root.querySelector('[data-action="save"]')?.addEventListener('click', () => saveGame(state))
  root.querySelector('[data-action="reset"]')?.addEventListener('click', resetGame)
}

function renderTile(tile: Tile, pos: Vec2) {
  if (samePos(pos, STOCKPILE_POS)) return '<span class="emoji">📦</span>'
  if (tile.kind === 'tree') return `<span class="emoji">🌲</span><small>${tile.amount}</small>`
  if (tile.kind === 'rock') return `<span class="emoji">🪨</span><small>${tile.amount}</small>`
  if (tile.kind === 'foundation') return `<span class="emoji">🏗️</span><small>${tile.buildKind}</small>`
  if (tile.kind === 'hut') return '<span class="emoji">🏠</span>'
  if (tile.kind === 'workshop') return '<span class="emoji">🛠️</span>'
  if (tile.kind === 'garden') return '<span class="emoji">🪴</span>'
  return '<span class="emoji faded">·</span>'
}

function renderWorkers(pos: Vec2) {
  return state.workers
    .filter((worker) => samePos(worker.pos, pos))
    .map((worker) => `<span class="worker">${worker.name[0]}</span>`)
    .join('')
}

function describeCarry(worker: Worker) {
  const entries = Object.entries(worker.carrying).filter(([, amount]) => Boolean(amount))
  if (!entries.length) return 'hands free'
  return entries.map(([resource, amount]) => `${amount} ${resource}`).join(', ')
}
