# Slurm Discovery

## Architecture du Cluster

```
┌────────────────────────────────────────────────────────────────────────────┐
│                     Docker Network: slurm_default                          │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │              Shared Infrastructure (Named Volumes)                  │   │
│  ├──────────────┬──────────────┬──────────────┬────────────────────────┤   │
│  │  MySQL       │  🔐 MUNGE    │  ⚙️ CONFIG   │  📝 LOGS               │   │
│  │  MariaDB     │  Crypto Keys │  JWT Keys    │  /var/log/slurm        │   │
│  │  Port 3306   │  Shared Auth │  slurm.conf  │  Audit Trail           │   │
│  └──────────────┴──────────────┴──────────────┴────────────────────────┘   │
│                                                                            │
│  ┌───────────────────────────────┐    ┌────────────────────────────────┐   │
│  │      slurmdbd                 │    │      slurmctld                 │   │
│  │  Database Daemon              │◄───┤  Controller Daemon             │   │
│  │  • Accounting                 │    │  • Job Scheduling              │   │
│  │  • Port 6819                  │    │  • Ports 6817-6818             │   │
│  │  ✓ MUNGE auth                 │    │  ✓ MUNGE auth + Privileged     │   │
│  └───────────────────────────────┘    └────────────────────┬───────────┘   │
│                 ▲                                          │               │
│                 │                                          ▼               │
│                 │                    ┌──────────────────────────────────┐  │
│                 │                    │      📂 Scripts Volume           │  │
│                 │                    │      ./scripts/test_job.sh       │  │
│                 │                    │      Job submissions             │  │
│                 │                    └──────────────────────────────────┘  │
│                 │                                           │              │
│  ┌──────────────┴──────────────┐              ┌────────────┴───────────┐   │
│  │                             │              │                        │   │
│  │    ┌─────────────────┐      │              │  ┌─────────────────┐   │   │
│  │    │  c1 (Worker)    │      │              │  │  c2 (Worker)    │   │   │
│  │    │  slurmd Daemon  │      │              │  │  slurmd Daemon  │   │   │
│  │    │  14 CPUs        │      │              │  │  14 CPUs        │   │   │
│  │    │  1 GPU          │      │              │  │  1 GPU          │   │   │
│  │    │  Dynamic Reg.   │      │              │  │  Dynamic Reg.   │   │   │
│  │    │  ✓ MUNGE + cgrs │      │              │  │ ✓ MUNGE + cgrs  │   │   │
│  │    └─────────────────┘      │              │  └─────────────────┘   │   │
│  │                             │              │                        │   │
│  └─────────────────────────────┘              └────────────────────────┘   │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘

Legend:
  ◄─►  = Data flows (queries, auth, config, scheduling)
  ✓    = Security/features enabled
  cgrs = cgroups for job resource isolation
```

## MUNGE

Munge sert à créer et valider des credentials pour Slurm. Il confirme s'ils sont valide pour d'autres hôtes qui partagent la même configuration utilisateurs (et groupes). Tous les membres du cluster doivent partager la même clé cryptographique.

