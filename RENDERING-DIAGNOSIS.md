# Rendering & Asset Diagnosis Runbook

Operational notes for the renderer/deployer side of this repo. The
content side (KO mirror reviews, caption inheritance) lives in the
sibling `knowledge-base` repo at
`knowledge/methodology/ko-mirror-review.md`. **Read both. They cover
opposite ends of the same kind of bug report — "figures not
rendering" — and either side can be the actual cause.**

## Symptom: figures not rendering on the deployed site

A reader reports `그림이 안 보인다` or `Figure X 안 나옴` for one or
more docs. There are two non-overlapping classes of cause:

- **Content-side: caption inheritance.** The image renders, but the
  figure caption is in English in an otherwise-Korean doc and the
  reader perceives the figure as content they cannot follow. See
  `knowledge-base/knowledge/methodology/ko-mirror-review.md`
  §"What to flag" → "Caption inheritance".
- **Renderer-side: emit/serve bug.** The HTML actually emits a broken
  `<img>` tag, or the server resolves the relative path wrong, or
  the asset is genuinely missing from the build output. This runbook
  covers this side.

The diagnosis chain in `ko-mirror-review.md` Stage 1 (caption
check) terminates the majority of reports cheaply. When Stage 1
fails and the report is still active, run the chain below.

## Diagnosis chain

Run in order. Stop at the first stage that explains the report.

```
Stage A. Verify the source markdown has the right ref.
   In knowledge-base/, grep the source markdown for `![Figure`
   near the reported figure. Is the path correct relative to the
   doc, and does the asset file actually exist on disk?
     YES → continue to Stage B.
     NO  → fix the source. This is a content bug, not a renderer bug.

Stage B. Verify the build output emits the right <img src="...">.
   In this repo, after a `bash deploy.sh refresh`:
     grep -E '<img[^>]*\.assets' public/<lang>/<path>/<doc>.html
   The src should be `./<doc>.assets/<file>.png` (a bare relative
   path). NOT `../../../<doc>.assets/...`. The `../../../` form is
   the 2026-05-09 bug pattern — see "Pitfall 1" below.
     CORRECT (./ prefix) → continue to Stage C.
     WRONG (../../../)   → this is the markdownLinkResolution bug.
                            See "Pitfall 1: shortest-path image
                            resolution" below.

Stage C. Verify the asset file exists at the emitted location.
   The src `./<doc>.assets/<file>.png` resolves against the page's
   directory. So the asset must exist at:
     public/<lang>/<path>/<doc>.assets/<file>.png
   Check it. If the symlink in the kb side broke during prebuild,
   or the rsync excludes too aggressively, it will be missing here.
     PRESENT → continue to Stage D.
     MISSING → check prebuild.sh's --copy-unsafe-links flag and the
               kb-side symlink (knowledge/ko/<...>/<doc>.assets ->
               ../../../code-analysis/<...>/<doc>.assets).

Stage D. Test the BROWSER-RESOLVED URL, not the absolute asset URL.
   This is the most common diagnosis trap (Pitfall 2 below).
   The browser computes the asset URL by resolving the <img src>
   relative to the page URL. To replicate what the browser does:
     curl -s -o /dev/null -w '%{http_code}\n' \
       "<page-url>/../<src-without-leading-./>"
   Or just hit the resolved asset path directly:
     # Page is at /ko/code-analysis/cubrid/cubrid-lock-manager (no slash, file-shaped)
     # img src is ./cubrid-lock-manager.assets/01-oid-layout.png
     # Browser resolves to /ko/code-analysis/cubrid/cubrid-lock-manager.assets/01-oid-layout.png
     curl -s -o /dev/null -w '%{http_code}\n' \
       "http://localhost:9090/ko/code-analysis/cubrid/cubrid-lock-manager.assets/01-oid-layout.png"
     ALL 200 → continue to Stage E. The renderer is healthy; the
                report is something else.
     ANY 404 → either the emit is wrong (back to Stage B) or the
                serve config redirects the page URL away from the
                form Quartz assumed (see Pitfall 3 below).

Stage E. Ask the reader to hard-refresh / clear cache.
   At this stage the server is healthy and the resolved URL serves
   200; the only remaining cause is browser cache from before the
   most recent rebuild. Hard-refresh resolves it.

Stage F. If the report persists past Stage E, request a screenshot
   plus the exact URL the reader is hitting, and the network panel
   for the failing image. The diagnosis stops being deterministic
   past this point and needs concrete evidence.
```

## Pitfalls (real bugs that produced misdiagnoses)

### Pitfall 1: `markdownLinkResolution: "shortest"` overprefixes image src

**Symptom.** Built HTML emits
`<img src="../../../<doc>.assets/<file>.png">` for every figure
on every doc with figures. The browser resolves `../../../X` from
a doc at depth-3 (e.g., `/ko/code-analysis/cubrid/`) and lands at
`/ko/X` or `/X`, neither of which exists.

**Root cause.** Quartz's `CrawlLinks` plugin with
`markdownLinkResolution: "shortest"` treats image references like
Obsidian wikilinks resolved at vault root. Even when the source
markdown writes a clean relative path
(`![alt](<doc>.assets/<file>.png)`), Quartz recomputes it to be
"vault-root-relative" and prepends one `../` per segment of page
depth — but the asset folder is *not* at vault root, it is a
sibling of the page.

**Fix.** Set `markdownLinkResolution: "relative"` in
`quartz.config.ts` `Plugin.CrawlLinks(...)`. This keeps the source
markdown's path as-is, which is already the correct relative form
since the asset folder sits next to the page. After the fix the
emit becomes `<img src="./<doc>.assets/<file>.png">`. Verify with
the curl loop in §"Verification recipe".

**History.** Landed in `79fbee8` on 2026-05-09 after misdiagnosis
in `bfa29cf` (see Pitfall 3).

### Pitfall 2: Testing absolute asset URLs instead of browser-resolved URLs

**Symptom.** A 200 from `curl <site>/<full-asset-path>` despite
figures being broken in the actual browser.

**Root cause.** Browsers resolve `<img src="...">` *relative to
the page URL*, not as absolute paths. If the emitted src is
wrong (Pitfall 1), the browser computes a different URL than the
absolute one a curl test hits. The asset file may exist at the
absolute URL and serve 200 there, while the browser-resolved URL
404s.

**The trap.** Skipping straight from "the asset file exists" to
"the rendering is fine" without ever simulating the browser's
URL resolution. Stage D of the chain above is the explicit
counter to this.

**History.** This is exactly what produced the wrong fix in
`bfa29cf`. The recovery in `79fbee8` was driven by adding the
browser-resolution test that would have caught the misdiagnosis
the first time.

### Pitfall 3: `trailingSlash` mode mismatch with image src style

**Symptom.** Some docs render figures, others don't, depending on
URL form. Or: switching `trailingSlash` between `true` and `false`
changes which docs break.

**Root cause.** Browser relative-path resolution is sensitive to
whether the page URL ends with `/`. With trailing slash the URL
is treated as a directory, without it as a file. Three `../`
climbs up from different starting points. Quartz's image-src
emit assumes a specific URL shape; if the serve mode redirects
to the other shape, the emit breaks.

**Resolution rule.** With `markdownLinkResolution: "relative"`,
the emitted src is bare (`./<doc>.assets/...`). For bare paths,
the file-shaped URL form (no trailing slash) is what works:
`/.../<doc>` resolves the relative path against `/.../`, giving
`/.../<doc>.assets/...` — correct.

**Configuration to keep.** `cleanUrls: true` and
`trailingSlash: false` in `scripts/serve-static.mjs`, paired with
`markdownLinkResolution: "relative"` in `quartz.config.ts`. These
three settings are co-dependent; do not change any one of them
in isolation without re-auditing every figure-bearing doc with
the curl loop in §"Verification recipe".

**History.** `bfa29cf` set `trailingSlash: true` based on a wrong
diagnosis; `79fbee8` reverted it and applied the actual fix in
`quartz.config.ts`.

## Verification recipe

After any change to `quartz.config.ts` or `scripts/serve-static.mjs`,
run this loop. It iterates every emitted `<img>` in every code-analysis
doc (EN + KO) and reports any that 404:

```bash
cd /data/hgryoo/knowledge-base-site
fail=0; pass=0
for tree in en ko; do
  for f in $(grep -rlE '<img[^>]*\.assets' public/$tree/code-analysis/*/*.html 2>/dev/null); do
    rel=${f#public/$tree/}; doc_dir=${rel%/*}
    for src in $(grep -oE 'src="\./[^"]+"' "$f" | sed -E 's/src="\.\///; s/"$//'); do
      url="http://localhost:9090/$tree/$doc_dir/$src"
      code=$(curl -s -o /dev/null -w "%{http_code}" "$url")
      if [ "$code" = "200" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $code $url"; fi
    done
  done
done
echo "==> pass=$pass fail=$fail"
```

Expected: `pass=N fail=0` where N is the total figure count
(54 as of 2026-05-09 across 9 cubrid docs in EN+KO).

If `fail > 0`, the chain in §"Diagnosis chain" applies. Start at
Stage B for each failing URL.

## Related docs

- `knowledge-base/knowledge/methodology/ko-mirror-review.md` — the
  content-side companion. Its diagnosis chain handles caption
  inheritance and other content-side smells. **Run it first when a
  reader reports `그림이 안 보인다`** — the majority of such reports
  are content-side, not renderer-side.
- `knowledge-base/knowledge/methodology/korean-translation.md` —
  defines the term-smell catalog including caption-inheritance,
  which is the content-side mirror of Pitfall 1 above.
- `quartz.config.ts` — current `markdownLinkResolution: "relative"`
  setting; do not flip back to `"shortest"` without re-running the
  verification recipe across every figure-bearing doc.
- `scripts/serve-static.mjs` — current `trailingSlash: false`
  setting; co-dependent with `markdownLinkResolution: "relative"`.
