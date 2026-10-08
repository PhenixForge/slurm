# Slurm Discovery - Jour 1 : Prise en main et cluster local

Ce dépôt contient la configuration et les commandes de base pour déployer un mini-cluster Slurm local avec Podman/Docker et manipuler la file d'attente.

## 🚀 Démarrage du cluster

```bash
# Lancer le cluster en arrière-plan
podman-compose up -d

# Vérifier l'état des nœuds Slurm
podman exec -it slurmctld sinfo