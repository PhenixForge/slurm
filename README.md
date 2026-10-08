# Slurm Discovery

# Jour 1 : Prise en main et cluster local

Ce dépôt contient la configuration et les commandes de base pour déployer un mini-cluster Slurm local avec Podman/Docker et manipuler la file d'attente.

## 🚀 Démarrage du cluster
### version Docker
```bash
# Install Docker compose
sudo dnf install -y docker-compose

# Eviter les access denied
sudo usermod -aG docker $USER

# Appliquer la modification
newgrp docker

# Lancer le cluster en arrière-plan
docker-compose up -d
```

Output :
```

```
[+] up 16/16
 ✔ Image mariadb:10.11 Pulled                                                                                                                                                                                                                                                                                                                                                                  4.5s
 ✔ Container c2        Started                                                                                                                                                                                                                                                                                                                                                                 0.7s
 ✔ Container mysql     Started                                                                                                                                                                                                                                                                                                                                                                 0.5s
 ✔ Container c1        Started                                                                                                                                                                                                                                                                                                                                                                 0.8s
 ✔ Container slurmdbd  Started                                                                                                                                                                                                                                                                                                                                                                 0.2s
 ✔ Container slurmctld Started  

# Vérifier l'état des nœuds Slurm
docker ps
```

Output
```bash
docker ps
CONTAINER ID   IMAGE                                    COMMAND                  CREATED          STATUS          PORTS                                                             NAMES
4dc9890de9ad   giovtorres/slurm-docker-cluster:latest   "/usr/local/bin/dock…"   18 seconds ago   Up 18 seconds                                                                     slurmdbd
c9c947c261d8   giovtorres/slurm-docker-cluster:latest   "/usr/local/bin/dock…"   19 seconds ago   Up 17 seconds                                                                     c1
2dc3030d51a1   giovtorres/slurm-docker-cluster:latest   "/usr/local/bin/dock…"   19 seconds ago   Up 17 seconds                                                                     c2
454f197f89d2   mariadb:10.11                            "docker-entrypoint.s…"   19 seconds ago   Up 18 seconds   3306/tcp                                                          mysql
2bd22d1b3dee   giovtorres/slurm-docker-cluster:latest   "/usr/local/bin/dock…"   10 minutes ago   Up 18 seconds   0.0.0.0:6817-6818->6817-6818/tcp, [::]:6817-6818->6817-6818/tcp   slurmctld
```

```bash
# Lancer le cluster en arrière-plan
podman-compose up -d

# Vérifier l'état des nœuds Slurm
podman exec -it slurmctld sinfo

```

## 📜 Les 4 commandes indispensables

Commande  : Rôles 

`batch <script>` : Soumettre un travail en arrière-plans

`queue` : Afficher les travaux dans la file d'attentes

`acct` : Consulter l'historique et le statut des travaux

`scancel <ID>` : Annuler un travail en cours ou en attente

## 🧪 Exercice : Lancer la charge de travail

Rendre le script exécutable :

`chmod +x scripts/test_job.sh`

Soumettre 20 travaux simultanément :

`podman exec -it slurmctld bash -c "cd /scripts && for i in {1..20}; do sbatch test_job.sh; done"`

Observer la file d'attente se remplir et se vider :

`podman exec -it slurmctld squeue`

Consulter l'historique des exécutions :

`podman exec -it slurmctld sacct --format=JobID,JobName,State,NodeList`

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