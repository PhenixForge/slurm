# Slurm Discovery

# Jour 1 : Prise en main et cluster local

Ce dépôt contient la configuration et les commandes de base pour déployer un mini-cluster Slurm local avec docker/Docker et manipuler la file d'attente.

## Architecture du Cluster

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     Docker Network: slurm_default                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │              Shared Infrastructure (Named Volumes)                  │   │
│  ├──────────────┬──────────────┬──────────────┬──────────────────────┤   │
│  │  MySQL       │  🔐 MUNGE    │  ⚙️ CONFIG   │  📝 LOGS             │   │
│  │  MariaDB     │  Crypto Keys │  JWT Keys    │  /var/log/slurm      │   │
│  │  Port 3306   │  Shared Auth │  slurm.conf  │  Audit Trail         │   │
│  └──────────────┴──────────────┴──────────────┴──────────────────────┘   │
│                                                                               │
│  ┌───────────────────────────────┐    ┌────────────────────────────────┐  │
│  │      slurmdbd                 │    │      slurmctld                 │  │
│  │  Database Daemon              │◄───┤  Controller Daemon             │  │
│  │  • Accounting                 │    │  • Job Scheduling              │  │
│  │  • Port 6819                  │    │  • Ports 6817-6818             │  │
│  │  ✓ MUNGE auth                 │    │  ✓ MUNGE auth + Privileged    │  │
│  └───────────────────────────────┘    └────────────────────┬───────────┘  │
│                 ▲                                           │               │
│                 │                                           ▼               │
│                 │                    ┌──────────────────────────────────┐ │
│                 │                    │    📂 Scripts Volume             │ │
│                 │                    │    ./scripts/test_job.sh          │ │
│                 │                    │    Job submissions                │ │
│                 │                    └──────────────────────────────────┘ │
│                 │                                           │               │
│  ┌──────────────┴──────────────┐              ┌────────────┴───────────┐ │
│  │                             │              │                        │ │
│  │    ┌─────────────────┐      │              │  ┌─────────────────┐  │ │
│  │    │  c1 (Worker)    │      │              │  │  c2 (Worker)    │  │ │
│  │    │  slurmd Daemon  │      │              │  │  slurmd Daemon  │  │ │
│  │    │  14 CPUs        │      │              │  │  14 CPUs        │  │ │
│  │    │  1 GPU          │      │              │  │  1 GPU          │  │ │
│  │    │  Dynamic Reg.   │      │              │  │  Dynamic Reg.   │  │ │
│  │    │  ✓ MUNGE + cgrs │      │              │  │  ✓ MUNGE + cgrs │  │ │
│  │    └─────────────────┘      │              │  └─────────────────┘  │ │
│  │                             │              │                        │ │
│  └─────────────────────────────┘              └────────────────────────┘ │
│                                                                               │
└─────────────────────────────────────────────────────────────────────────────┘

Legend:
  ◄─►  = Data flows (queries, auth, config, scheduling)
  ✓    = Security/features enabled
  cgrs = cgroups for job resource isolation
```

## MUNGE

Munge sert à créer et valider des credentials pour Slurm. Il confirme s'ils sont valide pour d'autres hôtes qui partagent la même configuration utilisateurs (et groupes). Tous les membres du cluster doivent partager la même clé cryptographique.

## 🚀 Démarrage du cluster
### Docker
```bash
# Install Docker compose
sudo dnf install -y docker-compose

# Eviter les access denied
sudo usermod -aG docker $USER

# Appliquer la modification
newgrp docker

# Lancer le cluster en arrière-plan
docker-compose up -d

# Vérifier l'état des nœuds Slurm
docker ps
```

Output
```bash
docker ps
CONTAINER ID   IMAGE                                    COMMAND                  CREATED         STATUS         PORTS                                                             NAMES
3a532cc154d8   giovtorres/slurm-docker-cluster:latest   "/bin/bash -c 'set -…"   4 seconds ago   Up 3 seconds                                                                     c1
d113018feacd   giovtorres/slurm-docker-cluster:latest   "/bin/bash -c 'set -…"   4 seconds ago   Up 3 seconds                                                                     c2
775b1eb41c47   giovtorres/slurm-docker-cluster:latest   "/usr/local/bin/dock…"   4 seconds ago   Up 3 seconds   0.0.0.0:6817-6818->6817-6818/tcp, [::]:6817-6818->6817-6818/tcp   slurmctld
d387cc7f4cc8   giovtorres/slurm-docker-cluster:latest   "/usr/local/bin/dock…"   4 seconds ago   Up 3 seconds                                                                     slurmdbd
83d47fa7b5b4   mariadb:10.11                            "docker-entrypoint.s…"   4 seconds ago   Up 3 seconds   3306/tcp                                                          mysql
```

## 📜 Les 4 commandes indispensables

- `sbatch <script>` : Soumettre un travail en arrière-plans
- `squeue` : Afficher les travaux dans la file d'attentes
- `sacct` : Consulter l'historique et le statut des travaux
- `scancel <ID>` : Annuler un travail en cours ou en attente


## 🧪 Exercice : Lancer la charge de travail

- Rendre le script exécutable :

`chmod +x scripts/test_job.sh`

- Soumettre 20 travaux simultanément :

`docker exec -it slurmctld bash -c "cd /scripts && for i in {1..20}; do sbatch test_job.sh; done"`

- Observer la file d'attente se remplir et se vider :

`docker exec -it slurmctld squeue`

- Consulter l'historique des exécutions :

`docker exec -it slurmctld sacct --format=JobID,JobName,State,NodeList`

---

## Résultats du lab

Résumé du travail accompli:

✅ 6 bugs identifiés et corrigés dans docker-compose.yml:

- Issue 1: Rôles incorrects + auth MySQL
- Issue 2: Volumes partagés manquants (/etc/slurm, /etc/munge)
- Issue 3: SELinux bloquant les volumes (besoin du flag :z)
- Issue 4: Permissions cgroup insuffisantes
- Issue 5: Socket munge stale après docker compose down
- Issue 6: Logique de détection de replica cassée dans l'entrypoint vendor

✅ Documentation complète via TROUBLESHOOTING.md:

- Tableau récapitulatif des 6 issues
- Explications détaillées (symptôme → diagnostic → fix)
- Commandes de diagnostic clés
- Configutation finale de docker-compose.yml

✅ Cluster Slurm 100% fonctionnel:

- Tous les services up et healthy
- Nœuds workers (c1, c2) enregistrés et prêts
- Jobs soumis et distribués correctement
- Tracking d'exécution via sacct fonctionnel