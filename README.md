# Slurm Discovery - Jour 1 : Prise en main et cluster local

Ce dépôt contient la configuration et les commandes de base pour déployer un mini-cluster Slurm local avec Podman/Docker et manipuler la file d'attente.

## 🚀 Démarrage du cluster

```bash
# Lancer le cluster en arrière-plan
podman-compose up -d

# Vérifier l'état des nœuds Slurm
podman exec -it slurmctld sinfo
```

📜 Les 4 commandes indispensables

Commande  : Rôles 

`batch <script>` : Soumettre un travail en arrière-plans

`queue` : Afficher les travaux dans la file d'attentes

`acct` : Consulter l'historique et le statut des travaux

`scancel <ID>` : Annuler un travail en cours ou en attente


🧪 Exercice : Lancer la charge de travail

Rendre le script exécutable :

`chmod +x scripts/test_job.sh`

Soumettre 20 travaux simultanément :

`podman exec -it slurmctld bash -c "cd /scripts && for i in {1..20}; do sbatch test_job.sh; done"`

Observer la file d'attente se remplir et se vider :

`podman exec -it slurmctld squeue`

Consulter l'historique des exécutions :

`podman exec -it slurmctld sacct --format=JobID,JobName,State,NodeList`

---

As-tu réussi à lancer le conteneur et à voir les 20 travaux s'empiler dans `squeue` ?