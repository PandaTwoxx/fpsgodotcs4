import type { ServerWebSocket } from "bun";

export interface Player {
  id: string;
  ws: ServerWebSocket<WSData> | null;
  name: string;
  skin: string;
  pos: [number, number, number];
  vel: [number, number, number];
  yaw: number;
  pitch: number;
  anim: string;
  onFloor: boolean;
  hp: number;
  maxHp: number;
  kills: number;
  deaths: number;
  ping: number;
  lastPingTime: number;
  lastSeen: number;
}

interface WSData {
  id: string;
}

const PORT = parseInt(process.env.PORT || "8910", 10);
const HOST = process.env.HOST || "0.0.0.0";
const TICK_RATE = 30; // 30Hz snapshot update

const SPAWN_POINTS: [number, number, number][] = [
  [0, 2.0, 2.5],
  [-12.0, 2.0, 8.0],
  [12.0, 2.0, 8.0],
  [-10.0, 2.0, -12.0],
  [10.0, 2.0, -12.0],
  [0, 2.0, -16.0],
  [-16.0, 2.0, -2.0],
  [16.0, 2.0, -2.0],
];

const SKINS = ["survivorMaleB", "survivorFemaleA", "zombieA", "zombieC"];

const players = new Map<string, Player>();
let playerIdCounter = 0;
const startTime = Date.now();

function getRandomSpawnPoint(): [number, number, number] {
  const idx = Math.floor(Math.random() * SPAWN_POINTS.length);
  const base = SPAWN_POINTS[idx];
  // Add small random jitter so two players don't overlap exactly
  return [
    base[0] + (Math.random() - 0.5) * 1.5,
    base[1],
    base[2] + (Math.random() - 0.5) * 1.5,
  ];
}

function broadcast(data: object, excludeId: string | null = null) {
  const jsonStr = JSON.stringify(data);
  for (const [id, player] of players.entries()) {
    if (excludeId && id === excludeId) continue;
    if (player.ws && player.ws.readyState === 1) {
      player.ws.send(jsonStr);
    }
  }
}

function sendTo(ws: ServerWebSocket<WSData>, data: object) {
  if (ws.readyState === 1) {
    ws.send(JSON.stringify(data));
  }
}

// Start Bun single-port server (HTTP + WebSocket on the same port)
const server = Bun.serve<WSData>({
  port: PORT,
  hostname: HOST,

  fetch(req, server) {
    const url = new URL(req.url);

    // Try WebSocket upgrade for ws:// or wss:// requests
    const upgraded = server.upgrade(req, {
      data: {
        id: `p_${++playerIdCounter}`,
      },
    });

    if (upgraded) {
      return undefined;
    }

    // HTTP Endpoints on the same port
    if (url.pathname === "/health") {
      return new Response(JSON.stringify({ status: "ok" }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    if (url.pathname === "/players") {
      const playerList = Array.from(players.values()).map((p) => ({
        id: p.id,
        name: p.name,
        skin: p.skin,
        kills: p.kills,
        deaths: p.deaths,
        ping: p.ping,
        hp: p.hp,
      }));
      return new Response(JSON.stringify(playerList), {
        headers: { "Content-Type": "application/json" },
      });
    }

    // Default status route
    const statusData = {
      name: "3D Game Multiplayer Server",
      status: "online",
      engine: "Bun",
      port: PORT,
      playersOnline: players.size,
      uptimeSeconds: Math.floor((Date.now() - startTime) / 1000),
      timestamp: new Date().toISOString(),
    };

    return new Response(JSON.stringify(statusData, null, 2), {
      headers: { "Content-Type": "application/json" },
    });
  },

  websocket: {
    open(ws) {
      const id = ws.data.id;
      const defaultSkin = SKINS[playerIdCounter % SKINS.length];
      const defaultName = `Player_${playerIdCounter}`;
      const spawnPos = getRandomSpawnPoint();

      const newPlayer: Player = {
        id,
        ws,
        name: defaultName,
        skin: defaultSkin,
        pos: spawnPos,
        vel: [0, 0, 0],
        yaw: 0,
        pitch: 0,
        anim: "idle",
        onFloor: true,
        hp: 100,
        maxHp: 100,
        kills: 0,
        deaths: 0,
        ping: 0,
        lastPingTime: Date.now(),
        lastSeen: Date.now(),
      };

      players.set(id, newPlayer);
      console.log(`[+] Player connected: ${id} (${defaultName}) | Online: ${players.size}`);

      // Collect existing players info to send to new player
      const existingPlayers: Record<string, any> = {};
      for (const [otherId, otherPlayer] of players.entries()) {
        if (otherId === id) continue;
        existingPlayers[otherId] = {
          id: otherPlayer.id,
          name: otherPlayer.name,
          skin: otherPlayer.skin,
          pos: otherPlayer.pos,
          vel: otherPlayer.vel,
          yaw: otherPlayer.yaw,
          pitch: otherPlayer.pitch,
          anim: otherPlayer.anim,
          hp: otherPlayer.hp,
          maxHp: otherPlayer.maxHp,
          kills: otherPlayer.kills,
          deaths: otherPlayer.deaths,
        };
      }

      // Send initialization message to the newcomer
      sendTo(ws, {
        type: "init",
        id,
        name: defaultName,
        skin: defaultSkin,
        spawn_pos: spawnPos,
        hp: newPlayer.hp,
        players: existingPlayers,
      });

      // Notify everyone else that a new player joined
      broadcast(
        {
          type: "player_join",
          player: {
            id,
            name: defaultName,
            skin: defaultSkin,
            pos: spawnPos,
            vel: [0, 0, 0],
            yaw: 0,
            pitch: 0,
            anim: "idle",
            hp: 100,
            maxHp: 100,
            kills: 0,
            deaths: 0,
          },
        },
        id
      );
    },

    message(ws, rawMessage) {
      const id = ws.data.id;
      const player = players.get(id);
      if (!player) return;

      player.lastSeen = Date.now();

      let msg: any;
      try {
        const text = typeof rawMessage === "string" ? rawMessage : new TextDecoder().decode(rawMessage);
        msg = JSON.parse(text);
      } catch (e) {
        console.warn(`[!] Invalid JSON from ${id}`);
        return;
      }

      if (!msg || typeof msg.type !== "string") return;

      switch (msg.type) {
        // Player joins with custom name & skin
        case "join": {
          if (typeof msg.name === "string" && msg.name.trim().length > 0) {
            player.name = msg.name.trim().substring(0, 24);
          }
          if (typeof msg.skin === "string" && SKINS.includes(msg.skin)) {
            player.skin = msg.skin;
          }
          // Broadcast updated player profile
          broadcast({
            type: "player_profile",
            id: player.id,
            name: player.name,
            skin: player.skin,
          });
          break;
        }

        // Regular state update from client
        case "state": {
          if (Array.isArray(msg.pos) && msg.pos.length === 3) {
            player.pos = [msg.pos[0], msg.pos[1], msg.pos[2]];
          }
          if (Array.isArray(msg.vel) && msg.vel.length === 3) {
            player.vel = [msg.vel[0], msg.vel[1], msg.vel[2]];
          }
          if (typeof msg.yaw === "number") player.yaw = msg.yaw;
          if (typeof msg.pitch === "number") player.pitch = msg.pitch;
          if (typeof msg.anim === "string") player.anim = msg.anim;
          if (typeof msg.on_floor === "boolean") player.onFloor = msg.on_floor;
          break;
        }

        // Shooting event
        case "shoot": {
          broadcast(
            {
              type: "player_shoot",
              shooter_id: id,
              origin: msg.origin,
              hit: msg.hit,
              normal: msg.normal,
              is_target: !!msg.is_target,
            },
            id
          );
          break;
        }

        // Hit registration (shooter damaged target)
        case "hit": {
          const targetId = msg.target_id;
          const damage = typeof msg.damage === "number" ? Math.max(0, msg.damage) : 25;
          const targetPlayer = players.get(targetId);

          if (targetPlayer && targetPlayer.hp > 0) {
            targetPlayer.hp = Math.max(0, targetPlayer.hp - damage);

            if (targetPlayer.hp <= 0) {
              // Target player died!
              player.kills += 1;
              targetPlayer.deaths += 1;

              broadcast({
                type: "player_killed",
                victim_id: targetPlayer.id,
                attacker_id: player.id,
                killer_name: player.name,
                victim_name: targetPlayer.name,
                killer_kills: player.kills,
                victim_deaths: targetPlayer.deaths,
              });

              console.log(`[⚔] ${player.name} killed ${targetPlayer.name}`);
            } else {
              // Target player damaged
              broadcast({
                type: "player_damaged",
                victim_id: targetPlayer.id,
                attacker_id: player.id,
                damage,
                hp: targetPlayer.hp,
              });
            }
          }
          break;
        }

        // Respawn request
        case "respawn": {
          player.hp = player.maxHp;
          const newPos = getRandomSpawnPoint();
          player.pos = newPos;

          broadcast({
            type: "player_respawn",
            id: player.id,
            pos: newPos,
            hp: player.hp,
          });
          break;
        }

        // Practice target hit sync
        case "target_hit": {
          if (typeof msg.target_name === "string") {
            broadcast(
              {
                type: "target_hit",
                target_name: msg.target_name,
                damage: msg.damage || 25,
              },
              id
            );
          }
          break;
        }

        // Crate damage sync
        case "crate_damage": {
          if (typeof msg.crate_name === "string") {
            broadcast(
              {
                type: "crate_damage",
                crate_name: msg.crate_name,
                damage: msg.damage || 25,
              },
              id
            );
          }
          break;
        }

        // Chat message
        case "chat": {
          if (typeof msg.text === "string" && msg.text.trim().length > 0) {
            const cleanText = msg.text.trim().substring(0, 120);
            broadcast({
              type: "chat",
              id: player.id,
              sender: player.name,
              text: cleanText,
              time: Date.now(),
            });
            console.log(`[Chat] ${player.name}: ${cleanText}`);
          }
          break;
        }

        // Latency ping
        case "ping": {
          const clientTimestamp = typeof msg.t === "number" ? msg.t : Date.now();
          if (typeof msg.ping === "number") {
            player.ping = Math.round(msg.ping);
          }
          sendTo(ws, {
            type: "pong",
            t: clientTimestamp,
            s: Date.now(),
          });
          break;
        }

        default:
          break;
      }
    },

    close(ws, code, reason) {
      const id = ws.data.id;
      const player = players.get(id);
      if (player) {
        players.delete(id);
        console.log(`[-] Player disconnected: ${id} (${player.name}) | Online: ${players.size}`);
        broadcast({
          type: "player_leave",
          id,
          name: player.name,
        });
      }
    },
  },
});

// Periodic snapshot broadcast at TICK_RATE (30Hz)
setInterval(() => {
  if (players.size === 0) return;

  const snapshot: Record<string, any> = {};
  for (const [id, p] of players.entries()) {
    snapshot[id] = {
      pos: [
        Math.round(p.pos[0] * 1000) / 1000,
        Math.round(p.pos[1] * 1000) / 1000,
        Math.round(p.pos[2] * 1000) / 1000,
      ],
      vel: [
        Math.round(p.vel[0] * 100) / 100,
        Math.round(p.vel[1] * 100) / 100,
        Math.round(p.vel[2] * 100) / 100,
      ],
      yaw: Math.round(p.yaw * 1000) / 1000,
      pitch: Math.round(p.pitch * 1000) / 1000,
      anim: p.anim,
      on_floor: p.onFloor,
      hp: p.hp,
      kills: p.kills,
      deaths: p.deaths,
      ping: p.ping,
    };
  }

  broadcast({
    type: "world_state",
    time: Date.now(),
    players: snapshot,
  });
}, 1000 / TICK_RATE);

console.log(`===============================================`);
console.log(`  3D GAME MULTIPLAYER BUN SERVER READY        `);
console.log(`  Listening on: http://${HOST}:${PORT}         `);
console.log(`  WebSocket URL: ws://127.0.0.1:${PORT}        `);
console.log(`  Tick Rate:    ${TICK_RATE} Hz               `);
console.log(`  Dynamic Ports: NONE (Single Port Only)      `);
console.log(`===============================================`);
