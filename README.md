# windowstead

Relaxing desktop game.

## Current prototype direction

A tiny desktop-overlay colony sim with:
- 2 autonomous workers
- gather / haul / build priorities
- 3 starter structures
- lightweight ambient event log
- save / load

The goal for the first playable is simple: something cozy that can sit in the corner of the desktop and visibly make progress without demanding constant input.

## Development

```bash
npm install
npm run dev
```

## First-pass stack

- TypeScript
- Vite
- plain DOM/CSS
- grid-based simulation loop

That is intentionally boring. The first job is getting a visible playable loop on screen, not winning architecture awards.
