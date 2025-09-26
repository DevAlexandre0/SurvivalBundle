# Survival Bundle

Headless survival mechanics for FiveM supporting Qbox, QBCore, ESX, ox_core and standalone adapters.

## Resources

| Resource | Responsibility | Persistence | Notes |
| --- | --- | --- | --- |
| `survival_hub` | Aggregates namespace state, clamps values, persists snapshots | oxmysql / file fallback | Provides framework adapter factory (`survival_shared`). |
| `survival_bio` | Infection, parasites, immunity | oxmysql | Uses upstream state (`needs`, `health`, `env`). |
| `survival_env` | Weather/body temperature/radiation | oxmysql | Clamps payloads and rate-limits events. |
| `survival_health` | HP, blood, bleed tiers, fractures | state bags only | Server-authoritative; medical exports gated by adapter permissions. |
| `survival_movement` | Stamina/O₂ authority | oxmysql | Rate-limited, saves debounced. |
| `survival_needs` | Food/water/energy/stress/bowel | oxmysql / in-memory fallback | Persists per player identifier. |
| `survival_shared` | Framework adapter utilities | n/a | Autodetects qbox/qb-core/es_extended/ox_core/standalone. |

## Installation

1. Install and start [`oxmysql`](https://github.com/overextended/oxmysql) if persistence is enabled.
2. Copy all resources to your server resources directory and ensure they load **after** the target framework.
3. Add to `server.cfg`:
   ```cfg
   ensure survival_shared
   ensure survival_hub
   ensure survival_env
   ensure survival_health
   ensure survival_movement
   ensure survival_bio
   ensure survival_needs
   ```
4. (Optional) Configure ACE permissions for medical/staff actions:
   ```cfg
   add_ace group.admin survival.* allow
   add_ace group.ems survival.bio allow
   add_ace group.ems survival.health allow
   ```
5. Import SQL schemas when using MySQL:
   ```bash
   mysql -u USER -p DB < survival_movement/sql.sql
   mysql -u USER -p DB < survival_needs/schema.sql
   ```
   Other tables are created automatically on first run.

## Configuration Matrix

Each resource exposes a `config.lua`. Key shared knobs:

| Setting | Description |
| --- | --- |
| `Config.Framework.priority` | Adapter selection order (`qbox`, `qb`, `ox`, `esx`, `standalone`). |
| `Config.Framework.permissions` | Capability → list of `job:` / `ace:` / custom functions controlling privileged actions. |
| `Config.Debug` | Verbose logging toggle. |
| `Config.Persistence` | Persistence provider options (table name, flush interval, fallback prefix). |

Refer to individual configs for additional module-specific coefficients.

## Development

* Lint with [`luacheck`](https://github.com/mpeterv/luacheck): `luacheck survival_* survival_shared tests`.
* Minimal tests use Lua 5.4: `lua5.4 tests/adapter_spec.lua`.
* CI workflow (`.github/workflows/ci.yml`) runs lint and tests on push/PR.

## Troubleshooting

| Symptom | Likely Cause | Fix |
| --- | --- | --- |
| State bags empty on connect | Framework adapter not matching | Adjust `Config.Framework.priority` or ensure framework resource is started. |
| Persistence not saving | `oxmysql` missing/stopped | Install/start oxmysql or disable persistence (`Config.Persistence.enabled = false`). |
| Medical exports denied | Missing ACE/job permissions | Grant ACE (`survival.health`, `survival.bio`) or add job name to config. |

## License

MIT License. See `LICENSE` if provided.
