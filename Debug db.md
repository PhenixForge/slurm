Ready for review
Select text to add comments on the plan
Fix slurmdbd/slurmctld/c1/c2 containers all starting the wrong Slurm role
Context
docker compose up -d starts, but slurmctld's logs show:

slurmctld  | ---> Starting the Slurm Database Daemon (slurmdbd) ...
slurmctld  | ERROR 2002 (HY000): Can't connect to MySQL server on 'mysql' (115)
slurmctld  | ERROR 1045 (28000): Access denied for user '-p'@'172.18.0.4' (using password: NO)
Root cause, confirmed by reading the giovtorres/slurm-docker-cluster image's actual Dockerfile and docker-entrypoint.sh on GitHub:

The image's CMD defaults to ["slurmdbd"] (Dockerfile: CMD ["slurmdbd"]). docker-entrypoint.sh picks which daemon to run by checking "$1" (the container's command). None of the services in docker-compose.yml set a command:, so every container (slurmdbd, slurmctld, c1, c2) falls back to the image default and runs the slurmdbd branch of the entrypoint — that's why slurmctld's logs say "Starting the Slurm Database Daemon".
Inside that slurmdbd branch, the entrypoint does:
until echo "SELECT 1" | mysql -h mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} ...
The slurmdbd service in docker-compose.yml never sets MYSQL_USER/MYSQL_PASSWORD (only the mysql service itself has them), so both expand to empty strings, and the command becomes literally mysql -h mysql -u -p. MySQL's CLI parses the bare -p as the value of -u (producing user -p) and is left with no password flag at all — exactly matching Access denied for user '-p'@'...' (using password: NO).
The fix is to give each service an explicit command: (matching the role the entrypoint script expects: slurmdbd, slurmctld, slurmd-cpu) and to pass MYSQL_USER/MYSQL_PASSWORD to the slurmdbd service so it can both authenticate to MySQL and populate /etc/slurm/slurmdbd.conf (which the entrypoint fills in via envsubst from a template containing StorageUser=${MYSQL_USER} / StoragePass=${MYSQL_PASSWORD}).

This was verified against the upstream project's own docker-compose.yml/docker-entrypoint.sh/config/common/slurmdbd.conf, which confirm the exact same env vars and command: values for these roles.

Change
Edit docker-compose.yml:

slurmdbd service: add
command: ["slurmdbd"]
environment:
  MYSQL_USER: slurm
  MYSQL_PASSWORD: password
(values matching the mysql service's MYSQL_USER/MYSQL_PASSWORD). Keep the existing SLURM_JOB_COMPLETION_LOGGING=1 line alongside the new vars.
slurmctld service: add command: ["slurmctld"].
c1 service: add command: ["slurmd-cpu"].
c2 service: add command: ["slurmd-cpu"].
No other services need changes. The already-uncommitted MYSQL_ROOT_PASSWORD tweak on the mysql service is unrelated to this bug (slurmdbd authenticates as the slurm user, not root) and can stay as-is.

Note (not actioned, just FYI): the image's node self-naming logic (detect_replica_number in docker-entrypoint.sh) expects Compose's scaled-replica DNS names (<project>-cpu-worker-N) to derive node names c1/c2. Since this repo names the services c1/c2 directly instead of a scaled cpu-worker service, that detection falls back to the container's own hostname and the worker ends up registering as cc1/cc2 inside Slurm (visible in sinfo/squeue) instead of c1/c2. This is purely cosmetic — the cluster's slurm.conf uses fully dynamic nodes (NodeSet=cpu_nodes Feature=cpu, no static NodeName list), so whatever hostname the worker self-registers under still lands correctly in the cpu partition.

Verification
docker compose up -d
docker compose logs -f slurmdbd — expect -- Database is now active ... then starting slurmdbd, no more MySQL errors.
docker compose logs -f slurmctld — expect -- slurmdbd is now active ... then Starting the Slurm Controller Daemon.
docker exec -it slurmctld sinfo — expect two nodes up in the cpu partition (named c1/c2 or cc1/cc2 per the note above).
Run the existing test job flow from README.md: docker exec -it slurmctld bash -c "cd /scripts && sbatch test_job.sh" then squeue / sacct to confirm a job actually runs on a worker.

---

## Results
```bash
docker compose logs -f slurmdbd
slurmdbd  | ---> Starting the MUNGE Authentication service (munged) ...
slurmdbd  | ---> Starting the Slurm Database Daemon (slurmdbd) ...
slurmdbd  | 1+0 records in
slurmdbd  | 1+0 records out
slurmdbd  | 32 bytes copied, 2.1907e-05 s, 1.5 MB/s
slurmdbd  | ERROR 2002 (HY000): Can't connect to MySQL server on 'mysql' (115)
slurmdbd  | -- Waiting for database to become active ...
slurmdbd  | ERROR 2002 (HY000): Can't connect to MySQL server on 'mysql' (115)
slurmdbd  | -- Waiting for database to become active ...
slurmdbd  | -- Database is now active ...
slurmdbd  | [2026-10-08T19:32:19.734] debug:  Log file re-opened
slurmdbd  | [2026-10-08T19:32:19.735] debug:  loaded
slurmdbd  | [2026-10-08T19:32:19.735] debug:  atomic_log_features: _Atomic enabled: bool=lock-free char=lock-free char16=lock-free char32=lock-free wchar=lock-free short=lock-free int=lock-free long=lock-free llong=lock-free pointer=lock-free char8=N/A
slurmdbd  | [2026-10-08T19:32:19.736] debug:  auth/munge: init: loaded
slurmdbd  | [2026-10-08T19:32:19.738] debug:  _plugrack_foreach: serializer plugin type:serializer/json path:/usr/lib64/slurm/serializer_json.so
slurmdbd  | [2026-10-08T19:32:19.738] debug:  _plugrack_foreach: serializer plugin type:serializer/url-encoded path:/usr/lib64/slurm/serializer_url_encoded.so
slurmdbd  | [2026-10-08T19:32:19.738] debug:  _plugrack_foreach: serializer plugin type:serializer/yaml path:/usr/lib64/slurm/serializer_yaml.so
slurmdbd  | [2026-10-08T19:32:19.738] debug:  auth/jwt: parse_auth_params: use_jwt_client_ids: 0, use_jwt_client_ids_only: 0
slurmdbd  | [2026-10-08T19:32:19.738] debug:  auth/jwt: init_hs256: init_hs256: Loading key: /etc/slurm/jwt_hs256.key
slurmdbd  | [2026-10-08T19:32:19.738] debug:  auth/jwt: init: JWT authentication plugin loaded
slurmdbd  | [2026-10-08T19:32:19.738] debug:  hash/k12: init: init: KangarooTwelve hash plugin loaded
slurmdbd  | [2026-10-08T19:32:19.739] debug:  tls/none: init: tls/none loaded
slurmdbd  | [2026-10-08T19:32:19.741] debug2: accounting_storage/as_mysql: init: mysql_connect() called for db slurm_acct_db
slurmdbd  | [2026-10-08T19:32:19.741] debug2: Attempting to connect to mysql:3306
slurmdbd  | [2026-10-08T19:32:19.742] accounting_storage/as_mysql: _check_mysql_concat_is_sane: MySQL server version is: 10.11.19-MariaDB-ubu2204
slurmdbd  | [2026-10-08T19:32:19.742] debug2: accounting_storage/as_mysql: _check_database_variables: innodb_buffer_pool_size: 134217728
slurmdbd  | [2026-10-08T19:32:19.742] debug2: accounting_storage/as_mysql: _check_database_variables: innodb_log_file_size: 100663296
slurmdbd  | [2026-10-08T19:32:19.742] debug2: accounting_storage/as_mysql: _check_database_variables: innodb_lock_wait_timeout: 50
slurmdbd  | [2026-10-08T19:32:19.742] debug2: accounting_storage/as_mysql: _check_database_variables: max_allowed_packet: 16777216
slurmdbd  | [2026-10-08T19:32:19.742] error: Database settings not recommended values: innodb_buffer_pool_size innodb_lock_wait_timeout
slurmdbd  | [2026-10-08T19:32:19.752] debug2: query
slurmdbd  | alter table convert_version_table modify `mod_time` bigint unsigned default 0 not null, modify `version` int default 0, drop primary key, add primary key (version);
slurmdbd  | [2026-10-08T19:32:19.764] debug2: query
slurmdbd  | alter table cluster_table modify `creation_time` bigint unsigned not null, modify `mod_time` bigint unsigned default 0 not null, modify `deleted` tinyint default 0, modify `name` tinytext not null, modify `id` smallint, modify `control_host` tinytext not null default '', modify `control_port` int unsigned not null default 0, modify `last_port` int unsigned not null default 0, modify `rpc_version` smallint unsigned not null default 0, modify `classification` smallint unsigned default 0, modify `dimensions` smallint unsigned default 1, modify `flags` int unsigned default 0, modify `federation` tinytext not null, modify `features` text not null default '', modify `fed_id` int unsigned default 0 not null, modify `fed_state` smallint unsigned not null, drop primary key, add primary key (name(42));
slurmdbd  | [2026-10-08T19:32:19.777] debug2: query
slurmdbd  | alter table txn_table modify `deleted` tinyint default 0 not null, modify `id` int not null auto_increment, modify `timestamp` bigint unsigned default 0 not null, modify `action` smallint not null, modify `name` text not null, modify `actor` tinytext not null, modify `cluster` tinytext not null default '', modify `info` blob, drop primary key, add primary key (id), drop key archive_delete, add key archive_delete (deleted), drop key archive_purge, add key archive_purge (timestamp, cluster(42));
slurmdbd  | [2026-10-08T19:32:19.791] debug2: query
slurmdbd  | alter table tres_table modify `creation_time` bigint unsigned not null, modify `deleted` tinyint default 0 not null, modify `id` int not null auto_increment, modify `type` tinytext not null, modify `name` tinytext not null default '', drop primary key, add primary key (id), drop index udex, add unique index udex (type(42), name(42));
slurmdbd  | [2026-10-08T19:32:19.803] debug2: query
slurmdbd  | alter table acct_coord_table modify `creation_time` bigint unsigned not null, modify `mod_time` bigint unsigned default 0 not null, modify `deleted` tinyint default 0, modify `acct` tinytext not null, modify `user` tinytext not null, drop primary key, add primary key (acct(42), user(42)), drop key user, add key user (user(42));
slurmdbd  | [2026-10-08T19:32:19.817] debug2: query
slurmdbd  | alter table acct_table modify `creation_time` bigint unsigned not null, modify `mod_time` bigint unsigned default 0 not null, modify `deleted` tinyint default 0, modify `flags` int unsigned default 0, modify `name` tinytext not null, modify `description` text not null, modify `organization` text not null, drop primary key, add primary key (name(42));
slurmdbd  | [2026-10-08T19:32:19.831] debug2: query
slurmdbd  | alter table res_table modify `creation_time` bigint unsigned not null, modify `mod_time` bigint unsigned default 0 not null, modify `deleted` tinyint default 0, modify `id` int not null auto_increment, modify `name` tinytext not null, modify `description` text default null, modify `manager` tinytext not null, modify `server` tinytext not null, modify `count` int unsigned default 0, modify `type` int unsigned default 0, modify `flags` int unsigned default 0, modify `last_consumed` int unsigned default 0, drop primary key, add primary key (id), drop index udex, add unique index udex (name(42), server(42), type);
slurmdbd  | [2026-10-08T19:32:19.847] debug2: query
slurmdbd  | alter table clus_res_table modify `creation_time` bigint unsigned not null, modify `mod_time` bigint unsigned default 0 not null, modify `deleted` tinyint default 0, modify `cluster` tinytext not null, modify `res_id` int not null, modify `allowed` int unsigned default 0, drop primary key, add primary key (res_id, cluster(42));
slurmdbd  | [2026-10-08T19:32:19.860] debug2: query
slurmdbd  | alter table qos_table modify `creation_time` bigint unsigned not null, modify `mod_time` bigint unsigned default 0 not null, modify `deleted` tinyint default 0, modify `id` int not null auto_increment, modify `name` tinytext not null, modify `description` text, modify `flags` int unsigned default 0, modify `grace_time` int unsigned default NULL, modify `max_jobs_pa` int default NULL, modify `max_jobs_per_user` int default NULL, modify `max_jobs_accrue_pa` int default NULL, modify `max_jobs_accrue_pu` int default NULL, modify `min_prio_thresh` int default NULL, modify `max_submit_jobs_pa` int default NULL, modify `max_submit_jobs_per_user` int default NULL, modify `max_tres_pa` text not null default '', modify `max_tres_pj` text not null default '', modify `max_tres_pn` text not null default '', modify `max_tres_pu` text not null default '', modify `max_tres_mins_pj` text not null default '', modify `max_tres_run_mins_pa` text not null default '', modify `max_tres_run_mins_pu` text not null default '', modify `min_tres_pj` text not null default '', modify `max_wall_duration_per_job` int default NULL, modify `grp_jobs` int default NULL, modify `grp_jobs_accrue` int default NULL, modify `grp_submit_jobs` int default NULL, modify `grp_tres` text not null default '', modify `grp_tres_mins` text not null default '', modify `grp_tres_run_mins` text not null default '', modify `grp_wall` int default NULL, modify `preempt` text not null default '', modify `preempt_mode` int default 0, modify `preempt_exempt_time` int unsigned default NULL, modify `priority` int unsigned default 0, modify `usage_factor` double default 1.0 not null, modify `usage_thres` double default NULL, modify `limit_factor` double default NULL, drop primary key, add primary key (id), drop index udex, add unique index udex (name(42));
slurmdbd  | [2026-10-08T19:32:19.873] debug2: query
slurmdbd  | alter table user_table modify `creation_time` bigint unsigned not null, modify `mod_time` bigint unsigned default 0 not null, modify `deleted` tinyint default 0, modify `name` tinytext not null, modify `admin_level` smallint default 1 not null, drop primary key, add primary key (name(42));
slurmdbd  | [2026-10-08T19:32:19.884] debug2: query
slurmdbd  | alter table federation_table modify `creation_time` int unsigned not null, modify `mod_time` int unsigned default 0 not null, modify `deleted` tinyint default 0, modify `name` tinytext not null, modify `flags` int unsigned default 0, drop primary key, add primary key (name(42));
slurmdbd  | [2026-10-08T19:32:19.894] accounting_storage/as_mysql: init: Accounting storage MYSQL plugin loaded
slurmdbd  | [2026-10-08T19:32:19.895] debug2: no streaming replication settings to restore
slurmdbd  | [2026-10-08T19:32:19.895] debug2: AllowNoDefAcct         = no
slurmdbd  | [2026-10-08T19:32:19.895] debug2: ArchiveDir             = /tmp
slurmdbd  | [2026-10-08T19:32:19.895] debug2: ArchiveEvents          = no
slurmdbd  | [2026-10-08T19:32:19.895] debug2: ArchiveJobs            = no
slurmdbd  | [2026-10-08T19:32:19.895] debug2: ArchiveJobScript       = no
slurmdbd  | [2026-10-08T19:32:19.895] debug2: ArchiveJobEnv          = no
slurmdbd  | [2026-10-08T19:32:19.895] debug2: ArchiveResvs           = no
slurmdbd  | [2026-10-08T19:32:19.895] debug2: ArchiveScript          = (null)
slurmdbd  | [2026-10-08T19:32:19.895] debug2: ArchiveSteps           = no
slurmdbd  | [2026-10-08T19:32:19.895] debug2: ArchiveSuspend         = no
slurmdbd  | [2026-10-08T19:32:19.895] debug2: ArchiveTXN             = no
slurmdbd  | [2026-10-08T19:32:19.895] debug2: ArchiveUsage           = no
slurmdbd  | [2026-10-08T19:32:19.895] debug2: AuthAltTypes           = auth/jwt
slurmdbd  | [2026-10-08T19:32:19.895] debug2: AuthAltParameters      = jwt_key=/etc/slurm/jwt_hs256.key
slurmdbd  | [2026-10-08T19:32:19.895] debug2: AuthInfo               = (null)
slurmdbd  | [2026-10-08T19:32:19.895] debug2: AuthType               = auth/munge
slurmdbd  | [2026-10-08T19:32:19.895] debug2: CommitDelay            = 0
slurmdbd  | [2026-10-08T19:32:19.895] debug2: CommunicationParameters = (null)
slurmdbd  | [2026-10-08T19:32:19.895] debug2: DbdAddr                = slurmdbd
slurmdbd  | [2026-10-08T19:32:19.895] debug2: DbdBackupHost          = (null)
slurmdbd  | [2026-10-08T19:32:19.895] debug2: DbdHost                = slurmdbd
slurmdbd  | [2026-10-08T19:32:19.895] debug2: DbdPort                = 6819
slurmdbd  | [2026-10-08T19:32:19.895] debug2: DebugFlags             = (null)
slurmdbd  | [2026-10-08T19:32:19.895] debug2: DebugLevel             = debug2
slurmdbd  | [2026-10-08T19:32:19.895] debug2: DebugLevelSyslog       = (null)
slurmdbd  | [2026-10-08T19:32:19.895] debug2: DefaultQOS             = (null)
slurmdbd  | [2026-10-08T19:32:19.895] debug2: DisableCoordDBD        = no
slurmdbd  | [2026-10-08T19:32:19.895] debug2: DisableArchiveCommands = no
slurmdbd  | [2026-10-08T19:32:19.895] debug2: DisableRollups         = no
slurmdbd  | [2026-10-08T19:32:19.895] debug2: HashPlugin             = hash/k12
slurmdbd  | [2026-10-08T19:32:19.895] debug2: LogFile                = /var/log/slurm/slurmdbd.log
slurmdbd  | [2026-10-08T19:32:19.895] debug2: MaxPurgeLimit          = 50000
slurmdbd  | [2026-10-08T19:32:19.895] debug2: MaxQueryTimeRange      = UNLIMITED
slurmdbd  | [2026-10-08T19:32:19.895] debug2: MessageTimeout         = 10 secs
slurmdbd  | [2026-10-08T19:32:19.895] debug2: Parameters             = (null)
slurmdbd  | [2026-10-08T19:32:19.895] debug2: PidFile                = /var/run/slurm/slurmdbd.pid
slurmdbd  | [2026-10-08T19:32:19.895] debug2: PluginDir              = /usr/lib64/slurm
slurmdbd  | [2026-10-08T19:32:19.895] debug2: PrivateData            = none
slurmdbd  | [2026-10-08T19:32:19.895] debug2: PurgeEventAfter        = NONE
slurmdbd  | [2026-10-08T19:32:19.895] debug2: PurgeJobAfter          = NONE
slurmdbd  | [2026-10-08T19:32:19.895] debug2: PurgeResvAfter         = NONE
slurmdbd  | [2026-10-08T19:32:19.895] debug2: PurgeStepAfter         = NONE
slurmdbd  | [2026-10-08T19:32:19.895] debug2: PurgeSuspendAfter      = NONE
slurmdbd  | [2026-10-08T19:32:19.895] debug2: PurgeTXNAfter          = NONE
slurmdbd  | [2026-10-08T19:32:19.895] debug2: PurgeUsageAfter        = NONE
slurmdbd  | [2026-10-08T19:32:19.895] debug2: PurgeJobScriptAfter    = NONE
slurmdbd  | [2026-10-08T19:32:19.895] debug2: PurgeJobEnvAfter       = NONE
slurmdbd  | [2026-10-08T19:32:19.895] debug2: SLURMDBD_CONF          = /etc/slurm/slurmdbd.conf
slurmdbd  | [2026-10-08T19:32:19.895] debug2: SLURMDBD_VERSION       = 26.05.2
slurmdbd  | [2026-10-08T19:32:19.895] debug2: SlurmUser              = slurm(990)
slurmdbd  | [2026-10-08T19:32:19.895] debug2: StorageBackupHost      = (null)
slurmdbd  | [2026-10-08T19:32:19.895] debug2: StorageHost            = mysql
slurmdbd  | [2026-10-08T19:32:19.895] debug2: StorageLoc             = slurm_acct_db
slurmdbd  | [2026-10-08T19:32:19.895] debug2: StorageParameters      = (null)
slurmdbd  | [2026-10-08T19:32:19.895] debug2: StoragePassScript      = (null)
slurmdbd  | [2026-10-08T19:32:19.895] debug2: StoragePort            = 3306
slurmdbd  | [2026-10-08T19:32:19.895] debug2: StorageType            = accounting_storage/mysql
slurmdbd  | [2026-10-08T19:32:19.895] debug2: StorageUser            = slurm
slurmdbd  | [2026-10-08T19:32:19.895] debug2: TCPTimeout             = 2 secs
slurmdbd  | [2026-10-08T19:32:19.895] debug2: TLSParameters          = (null)
slurmdbd  | [2026-10-08T19:32:19.895] debug2: TLSType                = tls/none
slurmdbd  | [2026-10-08T19:32:19.895] debug2: TrackWCKey             = no
slurmdbd  | [2026-10-08T19:32:19.895] debug2: TrackSlurmctldDown     = no
slurmdbd  | [2026-10-08T19:32:19.895] debug2: accounting_storage/as_mysql: acct_storage_p_get_connection: request new connection 1
slurmdbd  | [2026-10-08T19:32:19.895] debug2: Attempting to connect to mysql:3306
slurmdbd  | [2026-10-08T19:32:19.895] slurmdbd version 26.05.2 started
slurmdbd  | [2026-10-08T19:32:19.895] debug2: running rollup
slurmdbd  | [2026-10-08T19:32:19.896] debug2: accounting_storage/as_mysql: as_mysql_roll_usage: Everything rolled up
```
