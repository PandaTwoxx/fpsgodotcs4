# 3D Game Multiplayer Bun Server

A high-performance single-port WebSocket and HTTP game server built with Bun.

## Features
- **Strictly Single Port**: Serves both HTTP status (`/health`, `/players`, `/`) and WebSocket connections (`ws://host:port`) on the exact same port. No dynamic or secondary ports opened.
- **30 Hz World State Snapshots**: Synchronizes player position, velocity, orientation (yaw & pitch), animation state, health, and combat stats.
- **Event-Driven Combat**: Relays real-time shooting tracers, hit registration, sound events, target knockdown synchronization, and kill feeds.
- **Player Customization**: Supports player name registration and character skins (`survivorMaleB`, `survivorFemaleA`, `zombieA`, `zombieC`).
- **Low Latency**: Bun's native C++ WebSockets provide sub-millisecond packet dispatching and latency tracking.

## Starting the Server
```bash
# Run with default port 8910
bun run server/src/index.ts

# Or with custom port
PORT=9000 bun run server/src/index.ts
```
