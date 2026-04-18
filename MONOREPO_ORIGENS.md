# Origens Do Monorepo

Este workspace foi consolidado para um unico repositorio Git no root `C:\Work\jarvis_project`.

## Repositorios anteriores

- `jarvis_backend`
  - remote antigo: `https://github.com/rafaeldfdsf/aura_agent.git`
  - HEAD no momento da migracao: `8df661f96dcaf1422562efbc9dcd159ec4c08ef6`
- `jarvis_agent_windows`
  - remote antigo: `https://github.com/rafaeldfdsf/jarvis_agent_windows.git`
  - HEAD no momento da migracao: `27beaee77b8b7b35fc13f87e4ecd22043587f621`
- `jarvis_flutter`
  - remote antigo: `https://github.com/rafaeldfdsf/jarvis_flutter.git`
  - HEAD no momento da migracao: `0b6b35ce726f8085a7503a7fc354f949a3d773b8`

## Backups locais

Antes de remover os `.git` internos, foi criado um backup local com bundles em:

- `.repo_migration_backup/jarvis_backend.bundle`
- `.repo_migration_backup/jarvis_agent_windows.bundle`
- `.repo_migration_backup/jarvis_flutter.bundle`

Esses ficheiros nao entram no novo monorepo porque estao ignorados no `.gitignore`, mas preservam o historico dos repos antigos.
