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

Create an Ubuntu LTS droplet. `s-1vcpu-2gb` (~$12/mo) is the comfortable size; `s-1vcpu-1gb` works
because images are built on the CI runner and the droplet only pulls them, but leaves little headroom
for `bin/rails console` alongside Puma and the Solid Queue supervisor.

Add your SSH key at creation time. Then, with a DigitalOcean Cloud Firewall or `ufw`, allow inbound
`22/tcp` and `80/tcp` only. Keep SSH open to any source: GitHub-hosted runners have no stable egress IP.

Put the droplet's public IPv4 address into `config/deploy.yml` under `servers.web`, replacing the
`203.0.113.10` placeholder. That file is the only place the address is configured — the deploy job reads
it back out to pin the host key.

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

Kamal resolves `env.secret` entries through `.kamal/secrets`, and the generated file reads the master
key off disk:

```sh
RAILS_MASTER_KEY=$(cat config/master.key)
```

`config/master.key` is gitignored, so on a CI runner that file does not exist and the deploy would ship
an empty key. Change the line to prefer the environment and keep the file as a local fallback:

```sh
RAILS_MASTER_KEY=${RAILS_MASTER_KEY:-$(cat config/master.key)}
```

The `KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD` line already reads from the environment and needs
no change.

### 5. Bootstrap the droplet, then let CI do the first deploy

`kamal deploy` assumes Docker is already installed on the server. Install it once from a machine that
has the repo and SSH access — this step builds nothing, so it is fast even on Apple Silicon:

```bash
KAMAL_REGISTRY_PASSWORD=unused bin/kamal server bootstrap
```

Then merge to `main`. The `deploy` job builds the image on an amd64 runner, pushes it to
`ghcr.io/yarov1/school-app`, boots `kamal-proxy`, and starts the app. `bin/docker-entrypoint` runs
`bin/rails db:prepare` on boot, which creates and migrates all four databases on the mounted volume.

The `Dockerfile` carries `LABEL org.opencontainers.image.source`, which is what attaches the published
package to this repository. Without that link GHCR creates the package unattached, and `GITHUB_TOKEN`
loses push access after the first deploy.

### 6. Make the package public

After the first successful push, the GHCR package is private and the droplet pulls it with the
workflow's `GITHUB_TOKEN`, which expires when the run ends. Set the package to public at
**github.com/users/yaroV1/packages → school-app → Package settings → Change visibility** so the droplet
can pull unauthenticated. The repository is already public, so this leaks nothing new.

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

The volume holds everything: the four databases and every Active Storage file. Destroying it destroys
the app's data, and nothing here is backed up yet.

Enable DigitalOcean droplet backups for a coarse, automatic floor. For a real database copy, SQLite's
online backup API is safe against a live, WAL-mode database:

```bash
bin/kamal app exec "sqlite3 /rails/storage/production.sqlite3 \".backup /rails/storage/backup.sqlite3\""
```

then copy it off the droplet with `scp`. **This is not automated.** A nightly cron plus an upload to
Spaces, or Litestream streaming to Spaces, is the obvious next step and has not been built.

## Adding a domain

Currently there is no domain and no TLS: `kamal-proxy` serves plain HTTP on port 80.

This matters more than usual for this app. Student links are `/t/:token`, the token is the only
credential a student has, and `docs/agent-rules.md` § Tokens calls it a secret. Over plain HTTP every
token travels in cleartext in the request path. **Do not run a real class on the IP-only setup.**

To fix it, in one change:

1. Point an A record at the droplet and open `443/tcp` on the firewall.
2. Uncomment the `proxy:` block in `config/deploy.yml` and set `host:`.
3. Uncomment `config.assume_ssl`, `config.force_ssl`, and `config.ssl_options` in
   `config/environments/production.rb`. Without `assume_ssl` Rails builds `http://` URLs and marks
   cookies non-secure behind the terminating proxy; the `ssl_options` exclusion keeps `/up` reachable
   over HTTP so the proxy's health check does not chase a redirect.
4. Optionally set `config.hosts` to the domain, with `config.host_authorization` excluding `/up`.

## Known gaps

- **Password reset does not work in production.** `PasswordsMailer` has no SMTP settings, and
  `config.action_mailer.default_url_options` still points at `example.com`, so reset links would be
  wrong even if mail were delivered. Configure both before relying on the flow.
- **No error tracking or uptime monitoring.**
- **Build time.** Every deploy pays a cold `bundle install` (~2 min) because the runner keeps nothing
  between runs. Registry-backed layer caching (`builder.cache`) would fix it but needs a
  `docker-container` buildx driver configured on the runner first.
