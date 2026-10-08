# Troubleshooting log: getting the Slurm Docker cluster running

This document summarizes every issue hit while bringing up this `docker-compose.yml`
based on `giovtorres/slurm-docker-cluster:latest`, the root cause of each, the fix,
and the commands used to diagnose and verify. Keep this around — most of these
bugs resurface any time the compose file or volumes are touched.

## Summary of issues (in the order they were found)

| # | Symptom | Root cause | Fix |
|---|---------|-----------|-----|
| 1 | `slurmctld` logs show it starting `slurmdbd`; MySQL `Access denied for user '-p'@...` | No `command:` set on any service → all containers fall back to the image's default `CMD ["slurmdbd"]`; `slurmdbd`'s `MYSQL_USER`/`MYSQL_PASSWORD` were unset → `mysql -u -p` mis-parsed | Add explicit `command:` per service role; pass `MYSQL_USER`/`MYSQL_PASSWORD` to `slurmdbd` |
| 2 | `slurmctld` crashes: `fatal: auth/jwt: cannot stat '/etc/slurm/jwt_hs256.key'` | `/etc/slurm`, `/etc/munge`, `/var/log/slurm` were not shared between containers, so the JWT key `slurmdbd` generates is invisible to `slurmctld` | Add named volumes `etc_munge`, `etc_slurm`, `var_log_slurm` mounted into every Slurm container |
| 3 | `ls: cannot open directory '/scripts/': Permission denied` even though the mount exists | SELinux (`seclabel` in `mount` output) blocks container access to bind/volume mounts without a relabel | Add `:z` to every volume/bind mount (`./scripts:/scripts:z`, etc.) |
| 4 | `c1`/`c2` exit silently right after `-- slurmctld is now active ...`, no error printed to `docker compose logs` | `slurmd -Z` needs to create cgroups under `/sys/fs/cgroup`, which is read-only without extra privileges | Add `privileged: true` to `slurmctld`, `c1`, `c2` |
| 5 | After `docker compose down` + `up`, munge fails again: `munged: Error: Found pid N bound to socket "/var/run/munge/munge.socket.2"` | `docker compose down` (without `-v`) keeps named volumes; a stale munge socket file survives in the volume across container recreations | `docker compose down -v` (or `docker volume rm slurm_etc_munge slurm_etc_slurm slurm_var_log_slurm`) before `up` |
| 6 | `c1`/`c2` still exit (code 1) right after `-- slurmctld is now active ...` even with `privileged: true` and shared volumes in place, with zero error output | The vendor `docker-entrypoint.sh` has `set -e` at the top and calls `REPLICA=$(detect_replica_number "cpu-worker")`. That function expects Compose's scaled-replica DNS names (`<project>-cpu-worker-N`); since our services are named `c1`/`c2` directly, detection always falls through to its fallback path, which does `return 1`. Under `set -e`, that failing assignment kills the whole entrypoint script immediately — before the `echo`/`slurmd` lines ever run — with no error message | Bypass the vendor's `slurmd-cpu` branch entirely: override `entrypoint`/`command` on `c1`/`c2` to run munged + the slurmctld-wait loop + `exec slurmd -Z` directly, skipping `detect_replica_number` altogether |

A secondary, **cosmetic** quirk was also identified in the vendor script (see
[Known quirk](#known-quirk-c1c2-may-register-as-cc1cc2) below) — it's made moot by the
Issue 6 fix, since that fix never calls the buggy renaming logic in the first place.

## Issue 1 — Wrong role + MySQL auth failure

**Symptom:**
```
slurmctld  | ---> Starting the Slurm Database Daemon (slurmdbd) ...
slurmctld  | ERROR 2002 (HY000): Can't connect to MySQL server on 'mysql' (115)
slurmctld  | ERROR 1045 (28000): Access denied for user '-p'@'172.18.0.4' (using password: NO)
```

**Diagnosis:** Read the image's `Dockerfile` (`CMD ["slurmdbd"]`) and `docker-entrypoint.sh`
on GitHub. The entrypoint picks a role by checking `"$1"`; with no `command:` in compose,
every container runs the default `slurmdbd` branch. That branch does:
```bash
until echo "SELECT 1" | mysql -h mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} ...
```
With `MYSQL_USER`/`MYSQL_PASSWORD` unset, this becomes `mysql -h mysql -u -p`, and MySQL's
CLI parses the bare `-p` as the *value* of `-u`, producing the exact `user '-p'` error seen.

**Fix:** in `docker-compose.yml`, give each service its real role and pass DB creds to `slurmdbd`:
```yaml
slurmdbd:
  command: ["slurmdbd"]
  environment:
    - MYSQL_USER=slurm
    - MYSQL_PASSWORD=password

slurmctld:
  command: ["slurmctld"]

c1:
  command: ["slurmd-cpu"]

c2:
  command: ["slurmd-cpu"]
```

## Issue 2 — Missing shared `/etc/slurm`, `/etc/munge`, `/var/log/slurm`

**Symptom:**
```
slurmctld  | [...] fatal: auth/jwt: cannot stat '/etc/slurm/jwt_hs256.key': No such file or directory
```

**Diagnosis:** `slurmdbd`'s entrypoint branch creates `/etc/slurm/jwt_hs256.key` on first run.
Without a shared volume, that file only exists inside the `slurmdbd` container's own
writable layer — `slurmctld` (a separate container) never sees it.

**Fix:** declare named volumes and mount them in every Slurm service:
```yaml
volumes:
  etc_munge:
  etc_slurm:
  var_log_slurm:

services:
  slurmdbd:
    volumes:
      - etc_munge:/etc/munge
      - etc_slurm:/etc/slurm
      - var_log_slurm:/var/log/slurm
  # ...same three lines added to slurmctld, c1, c2
```

## Issue 3 — SELinux blocking volume access

**Symptom:**
```
ls: cannot open directory '/scripts/': Permission denied
ls: cannot access '/scripts/test_job.sh': Permission denied
```
even though `docker exec -it slurmctld mount | grep scripts` showed the mount present
(with `seclabel` visible in the mount options — the tell that SELinux is active and enforcing).

**Fix:** append `:z` to every volume and bind mount so Docker relabels it for container access:
```yaml
volumes:
  - ./scripts:/scripts:z
  - etc_munge:/etc/munge:z
  - etc_slurm:/etc/slurm:z
  - var_log_slurm:/var/log/slurm:z
```

## Issue 4 — cgroup permissions for `slurmd`

**Symptom:** `c1`/`c2` logs stop cleanly right after `-- slurmctld is now active ...`,
no error, container simply exits. Confirmed by running the image manually:
```bash
docker run -it --rm \
  --network slurm_default \
  -v slurm_etc_munge:/etc/munge:z \
  -v slurm_etc_slurm:/etc/slurm:z \
  -v slurm_var_log_slurm:/var/log/slurm:z \
  giovtorres/slurm-docker-cluster:latest \
  bash
# inside the container:
/usr/sbin/slurmd -Z -Dvvv
```
which surfaced the real error:
```
error: common_cgroup_instantiate: unable to create cgroup '/sys/fs/cgroup/system' : Read-only file system
error: Unable to initialize cgroup plugin
error: slurmd initialization failed
```

**Fix:** `slurmd` needs to manage cgroups for job resource isolation, which requires
elevated container privileges:
```yaml
slurmctld:
  privileged: true
c1:
  privileged: true
c2:
  privileged: true
```

## Issue 5 — Stale munge socket surviving `docker compose down`

**Symptom:** After fixing issues 1–4, restarting still failed:
```
munged: Error: Found pid 13 bound to socket "/var/run/munge/munge.socket.2"
```

**Diagnosis:** `docker compose down` removes containers but **keeps named volumes** by
default. The munge runtime socket file persisted in the `etc_munge`/shared state across
recreations and conflicted with the new munge daemon trying to bind the same path.

**Fix:** force a clean slate:
```bash
docker compose down -v        # -v also removes named volumes
# or, more surgically:
docker volume rm slurm_etc_munge slurm_etc_slurm slurm_var_log_slurm
```
If containers/volumes are in a truly broken state, the nuclear option that was used here:
```bash
docker ps -a                  # confirm nothing is lingering
docker container prune -f
docker volume prune -f
docker system prune -f
ps aux | grep munge           # make sure no stray munged on the HOST
sudo pkill -9 munged
docker compose up -d
```

## Issue 6 — `set -e` + buggy replica detection silently kills c1/c2

**Symptom:** even after fixing issues 1–5 (explicit `command: ["slurmd-cpu"]`, shared
volumes, `:z` flags, `privileged: true`), `c1`/`c2` still exited with code 1 right after:
```
c1  | -- slurmctld is now active ...
```
No error message at all, container just gone from `docker ps`.

**Diagnosis:** ran the image manually bypassing the vendor entrypoint entirely with
`--entrypoint /bin/bash` (see [the gotcha](#key-diagnostic-commands-reference) above),
replicating each step of the `slurmd-cpu` branch by hand but using `REPLICA=$(hostname)`
instead of the vendor's helper. That manual version **worked perfectly** — `slurmd`
started, detected CPUs/GPU, and registered with `slurmctld`
(`_handle_node_reg_resp: slurmctld sent back 8 TRES`), then sat processing
`REQUEST_PING` RPCs in the foreground (correct behavior for `-Dvvv`, not a hang).

Comparing that working manual run to the real entrypoint revealed the actual bug:
`docker-entrypoint.sh` starts with `set -e`, and the `slurmd-cpu` branch does
```bash
REPLICA=$(detect_replica_number "cpu-worker")
```
`detect_replica_number()` looks for Docker Compose's scaled-replica DNS names
(`${COMPOSE_PROJECT_NAME}-cpu-worker-N`). Since this repo's worker services are named
`c1`/`c2` directly (not a scaled `cpu-worker` service), no such name ever resolves, so
the function always falls through to its fallback branch, which does `return 1`. Under
`set -e`, a failing command substitution assigned to a variable (`REPLICA=$(...)`)
aborts the entire script right there — silently, with exit code 1 — before any of the
following `echo`/`slurmd` lines ever execute. That's the exact symptom observed.

**Fix:** stop relying on the vendor's `slurmd-cpu` role switch for `c1`/`c2`. Override
the container's `entrypoint`/`command` to run the same steps directly, skipping the
buggy `detect_replica_number` call entirely (and the hostname rename isn't needed either,
since Compose's `hostname: c1`/`hostname: c2` already sets the right name):
```yaml
c1:
  entrypoint: ["/bin/bash", "-c"]
  command:
    - |
      set -e
      echo "---> Starting the MUNGE Authentication service (munged) ..."
      gosu munge /usr/sbin/munged
      echo "---> Waiting for slurmctld to become active before starting slurmd..."
      until 2>/dev/null >/dev/tcp/slurmctld/6817; do
        echo "-- slurmctld is not available.  Sleeping ..."
        sleep 2
      done
      echo "-- slurmctld is now active ..."
      exec /usr/sbin/slurmd -Z -Dvvv --conf "Feature=cpu"
  # same block for c2
```
This also fixes the cosmetic `cc1`/`cc2` naming quirk described below as a side effect,
since the buggy renaming logic is never invoked.

## Known quirk: c1/c2 may register as `cc1`/`cc2` (superseded by Issue 6 fix)

This was the originally-observed cosmetic symptom of the Issue 6 bug, documented here
for context. `detect_replica_number()`'s fallback path returns the container's own
hostname (already `c1`/`c2`), and the script then computes `NODE_NAME="c${hostname}"` →
`cc1` / `cc2`. This would have been harmless on its own (slurm.conf uses fully dynamic
nodes — `NodeSet=cpu_nodes Feature=cpu`, no static `NodeName` list — so any self-registered
hostname lands in the right partition), **but it never actually got reached**: the
`return 1` from the same fallback path kills the script under `set -e` before the rename
or `slurmd` start happens, which is the real Issue 6 bug above. With the Issue 6 fix in
place, nodes register as plain `c1`/`c2`.

## Key diagnostic commands reference

**See why a container isn't running at all:**
```bash
docker ps -a | grep -E "c1|c2"
docker logs <container_id_or_name>
```

**Tail logs for one or more services (compose-level):**
```bash
docker compose logs -f slurmctld
docker compose logs c1 c2 | tail -50
```

**Check if SELinux/permissions are blocking a mount:**
```bash
docker exec -it slurmctld mount | grep -E "slurm|munge|scripts"
docker exec -it slurmctld ls -la /scripts/
```

**Run the image manually, bypassing compose, to reproduce in isolation:**
```bash
docker run -it --rm \
  --network slurm_default \
  --privileged \
  -v slurm_etc_munge:/etc/munge:z \
  -v slurm_etc_slurm:/etc/slurm:z \
  -v slurm_var_log_slurm:/var/log/slurm:z \
  giovtorres/slurm-docker-cluster:latest \
  bash
```

**IMPORTANT gotcha when debugging the entrypoint manually:** this image's `ENTRYPOINT`
is `/usr/local/bin/docker-entrypoint.sh`, and it unconditionally starts `munged` as its
very first action — *before* it even looks at `$1`. If you `docker run ... image bash -c '...'`
**without** `--entrypoint`, Docker appends `bash -c '...'` as arguments to that same
entrypoint script, so munged gets started once by the real entrypoint and then your
debug script tries to start it *again*, producing a false
`Found pid N bound to socket` error that has nothing to do with the real bug. Always use
`--entrypoint /bin/bash` to fully bypass it when debugging manually:
```bash
docker run -it --rm \
  --network slurm_default --privileged \
  -v slurm_etc_munge:/etc/munge:z \
  -v slurm_etc_slurm:/etc/slurm:z \
  -v slurm_var_log_slurm:/var/log/slurm:z \
  --entrypoint /bin/bash \
  giovtorres/slurm-docker-cluster:latest \
  -c 'set -e; set -x
gosu munge /usr/sbin/munged
until 2>/dev/null >/dev/tcp/slurmctld/6817; do sleep 2; done
echo "-- slurmctld is now active ..."
REPLICA=$(hostname)
NODE_NAME="c${REPLICA}"
hostname "$NODE_NAME"
/usr/sbin/slurmd -Z -Dvvv'
```

**Full clean restart (use when state looks corrupted):**
```bash
docker compose down -v
docker compose up -d
sleep 10
docker ps
docker exec -it slurmctld sinfo
```

**End-to-end functional test once nodes are up:**
```bash
docker exec -it slurmctld sinfo
docker exec -it slurmctld scontrol show nodes
docker exec -it slurmctld sbatch /scripts/test_job.sh
docker exec -it slurmctld squeue
docker exec -it slurmctld sacct --format=JobID,JobName,State,NodeList
```

## Final working `docker-compose.yml` shape

```yaml
volumes:
  etc_munge:
  etc_slurm:
  var_log_slurm:

services:
  mysql:
    image: mariadb:10.11
    container_name: mysql
    hostname: mysql
    environment:
      MYSQL_ROOT_PASSWORD: "password"
      MYSQL_DATABASE: slurm_acct_db
      MYSQL_USER: slurm
      MYSQL_PASSWORD: password

  slurmdbd:
    image: giovtorres/slurm-docker-cluster:latest
    container_name: slurmdbd
    hostname: slurmdbd
    command: ["slurmdbd"]
    volumes:
      - ./scripts:/scripts:z
      - etc_munge:/etc/munge:z
      - etc_slurm:/etc/slurm:z
      - var_log_slurm:/var/log/slurm:z
    environment:
      - SLURM_JOB_COMPLETION_LOGGING=1
      - MYSQL_USER=slurm
      - MYSQL_PASSWORD=password
    depends_on:
      - mysql

  slurmctld:
    image: giovtorres/slurm-docker-cluster:latest
    container_name: slurmctld
    hostname: slurmctld
    command: ["slurmctld"]
    privileged: true
    volumes:
      - ./scripts:/scripts:z
      - etc_munge:/etc/munge:z
      - etc_slurm:/etc/slurm:z
      - var_log_slurm:/var/log/slurm:z
    ports:
      - "6817:6817"
      - "6818:6818"
    depends_on:
      - slurmdbd

  c1:
    image: giovtorres/slurm-docker-cluster:latest
    container_name: c1
    hostname: c1
    entrypoint: ["/bin/bash", "-c"]
    command:
      - |
        set -e
        echo "---> Starting the MUNGE Authentication service (munged) ..."
        gosu munge /usr/sbin/munged
        echo "---> Waiting for slurmctld to become active before starting slurmd..."
        until 2>/dev/null >/dev/tcp/slurmctld/6817; do
          echo "-- slurmctld is not available.  Sleeping ..."
          sleep 2
        done
        echo "-- slurmctld is now active ..."
        exec /usr/sbin/slurmd -Z -Dvvv --conf "Feature=cpu"
    privileged: true
    volumes:
      - ./scripts:/scripts:z
      - etc_munge:/etc/munge:z
      - etc_slurm:/etc/slurm:z
      - var_log_slurm:/var/log/slurm:z
    depends_on:
      - slurmctld

  c2:
    image: giovtorres/slurm-docker-cluster:latest
    container_name: c2
    hostname: c2
    entrypoint: ["/bin/bash", "-c"]
    command:
      - |
        set -e
        echo "---> Starting the MUNGE Authentication service (munged) ..."
        gosu munge /usr/sbin/munged
        echo "---> Waiting for slurmctld to become active before starting slurmd..."
        until 2>/dev/null >/dev/tcp/slurmctld/6817; do
          echo "-- slurmctld is not available.  Sleeping ..."
          sleep 2
        done
        echo "-- slurmctld is now active ..."
        exec /usr/sbin/slurmd -Z -Dvvv --conf "Feature=cpu"
    privileged: true
    volumes:
      - ./scripts:/scripts:z
      - etc_munge:/etc/munge:z
      - etc_slurm:/etc/slurm:z
      - var_log_slurm:/var/log/slurm:z
    depends_on:
      - slurmctld
```
