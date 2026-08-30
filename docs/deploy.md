# Deploy — school-app

Production runs as a single Docker container on one DigitalOcean droplet, deployed by Kamal from a
GitHub Actions job that only fires on a green `main`.

## Why a droplet and not App Platform

`config/database.yml` gives production four SQLite databases — `primary`, `cache`, `queue`, `cable` —
all files under `storage/`, and `config/storage.yml` roots Active Storage's local disk service in the
same directory. Every piece of production state is therefore a file on disk, which forces two things:

- **A persistent volume.** DigitalOcean App Platform has an ephemeral filesystem and cannot attach block
  storage, so every deploy there would silently start from an empty database. `config/deploy.yml` mounts
  the named volume `school_app_storage` at `/rails/storage` instead.
- **Exactly one app server.** Two servers would each get their own copy of the four databases. Scaling
  out means moving to Postgres first — a change to `database.yml`, to the concurrency reasoning in
  `docs/agent-rules.md` § Attempt lifecycle (`.lock` is a no-op on SQLite but emits `FOR UPDATE` on
  Postgres), and a data migration. It is not a deployment task.

## One-time setup

### 1. The droplet

Create an Ubuntu LTS droplet, `s-1vcpu-2gb`, in a region close to the classrooms — Frankfurt for
Ukraine. Latency is felt here rather than merely measured: the runner autosaves every 5 seconds and the
live board polls every 4, for every student at once.

One vCPU is the right number, not a compromise. SQLite serializes writes on the database lock for the
whole of each `:immediate` transaction, so extra cores buy no throughput — which is also why
`WEB_CONCURRENCY` stays at 1 — and images are built on the CI runner, never here.

2 GB is, though. A production Rails process eager-loads to ~120 MB; Puma plus the Solid Queue
supervisor and its three forks land around 600-800 MB, and Docker and the OS take another 250-400.
That fits in 1 GB right up until a deploy, when Kamal runs the old and new containers side by side
until `/up` answers and the total roughly doubles. DigitalOcean droplets ship without swap, so that
peak is an OOM kill rather than a slow minute. Adding a swap file is worth it either way:

```bash
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo "/swapfile none swap sw 0 0" >> /etc/fstab
```

Turn on **Backups** (+20%) while creating it. The nightly snapshots from `BackupDatabaseJob` live on
the same volume as the database, so they cover a bad migration but not a lost droplet; DigitalOcean's
weekly image is the cheapest thing that covers the second case. **Monitoring** is free and worth having
given there is no error tracking.

Add your SSH key at creation time. Then, with a DigitalOcean Cloud Firewall or `ufw`, allow inbound
`22/tcp`, `80/tcp` and `443/tcp`. Keep SSH open to any source: GitHub-hosted runners have no stable
egress IP. Port 80 stays open even though the app redirects to HTTPS — Let's Encrypt answers its
HTTP-01 challenge there.

The droplet's public IPv4 address goes into `config/deploy.yml` under `servers.web`. That file is the
only place it is configured — the deploy job reads it back out to pin the host key, so a wrong address
fails at `ssh-keyscan` naming it rather than somewhere deep inside Kamal. Rebuilding onto a new droplet
means editing that one line.

### 1b. DNS, before the first deploy

`config/deploy.yml` sets `proxy.ssl: true`, so kamal-proxy asks Let's Encrypt for a certificate the
first time it boots. The challenge resolves `edubba.com.ua` over the public internet and connects back
on port 80, so **the A record has to exist and have propagated before that deploy runs**, or the
container comes up without a certificate.

| Type | Name | Value |
| --- | --- | --- |
| A | `edubba.com.ua` (apex, often written `@`) | the droplet's IPv4 address |

Only the apex. Every name in `proxy.host` is certified, and one without an A record fails the whole
challenge — adding `www` later means a DNS record, `proxy.host`, and `config.hosts` in the same change.

**Delete any `AAAA` record that does not point at this droplet.** Let's Encrypt prefers IPv6 when both
families are published, so a stale `AAAA` left over from a previous host silently sends the challenge to
a server that knows nothing about it — the A record looks right, the certificate never arrives, and each
retry spends one of the five failures per hour the rate limit allows. Either drop the record, or, if the
droplet has IPv6 enabled, point it at the droplet's own address.

Confirm both families before going further, not just the one you set:

```bash
dig +short A edubba.com.ua       # the droplet
dig +short AAAA edubba.com.ua    # empty, or the droplet's IPv6
```

`.com.ua` can propagate more slowly than the common zones; querying a public resolver
(`dig +short edubba.com.ua @8.8.8.8`) shows what Let's Encrypt will see rather than what your ISP cached.

### 2. A deploy key for GitHub Actions

The runner needs its own keypair; do not reuse a personal key.

```bash
ssh-keygen -t ed25519 -C "github-actions@school-app" -f ~/.ssh/school_app_deploy -N ""
ssh-copy-id -i ~/.ssh/school_app_deploy.pub root@<droplet-ip>
```

### 3. Repository secrets

At **Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `SSH_PRIVATE_KEY` | the full contents of `~/.ssh/school_app_deploy`, including the BEGIN/END lines |
| `RAILS_MASTER_KEY` | the contents of `config/master.key` |

The registry password is not a secret you set: the deploy job passes the workflow's built-in
`GITHUB_TOKEN`, which has push access to `ghcr.io` under the repository owner. Kamal uses it to log both
the runner and the droplet into the registry, so the workflow has no separate login step.

### 4. `.kamal/secrets`

Kamal resolves `env.secret` and `registry.password` through `.kamal/secrets`. Two lines in the
generated file need editing before CI can deploy — one is commented out, the other reads a file that
does not exist on a runner:

```sh
# Uncomment this one. Without it Kamal aborts with
# "Secret 'KAMAL_REGISTRY_PASSWORD' not found in .kamal/secrets".
KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD

# Was: RAILS_MASTER_KEY=$(cat config/master.key)
# config/master.key is gitignored, so on a runner that file does not exist.
RAILS_MASTER_KEY=$RAILS_MASTER_KEY
```

**This file is not a shell script.** Kamal parses it with dotenv, which understands `$VAR` and
`${VAR}` and nothing else — there is no `${VAR:-default}`. Writing one does not fail loudly; it
corrupts the value. With `RAILS_MASTER_KEY` set to `abc123`, dotenv parses

```sh
RAILS_MASTER_KEY=${RAILS_MASTER_KEY:-$(cat config/master.key)}
```

into `abc123:-}` — the variable substituted, the rest of the shell syntax left in place as literal
text. The container then boots with a master key that is almost right, fails to decrypt credentials,
and never answers the health check.

Kamal also runs every `$(...)` unconditionally while parsing, so a `cat: config/master.key: No such
file or directory` line in the deploy log is expected noise on a runner, not evidence of a missing
secret.

Because there is no fallback syntax, `bin/kamal` from your own machine needs the key in the
environment too:

```bash
export RAILS_MASTER_KEY=$(cat config/master.key)
```

Worth putting in your shell profile, or in a direnv `.envrc` for the project.

### 5. Bootstrap the droplet, then let CI do the first deploy

`kamal deploy` assumes Docker is already installed on the server. Install it once from a machine that
has the repo and SSH access — this step builds nothing, so it is fast even on Apple Silicon:

```bash
KAMAL_REGISTRY_PASSWORD=unused bin/kamal server bootstrap
```

Then merge to `main`. The `deploy` job builds the image on an amd64 runner, pushes it to
`ghcr.io/yarov1/school-app`, boots `kamal-proxy`, and starts the app. `bin/docker-entrypoint` runs
`bin/rails db:prepare` on boot, which creates and migrates all four databases on the mounted volume.

`db:prepare` seeds any database it had to create, which on a fresh volume would publish the demo
teacher whose password is in the public README and log the demo `/t/` tokens. Two things stop it:
`seeds: false` on the production primary in `config/database.yml` keeps `db:prepare` from loading
the file at all, and `db/seeds.rb` aborts on `Rails.env.production?` so a hand-typed `bin/rails
db:seed` cannot get through either.

That leaves no account to sign in with, and there is no registration route, so create the first
teacher with the provisioning task:

```bash
bin/kamal app exec --interactive --reuse "bin/rails teacher:create"
```

`--interactive` is what gives the process a TTY, and the TTY is what lets the task read the password
without echoing it — keeping it out of the command line, the process list and your shell history.
The password must be at least 12 characters; `User::MINIMUM_PASSWORD_LENGTH` is the rule.

The `Dockerfile` carries `LABEL org.opencontainers.image.source`, which is what attaches the published
package to this repository. Without that link GHCR creates the package unattached, and `GITHUB_TOKEN`
loses push access after the first deploy.

### 6. Make the package public

After the first successful push, the GHCR package is private and the droplet pulls it with the
workflow's `GITHUB_TOKEN`, which expires when the run ends. Set the package to public at
**github.com/users/yaroV1/packages → school-app → Package settings → Change visibility** so the droplet
can pull unauthenticated. The repository is already public, so this leaks nothing new.

## After the first deploy

Four checks, in this order. The first two are about whether TLS actually happened; the third catches a
misconfiguration that looks fine until it matters.

```bash
# 1. The certificate is real and issued to the domain, not a self-signed placeholder.
curl -sSI https://edubba.com.ua/up | head -1

# 2. Plain HTTP redirects rather than serving.
curl -sSI http://edubba.com.ua/ | head -1        # expect 301

# 3. The client IP reaches Rails. Sign in first, then:
bin/kamal app exec --reuse "bin/rails runner 'puts Session.last.ip_address'"

# 4. The first nightly snapshot, the morning after.
bin/kamal app exec --reuse "ls -la storage/backups"
```

Check 3 is the one worth understanding. With `proxy.ssl: true` kamal-proxy stops forwarding
`X-Forwarded-For` unless `forward_headers: true` is set, and `request.remote_ip` is what
`rate_limit to: 10, within: 3.minutes` on `SessionsController#create` keys on. If that command prints a
private address (`172.x`, `10.x`) rather than your own public one, the login limit is being counted
globally instead of per client — one person hammering the form could lock the teacher out in
three-minute stretches. The fix is `forward_headers: true` under `proxy:` in `config/deploy.yml`.

TLS itself does not depend on this: `config.assume_ssl` sets `HTTPS=on` and `X-Forwarded-Proto` on every
request from inside Rails, without asking the proxy.

## Deploying after that

Every push to `main` runs the four existing CI jobs; `deploy` has `needs` on all of them, so red CI never
reaches production. Deploys are serialized by a `concurrency` group — a second push waits rather than
cancelling, because a cancelled run can leave the droplet mid-swap.

Kamal deploys by rolling: it starts the new container, waits for `/up` to answer, then stops the old one.
Both containers briefly share the SQLite volume. That is safe here — `default_transaction_mode` is
`:immediate`, so writers serialize on the database write lock, and Solid Queue's recurring tasks are
guarded by a unique index on `(task_key, run_at)` against double execution during the overlap.

## Day-to-day

```bash
bin/kamal logs           # tail
bin/kamal console        # bin/rails console on the droplet
bin/kamal shell          # bash in the container
bin/kamal app details    # what is running
bin/kamal rollback <version>
```

These talk to the droplet over SSH from your machine, so they need `KAMAL_REGISTRY_PASSWORD` set to a
personal access token with `read:packages` (unless the package is public, per step 6).

`rollback` swaps the container back to a previous image. It does **not** reverse migrations, so a
rollback across a migration that dropped or rewrote a column needs a manual fix.

## Backups

`BackupDatabaseJob` runs nightly at 03:30 Kyiv time from `config/recurring.yml` and keeps the last
seven snapshots in `storage/backups/`. No host cron is involved: `SOLID_QUEUE_IN_PUMA` runs the Solid
Queue supervisor inside Puma, and its scheduler reads `recurring.yml` itself. The corollary is that a
container which is not running takes no backup that night.

Take one by hand before a migration or a bulk edit:

```bash
bin/kamal app exec --reuse "bin/rails db:backup"
bin/kamal app exec --reuse "ls -la storage/backups"
```

Snapshots use `VACUUM INTO`, not a file copy. Under WAL the `.sqlite3` file on its own is not a
database — the newest commits sit in `-wal` until a checkpoint — so `cp` produces a backup that
restores to a moment nobody ever saw. Only `primary` is copied; `cache`, `queue` and `cable` are
rebuildable.

Restoring is in [`../README.md`](../README.md) § Backups, including the step people skip: delete
`-wal` and `-shm` before starting the app, or the stale log replays over what you restored.

**Still not off-server.** The snapshots share the volume with the database, so they cover a bad
migration, a wrong edit or a corrupted file — not a lost volume or a lost droplet. Turn on
DigitalOcean droplet backups for a coarse automatic floor, and pull the directory down periodically:

```bash
scp -r root@<droplet-ip>:/var/lib/docker/volumes/school_app_storage/_data/backups ./
```

Automating that upload to Spaces, or replacing the lot with Litestream, has not been built.

## The domain and TLS

`edubba.com.ua`, served over HTTPS. This matters more than usual here: a student's link is
`/t/:token`, that token is the only credential they have, and `docs/agent-rules.md` § Tokens calls it
a secret. Over plain HTTP it travels in cleartext in the request path, readable by anyone on the same
classroom Wi-Fi. There is no HTTP-only mode to fall back to.

Four settings carry it, and they only work as a set:

| Where | Setting | Without it |
| --- | --- | --- |
| `config/deploy.yml` | `proxy.ssl: true`, `proxy.host` | no certificate; plain HTTP on port 80 |
| `production.rb` | `config.assume_ssl` | Rails reads every request as insecure: `http://` URLs in mail, session cookie without `secure` |
| `production.rb` | `config.force_ssl` | an `http://` link stays on `http://` |
| `production.rb` | `config.hosts` | any `Host` header is answered — DNS rebinding |

Both `ssl_options` and `host_authorization` exclude `/up`, because kamal-proxy health-checks the
container over plain HTTP with the container's own `Host`. A redirect or a rejection there is a failed
health check, and a failed health check is a failed deploy.

The certificate is obtained and renewed by kamal-proxy itself. It needs the A record from § 1b to
resolve before the first deploy, and port 80 to stay open for the renewal challenge.

Adding `www` later is three edits in one change: the DNS record, `proxy.host`, and `config.hosts`.
Let's Encrypt certifies every name in `proxy.host`, so one without a record fails the challenge for
all of them.

## Known gaps

- **Password reset does not work in production.** `PasswordsMailer` has no SMTP settings.
  `config.action_mailer.default_url_options` now points at the real domain, so links would be correct
  once mail is configured — but nothing is delivered until then, and the form still tells the teacher
  it sent something. A locked-out teacher gets back in with `bin/rails teacher:create` (a new account)
  or `bin/kamal console`.
- **No error tracking or uptime monitoring.** A 500 during a lesson is visible only in `bin/kamal logs`.
- **Build time.** Every deploy pays a cold `bundle install` (~2 min) because the runner keeps nothing
  between runs. Registry-backed layer caching (`builder.cache`) would fix it but needs a
  `docker-container` buildx driver configured on the runner first.
