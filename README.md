# Knowledge Base Site

Quartz v4 site that publishes selected portions of [hgryoo's personal
knowledge base](https://github.com/hgryoo/knowledge-base) as a static
website at <https://hgryoo.github.io/knowledge-base-site>.

The curated notes themselves live in the sibling `knowledge-base` repo;
this repo is the renderer/deployer.

## Layout

- `quartz/` — upstream Quartz engine (kept close to the v4 baseline so
  it can be rebased)
- `quartz.config.ts` — site config (title, theme, plugin pipeline,
  ignore patterns, public/local-full filter)
- `prebuild.sh` — copies `../knowledge-base/knowledge` into bilingual
  `content/en/` and `content/ko/` trees
- `scripts/generate_index.py` — generates `content/index.md` (landing
  page) from the per-doc frontmatter
- `scripts/serve-local.sh` — wraps prebuild + `quartz build --serve`
  for the local-full LAN deploy
- `.github/workflows/deploy.yml` — GitHub Pages build (checks out
  `hgryoo/knowledge-base`, runs `prebuild.sh`, then `quartz build`)

## Build modes

| Mode | Trigger | Scope |
|------|---------|-------|
| Public | default | Only the index page and `*/code-analysis/**` (see `WhitelistPaths` in `quartz.config.ts`) |
| Local-full | `QUARTZ_LOCAL_FULL=1` | Every curated doc, including `methodology/` |

## Local development

Requires Node 22 and a checkout of `hgryoo/knowledge-base` at
`../knowledge-base` relative to this repo.

```bash
npm ci
./scripts/serve-local.sh           # local-full mode, port 8080
PORT=9090 ./scripts/serve-local.sh
```

To preview exactly what GitHub Pages will serve:

```bash
bash prebuild.sh                   # public mode
npx quartz build --serve
```

Override the source tree with `SRC=/path/to/knowledge bash prebuild.sh`
(this is what CI does).

## Deployment

`main` pushes deploy to GitHub Pages via `.github/workflows/deploy.yml`.
A `repository_dispatch` of type `knowledge-base-push` from the
`knowledge-base` repo also triggers a rebuild so content edits ship
without requiring a commit here.

## Upstream

Forked from [jackyzha0/quartz](https://github.com/jackyzha0/quartz)
(MIT). See `LICENSE.txt` and the upstream docs at
<https://quartz.jzhao.xyz/> for engine-level configuration.
