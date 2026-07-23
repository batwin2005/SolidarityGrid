# SolidarityGrid — Malla de Procesamiento de Pagos Distribuido
# SolidarityGrid — Distributed Payment Processing Mesh

> *"Ningún nodo cae solo." / "No node falls alone."*

[Español](#español) • [English](#english)

---

## Español

Una malla de procesamiento de pagos peer-to-peer auto-curativa construida en .NET 8 con cero dependencias externas. Los nodos cooperan mediante protocolos de gossip y failover automático — si un nodo muere mientras procesa una transacción, sus vecinos detectan la falla y completan el trabajo.

### Arquitectura

```
                    ┌──────────────────┐
                    │  Cliente / App   │
                    │ (curl / script)  │
                    └────────┬─────────┘
                             │ POST /pay (Round-Robin)
                             ▼
              ┌─────────────────────────────┐
              │    Malla HTTP / Gossip       │
              │  ♥ Heartbeat │ 📡 Estado    │
              │  cada 2s     │ cada 2s       │
              └─────────────────────────────┘
                    │        │        │
         ┌──────────┘  ┌─────┴──────┐  └──────────┐
         ▼             ▼            ▼             ▼
   ┌──────────┐  ┌──────────┐  ┌──────────┐
   │  Nodo A  │◄─┤  Nodo B  │──►│  Nodo C  │
   │ :5001    │──┤ :5002    │◄─┤ :5003    │
   └──────────┘  └──────────┘  └──────────┘
         │             │             │
         └─────────────┴─────────────┘
           Gossip / Heartbeat / Claim
```

### Estrategia de Comunicación

| Protocolo | Mecanismo | Intervalo |
|-----------|-----------|-----------|
| **Heartbeat** | `GET /health` → pares | Cada 2s |
| **Gossip** | Intercambio de estado vía `POST /gossip` | Cada 2s (+ inmediato en nueva tx) |
| **Claim** | Bloqueo distribuido vía `POST /claim` (compare-and-swap) | Bajo demanda durante recuperación |

### Flujo de Detección y Recuperación

```
1. Cliente → POST /pay → Nodo A
2. Nodo A crea TX-99, inmediatamente hace gossip a B y C
3. Nodo A empieza a procesar (delay simulado de 5-10s)
4. 🔥 CAOS: Nodo A es eliminado en t=3s
5. Nodo B pierde 2 heartbeats consecutivos de A (~6s)
6. Nodo B marca Nodo A como MUERTO
7. Nodo B escanea su estado → encuentra TX-99 (Processing, owner=NodoA) → HUÉRFANA
8. Nodo B envía POST /claim al Nodo C (único par sobreviviente)
9. Nodo C registra atómicamente: "TX-99 → reclamado por Nodo B" → devuelve OK
10. Nodo B toma posesión, marca TX-99 → COMPLETADA
11. Cliente ve TX-99 como Completada ✓
```

### Garantías de Consistencia

- **Idempotencia**: Cada transacción tiene un `Id` único de 8 caracteres hex. El endpoint `POST /claim` usa `ConcurrentDictionary.GetOrAdd` — el primer reclamante gana atómicamente.
- **Sin doble gasto**: Una transacción solo puede ser reclamada por un nodo. Los pares validan la propiedad antes de reconocer un reclamo.
- **Fusión de estado**: Durante el gossip, las transacciones solo avanzan hacia adelante (`Pendiente → Procesando → Completada`). Un estado `Completada` sobrescribe cualquier estado menor.

### Inicio Rápido

#### Prerrequisitos

- Docker & Docker Compose

#### Ejecutar con Docker

```bash
docker compose up --build -d
```

Este comando construye e inicia los 3 nodos. Cada nodo:
- Recibe un `NODE_ID` único (`NodeA`, `NodeB`, `NodeC`)
- Descubre sus pares via la variable `PEERS`
- Escucha en el puerto `5000` (mapeado a `5001`, `5002`, `5003` en el host)

#### Ejecutar Local (Sin Docker)

```bash
# Prerrequisitos: .NET 8 SDK
dotnet build src/SolidarityGrid.Node -c Release

# Terminal 1 - NodeA
set NODE_ID=NodeA && set PEERS=http://localhost:5002,http://localhost:5003 && set ASPNETCORE_URLS=http://0.0.0.0:5001 && dotnet run --project src/SolidarityGrid.Node --no-build -c Release

# Terminal 2 - NodeB
set NODE_ID=NodeB && set PEERS=http://localhost:5001,http://localhost:5003 && set ASPNETCORE_URLS=http://0.0.0.0:5002 && dotnet run --project src/SolidarityGrid.Node --no-build -c Release

# Terminal 3 - NodeC
set NODE_ID=NodeC && set PEERS=http://localhost:5001,http://localhost:5002 && set ASPNETCORE_URLS=http://0.0.0.0:5003 && dotnet run --project src/SolidarityGrid.Node --no-build -c Release
```

> **Nota**: En Linux/macOS usa `export` en lugar de `set`.

#### Verificar el Clúster

```bash
curl http://localhost:5001/health
curl http://localhost:5002/health
curl http://localhost:5003/health
```

Salida esperada:
```json
{"nodeId":"NodeA","alive":true,"transactionCount":0,"peerCount":2,"timestamp":"..."}
```

### Chaos Test (Falla Simulada)

> Observa a SolidarityGrid auto-curarse en tiempo real.

#### Tutorial Manual

**Terminal 1** — Ver logs:
```bash
docker compose logs -f
```

**Terminal 2** — Inyectar caos:
```bash
# 1. Enviar un pago a cualquier nodo
curl -X POST http://localhost:5002/pay \
  -H "Content-Type: application/json" \
  -d '{"amount": 99.95, "currency": "USD"}'

# 2. Antes de que termine (dentro de 5s), matar el nodo que procesa
docker stop solidaritygrid-node-a

# 3. Esperar ~10s para recuperación, luego verificar
curl http://localhost:5002/transactions
curl http://localhost:5003/transactions

# 4. Reiniciar el nodo muerto
docker start solidaritygrid-node-a
```

#### Script Automatizado

```bash
# PowerShell (Windows)
.\scripts\chaos-test.ps1

# Bash (Linux/macOS)
chmod +x scripts/chaos-test.sh && ./scripts/chaos-test.sh
```

### Estructura del Proyecto

```
SolidarityGrid/
├── docker-compose.yml               # Orquestación de 3 nodos
├── Dockerfile                        # Imagen .NET 8 para contenedor
├── src/SolidarityGrid.Node/
│   ├── SolidarityGrid.Node.csproj
│   ├── Program.cs                    # Punto de entrada, configuración DI
│   ├── Models/
│   │   ├── Transaction.cs            # Entidad de transacción + máquina de estados
│   │   ├── GossipPayload.cs          # DTO de intercambio gossip
│   │   └── Dtos.cs                   # DTOs de solicitud/respuesta
│   ├── Services/
│   │   ├── NodeState.cs              # Singleton: identidad, pares, almacenamiento en memoria
│   │   ├── HeartbeatService.cs       # Background: ping a pares cada 2s
│   │   ├── GossipService.cs          # Background: intercambio de estado cada 2s
│   │   └── RecoveryService.cs        # Background: detección de huérfanas + reclamación
│   └── Controllers/
│       ├── PaymentController.cs      # POST /pay, GET /transactions
│       └── NodeController.cs         # GET /health, POST /gossip, POST /claim
├── scripts/
│   ├── chaos-test.ps1                # Chaos test (PowerShell)
│   └── chaos-test.sh                 # Chaos test (Bash)
└── README.md
```

### Referencia de API

| Método | Endpoint | Descripción |
|--------|----------|-------------|
| `POST` | `/pay` | Enviar un pago (asíncrono, respuesta inmediata) |
| `GET` | `/transactions` | Listar todas las transacciones conocidas |
| `GET` | `/transactions/{id}` | Obtener una transacción específica |
| `GET` | `/health` | Health check (usado por heartbeat) |
| `POST` | `/gossip` | Recibir estado de un par |
| `POST` | `/claim` | Reclamar atómicamente una transacción huérfana |

#### POST /pay

```json
// Solicitud
{ "amount": 99.95, "currency": "USD" }

// Respuesta (202 Accepted)
{ "transactionId": "A1B2C3D4", "status": "processing", "node": "NodeA", "estimatedDelayMs": 7500 }
```

### Logs Esperados (Escenario de Recuperación)

```
10:00:01 [NodeA] 💰 Nuevo pago $99.95 USD. Transacción A1B2C3D4 creada.
10:00:01 [NodeA] 🔄 Broadcast A1B2C3D4 a pares. Iniciando procesamiento en segundo plano...
10:00:01 [NodeB] 📡 Gossip desde NodeA: nueva tx A1B2C3D4 (Processing, owner=NodeA)
10:00:01 [NodeC] 📡 Gossip desde NodeA: nueva tx A1B2C3D4 (Processing, owner=NodeA)

... (t=3s) Contenedor NodeA eliminado ...

10:00:03 [NodeB] ♡ Heartbeat PERDIDO de node-a (Connection refused)
10:00:05 [NodeB] ♡ Heartbeat PERDIDO de node-a (Connection refused)
10:00:07 [NodeB] ♡ Heartbeat PERDIDO de node-a (Connection refused)
10:00:07 [NodeB] ⚠ Par [node-a] parece muerto. Investigando transacción huérfana A1B2C3D4...
10:00:07 [NodeB] 🔑 Bloqueo concedido en A1B2C3D4 para [NodeB].
10:00:07 [NodeB] 🔄 Bloqueo adquirido en huérfana A1B2C3D4. Tomando control desde [node-a].
10:00:07 [NodeB] ✓ Transacción A1B2C3D4 recuperada y marcada COMPLETADA.
10:00:09 [NodeC] 📡 Gossip desde NodeB: A1B2C3D4 → Completed
```

### Bugs Corregidos Durante Pruebas

1. **Resolución de ID de nodo desde URLs de pares**: El servicio de recuperación extraía el hostname (`localhost`) de las URLs en lugar del ID lógico (`NodeA`). Corregido manteniendo un diccionario `PeerNodeIds` (URL → NodeId) poblado desde las respuestas de heartbeat.

2. **Regresión de estado en Gossip**: `NodeController.ReceiveGossip` usaba `>` para comparación de estados, permitiendo que objetos gossip `Completed` con owner desactualizado sobrescribieran un estado `Completed` local más reciente. Corregido cambiando a transiciones explícitas permitidas.

### Decisiones de Diseño Clave

| Decisión | Razón |
|----------|-------|
| **Sin broker de mensajes externo** | Cumple el requisito; gossip está embebido en la capa de aplicación |
| **Malla HTTP sobre gRPC** | Implementación más simple, más fácil de depurar, sin dependencia de protobuf |
| **ConcurrentDictionary.GetOrAdd para claims** | Provee semántica atómica "primero en escribir gana" sin locks |
| **Estado en memoria** | Adecuado para PoC; producción usaría un KVS distribuido (etcd, Consul) o base de datos |
| **Fusión optimista de estado** | Las transacciones solo avanzan en su máquina de estados, previniendo regresiones |
| **Procesamiento fire-and-forget** | Tarea en segundo plano ejecutada en el nodo que recibe la solicitud; los nodos no esperan entre sí |

### Limitaciones Conocidas

| Limitación | Impacto | Mitigación |
|------------|---------|------------|
| **Doble recuperación** | Ambos nodos sobrevivientes pueden recuperar la misma transacción huérfana | El bloqueo de claim es por nodo, no cross-nodo. Ambos terminan con estado=Completed (idempotente). Para recuperación exactly-once, usar Raft o etcd. |
| **Estado en memoria** | Estado perdido en reinicio completo del clúster | Agregar base de datos en producción |
| **Sin ledger persistente** | Sin historial de transacciones tras reinicio | Agregar event sourcing / write-ahead log |
| **Simulación monohost** | Todos los nodos corren en la misma máquina | La resiliencia real requiere pruebas de partición de red entre hosts |

### Consideraciones de Producción

- **Almacenamiento persistente**: Agregar base de datos (PostgreSQL, MSSQL) para sobrevivir reinicios completos
- **Consenso más fuerte**: Reemplazar el protocolo de claim simple con Raft (usando `dotnet/raft` o `RealisticConsensus`)
- **Streams gRPC**: Para gossip de menor latencia en escenarios de alto throughput
- **Idempotencia del lado del cliente**: Requerir que los clientes provean un header `Idempotency-Key` para garantizar procesamiento exactly-once
- **Health probes**: Conectar Docker HEALTHCHECK / Kubernetes liveness probes para orquestación de contenedores

### Licencia

MIT — Construido como prueba de concepto para resiliencia en sistemas distribuidos.

---

## English

A self-healing, peer-to-peer payment processing fabric built on .NET 8 with zero external dependencies. Nodes cooperate via gossip protocols and automatic failover — if a node dies mid-transaction, its neighbors detect the failure and complete the work.

### Architecture

```
                    ┌──────────────────┐
                    │    Client App    │
                    │  (curl / script) │
                    └────────┬─────────┘
                             │ POST /pay (Round-Robin)
                             ▼
              ┌─────────────────────────────┐
              │      HTTP Mesh / Gossip      │
              │  ♥ Heartbeat  │  📡 State   │
              │  every 2s     │  every 2s    │
              └─────────────────────────────┘
                    │        │        │
         ┌──────────┘  ┌─────┴──────┐  └──────────┐
         ▼             ▼            ▼             ▼
   ┌──────────┐  ┌──────────┐  ┌──────────┐
   │  Node A  │◄─┤  Node B  │──►│  Node C  │
   │ :5001    │──┤ :5002    │◄─┤ :5003    │
   └──────────┘  └──────────┘  └──────────┘
         │             │             │
         └─────────────┴─────────────┘
         Gossip / Heartbeat / Claim
```

### Communication Strategy

| Protocol | Mechanism | Interval |
|----------|-----------|----------|
| **Heartbeat** | `GET /health` → peers | Every 2s |
| **Gossip** | Full transaction state exchange via `POST /gossip` | Every 2s (+ immediate on new tx) |
| **Claim** | Distributed lock via `POST /claim` (compare-and-swap on peer) | On-demand during recovery |

### Failure Detection & Recovery Flow

```
1. Client → POST /pay → Node A
2. Node A creates TX-99, immediately gossips to B & C
3. Node A starts processing (simulated 5-10s delay)
4. 🔥 CHAOS: Node A is killed at t=3s
5. Node B misses 2 consecutive heartbeats from A (~6s)
6. Node B marks Node A as DEAD
7. Node B scans its transaction state → finds TX-99 (Processing, owner=NodeA) → ORPHAN
8. Node B sends POST /claim to Node C (the only surviving peer)
9. Node C atomically records: "TX-99 → claimed by Node B" → returns OK
10. Node B takes ownership, marks TX-99 → COMPLETED
11. Client sees TX-99 as Completed ✓
```

### Consistency Guarantees

- **Idempotency**: Each transaction has a unique 8-char hex `Id`. The `POST /claim` endpoint uses `ConcurrentDictionary.GetOrAdd` — the first claimant wins atomically.
- **No Double-Spending**: A transaction can only be claimed by one node. Peer validates ownership before acknowledging a claim.
- **State Merge**: During gossip, transactions only move forward in state (`Pending → Processing → Completed`). A `Completed` state overwrites any lesser state.

### Quick Start

#### Prerequisites

- Docker & Docker Compose

#### Run with Docker

```bash
docker compose up --build -d
```

This single command builds and starts all 3 nodes. Each node:
- Is assigned a unique `NODE_ID` (`NodeA`, `NodeB`, `NodeC`)
- Discovers peers via the `PEERS` environment variable
- Listens on port `5000` (mapped to `5001`, `5002`, `5003` on host)

#### Run Locally (No Docker)

```bash
# Prerequisites: .NET 8 SDK
dotnet build src/SolidarityGrid.Node -c Release

# Terminal 1 - NodeA
set NODE_ID=NodeA && set PEERS=http://localhost:5002,http://localhost:5003 && set ASPNETCORE_URLS=http://0.0.0.0:5001 && dotnet run --project src/SolidarityGrid.Node --no-build -c Release

# Terminal 2 - NodeB
set NODE_ID=NodeB && set PEERS=http://localhost:5001,http://localhost:5003 && set ASPNETCORE_URLS=http://0.0.0.0:5002 && dotnet run --project src/SolidarityGrid.Node --no-build -c Release

# Terminal 3 - NodeC
set NODE_ID=NodeC && set PEERS=http://localhost:5001,http://localhost:5002 && set ASPNETCORE_URLS=http://0.0.0.0:5003 && dotnet run --project src/SolidarityGrid.Node --no-build -c Release
```

> **Note**: On Linux/macOS use `export` instead of `set`.

#### Verify the Cluster

```bash
curl http://localhost:5001/health
curl http://localhost:5002/health
curl http://localhost:5003/health
```

Expected output:
```json
{"nodeId":"NodeA","alive":true,"transactionCount":0,"peerCount":2,"timestamp":"..."}
```

### Chaos Test (Simulated Failure)

> Watch SolidarityGrid heal itself in real-time.

#### Manual Walkthrough

**Terminal 1** — Watch logs:
```bash
docker compose logs -f
```

**Terminal 2** — Inject chaos:
```bash
# 1. Send a payment to any node
curl -X POST http://localhost:5002/pay \
  -H "Content-Type: application/json" \
  -d '{"amount": 99.95, "currency": "USD"}'

# 2. Before it finishes (within 5s), kill the processing node
docker stop solidaritygrid-node-a

# 3. Wait ~10s for recovery, then check status
curl http://localhost:5002/transactions
curl http://localhost:5003/transactions

# 4. Restart the dead node
docker start solidaritygrid-node-a
```

#### Automated Script

```bash
# PowerShell (Windows)
.\scripts\chaos-test.ps1

# Bash (Linux/macOS)
chmod +x scripts/chaos-test.sh && ./scripts/chaos-test.sh
```

### Project Structure

```
SolidarityGrid/
├── docker-compose.yml               # 3-node cluster orchestration
├── Dockerfile                        # .NET 8 container image
├── src/SolidarityGrid.Node/
│   ├── SolidarityGrid.Node.csproj
│   ├── Program.cs                    # Entry point, DI setup
│   ├── Models/
│   │   ├── Transaction.cs            # Transaction entity + state machine
│   │   ├── GossipPayload.cs          # Gossip exchange DTO
│   │   └── Dtos.cs                   # Request/response DTOs
│   ├── Services/
│   │   ├── NodeState.cs              # Singleton: identity, peers, in-memory store
│   │   ├── HeartbeatService.cs       # Background: pings peers every 2s
│   │   ├── GossipService.cs          # Background: state exchange every 2s
│   │   └── RecoveryService.cs        # Background: orphan detection + claim
│   └── Controllers/
│       ├── PaymentController.cs      # POST /pay, GET /transactions
│       └── NodeController.cs         # GET /health, POST /gossip, POST /claim
├── scripts/
│   ├── chaos-test.ps1                # Chaos test (PowerShell)
│   └── chaos-test.sh                 # Chaos test (Bash)
└── README.md
```

### API Reference

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/pay` | Submit a payment (async, returns immediately) |
| `GET` | `/transactions` | List all known transactions |
| `GET` | `/transactions/{id}` | Get a single transaction |
| `GET` | `/health` | Health check (used by heartbeat) |
| `POST` | `/gossip` | Receive state from a peer |
| `POST` | `/claim` | Atomically claim an orphaned transaction |

#### POST /pay

```json
// Request
{ "amount": 99.95, "currency": "USD" }

// Response (202 Accepted)
{ "transactionId": "A1B2C3D4", "status": "processing", "node": "NodeA", "estimatedDelayMs": 7500 }
```

### Expected Log Output (Recovery Scenario)

```
10:00:01 [NodeA] 💰 New payment $99.95 USD. Transaction A1B2C3D4 created.
10:00:01 [NodeA] 🔄 Broadcast A1B2C3D4 to peers. Starting background processing...
10:00:01 [NodeB] 📡 Gossip from NodeA: new tx A1B2C3D4 (Processing, owner=NodeA)
10:00:01 [NodeC] 📡 Gossip from NodeA: new tx A1B2C3D4 (Processing, owner=NodeA)

... (t=3s) NodeA container killed ...

10:00:03 [NodeB] ♡ Heartbeat MISS from node-a (Connection refused)
10:00:05 [NodeB] ♡ Heartbeat MISS from node-a (Connection refused)
10:00:07 [NodeB] ♡ Heartbeat MISS from node-a (Connection refused)
10:00:07 [NodeB] ⚠ Peer [node-a] appears dead. Investigating orphaned transaction A1B2C3D4...
10:00:07 [NodeB] 🔑 Lock granted on A1B2C3D4 for [NodeB].
10:00:07 [NodeB] 🔄 Acquired lock on orphaned A1B2C3D4. Taking over from [node-a].
10:00:07 [NodeB] ✓ Transaction A1B2C3D4 recovered and marked COMPLETED.
10:00:09 [NodeC] 📡 Gossip from NodeB: A1B2C3D4 → Completed
```

### Bugs Fixed During Testing

1. **Node ID resolution from peer URLs**: The recovery service was extracting the hostname (`localhost`) from peer URLs instead of the logical node ID (`NodeA`). Fixed by maintaining a `PeerNodeIds` dictionary (URL → NodeId) populated from heartbeat responses.

2. **Gossip state regression**: `NodeController.ReceiveGossip` used `>=` for state comparison, allowing stale `Completed` gossip objects (with outdated owner) to overwrite fresher local `Completed` state. Fixed by changing to explicit allowed transitions.

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **No external message broker** | Meets requirement; gossip is embedded in the application layer |
| **HTTP mesh over gRPC** | Simpler implementation, easier to debug, no protobuf dependency |
| **ConcurrentDictionary.GetOrAdd for claims** | Provides atomic "first-writer-wins" semantics without locks |
| **In-memory state** | Suitable for PoC; production would plug in a distributed KVS (etcd, Consul) or database |
| **Optimistic state merge** | Transactions only move forward in their state machine, preventing regressions |
| **Fire-and-forget processing** | Background task runs on the node that received the request; nodes don't await each other |

### Known Limitations

| Limitation | Impact | Mitigation |
|------------|--------|------------|
| **Double recovery** | Both surviving nodes may recover the same orphaned transaction | The claim lock is per-node, not cross-node. Both end with state=Completed (idempotent). For exactly-once recovery, use Raft or etcd. |
| **In-memory state** | State lost on full cluster restart | Add a database in production |
| **No persistent ledger** | No transaction history after restart | Add event sourcing / write-ahead log |
| **Single-host simulation** | All nodes run on the same machine | True resilience requires network-partition testing across hosts |

### Production Considerations

- **Persistent storage**: Add a database (PostgreSQL, MSSQL) to survive full cluster restarts
- **Stronger consensus**: Replace the simple claim protocol with Raft (using e.g. `dotnet/raft` or `RealisticConsensus`)
- **gRPC streams**: For lower-latency gossip in high-throughput scenarios
- **Client-side idempotency**: Require clients to provide an `Idempotency-Key` header to guarantee exactly-once processing
- **Health probes**: Wire up Docker HEALTHCHECK / Kubernetes liveness probes for container orchestration

### License

MIT — Built as a proof-of-concept for distributed systems resilience.
