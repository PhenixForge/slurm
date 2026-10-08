```bash
docker ps
CONTAINER ID   IMAGE                                    COMMAND                  CREATED          STATUS          PORTS                                                             NAMES
36942791acfd   giovtorres/slurm-docker-cluster:latest   "/bin/bash -c 'set -…"   16 seconds ago   Up 15 seconds                                                                     c1
39adbce4a2c4   giovtorres/slurm-docker-cluster:latest   "/bin/bash -c 'set -…"   16 seconds ago   Up 15 seconds                                                                     c2
acc1bc2eb7d7   giovtorres/slurm-docker-cluster:latest   "/usr/local/bin/dock…"   16 seconds ago   Up 15 seconds   0.0.0.0:6817-6818->6817-6818/tcp, [::]:6817-6818->6817-6818/tcp   slurmctld
5eefeb79144e   giovtorres/slurm-docker-cluster:latest   "/usr/local/bin/dock…"   16 seconds ago   Up 15 seconds                                                                     slurmdbd
f9c49b301a55   mariadb:10.11                            "docker-entrypoint.s…"   16 seconds ago   Up 15 seconds   3306/tcp                                                          mysql
```

```bash
docker exec -it slurmctld sinfo
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
cpu*         up   infinite      2   idle c[1-2]
gpu          up   infinite      0    n/a 
```

```bash
docker exec -it slurmctld bash -c "cd /scripts && for i in {1..20}; do sbatch test_job.sh; done"
Submitted batch job 1
Submitted batch job 2
Submitted batch job 3
Submitted batch job 4
Submitted batch job 5
Submitted batch job 6
Submitted batch job 7
Submitted batch job 8
Submitted batch job 9
Submitted batch job 10
Submitted batch job 11
Submitted batch job 12
Submitted batch job 13
Submitted batch job 14
Submitted batch job 15
Submitted batch job 16
Submitted batch job 17
Submitted batch job 18
Submitted batch job 19
Submitted batch job 20
revan@fedora:~/git/slurm$ docker exec -it slurmctld squeue
             JOBID PARTITION     NAME     USER ST       TIME  NODES NODELIST(REASON)
                19       cpu test_slu     root PD       0:00      1 (Priority)
                20       cpu test_slu     root PD       0:00      1 (Priority)
                17       cpu test_slu     root PD       0:00      1 (Priority)
                18       cpu test_slu     root PD       0:00      1 (Priority)
                15       cpu test_slu     root PD       0:00      1 (Priority)
                16       cpu test_slu     root PD       0:00      1 (Priority)
                13       cpu test_slu     root PD       0:00      1 (Priority)
                14       cpu test_slu     root PD       0:00      1 (Priority)
                11       cpu test_slu     root PD       0:00      1 (Priority)
                12       cpu test_slu     root PD       0:00      1 (Priority)
                 9       cpu test_slu     root PD       0:00      1 (Resources)
                10       cpu test_slu     root PD       0:00      1 (Priority)
                 8       cpu test_slu     root  R       0:00      1 c2
                 7       cpu test_slu     root  R       0:01      1 c1
```

```bash
docker exec -it slurmctld sacct --format=JobID,JobName,State,NodeList,Elapsed
JobID           JobName      State        NodeList    Elapsed 
------------ ---------- ---------- --------------- ---------- 
1            test_slurm  COMPLETED              c1   00:00:31 
1.batch           batch  COMPLETED              c1   00:00:31 
2            test_slurm  COMPLETED              c2   00:00:30 
2.batch           batch  COMPLETED              c2   00:00:30 
3            test_slurm  COMPLETED              c1   00:00:30 
3.batch           batch  COMPLETED              c1   00:00:30 
4            test_slurm  COMPLETED              c2   00:00:30 
4.batch           batch  COMPLETED              c2   00:00:30 
5            test_slurm  COMPLETED              c1   00:00:30 
5.batch           batch  COMPLETED              c1   00:00:30 
6            test_slurm  COMPLETED              c2   00:00:30 
6.batch           batch  COMPLETED              c2   00:00:30 
7            test_slurm    RUNNING              c1   00:00:12 
7.batch           batch    RUNNING              c1   00:00:12 
8            test_slurm    RUNNING              c2   00:00:11 
8.batch           batch    RUNNING              c2   00:00:11 
9            test_slurm    PENDING   None assigned   00:00:00 
10           test_slurm    PENDING   None assigned   00:00:00 
11           test_slurm    PENDING   None assigned   00:00:00 
12           test_slurm    PENDING   None assigned   00:00:00 
13           test_slurm    PENDING   None assigned   00:00:00 
14           test_slurm    PENDING   None assigned   00:00:00 
15           test_slurm    PENDING   None assigned   00:00:00 
16           test_slurm    PENDING   None assigned   00:00:00 
17           test_slurm    PENDING   None assigned   00:00:00 
18           test_slurm    PENDING   None assigned   00:00:00 
19           test_slurm    PENDING   None assigned   00:00:00 
20           test_slurm    PENDING   None assigned   00:00:00
```
Eteignons tout proprement :

```bash
docker compose down -v
[+] down 9/9
 ✔ Container c2               Removed                                                                                                                                                                                                                                                                                                                                                          0.1s
 ✔ Container c1               Removed                                                                                                                                                                                                                                                                                                                                                          0.1s
 ✔ Container slurmctld        Removed                                                                                                                                                                                                                                                                                                                                                          0.2s
 ✔ Container slurmdbd         Removed                                                                                                                                                                                                                                                                                                                                                          0.1s
 ✔ Container mysql            Removed                                                                                                                                                                                                                                                                                                                                                          0.2s
 ✔ Volume slurm_var_log_slurm Removed                                                                                                                                                                                                                                                                                                                                                          0.0s
 ✔ Volume slurm_etc_slurm     Removed                                                                                                                                                                                                                                                                                                                                                          0.0s
 ✔ Volume slurm_etc_munge     Removed                                                                                                                                                                                                                                                                                                                                                          0.0s
 ✔ Network slurm_default      Removed
 ```