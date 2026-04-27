# Mono API Reference v1.0 "Mono"

## Lifecycle

A game is composed of three callback functions:

```typescript
function init(): void    // called once when the game starts
function update(): void  // per-frame logic (30fps)
function draw(): void    // per-frame rendering
```
