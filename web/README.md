# The GlassDeck site

The product page, in Vue 3 and Vuetify 3. Published to GitHub Pages by
[`.github/workflows/pages.yml`](../.github/workflows/pages.yml) on every push to
`main` that touches `web/` or the screenshots.

```sh
cd web
npm install
npm run dev        # http://localhost:5173
npm run build      # dist/, built with base /glassdeck/
npm run preview
```

## What is where

```
web/
├── index.html                  # the shell, the <title> and the social cards
├── vite.config.js              # the /glassdeck/ base path and the #images alias
└── src/
    ├── App.vue                 # the section order, and nothing else
    ├── data/content.js         # every word the page says that is not layout
    ├── plugins/vuetify.js      # the two themes, dark and near-white
    ├── styles/main.css         # the type scale and the reveal animation
    ├── composables/
    │   ├── reveal.js           # the v-reveal directive
    │   └── useLatestRelease.js # the version, read from the GitHub API
    └── components/             # one file per section, plus two small pieces
```

## Two things worth knowing before editing

**The screenshots are not copied here.** `#images` is an alias onto
`../docs/images`, the same files the README shows, so there is one set to keep
current rather than two that drift. Vite hashes them into `dist/assets` at build
time.

The one exception is `public/icon.png`, which *is* a copy of
`docs/images/icon.png`. The favicon and the `og:image` are referenced from
`index.html` by a fixed URL, so they need a static file rather than a hashed
asset. If the app icon is ever regenerated, copy it across.

**The version is fetched, not hardcoded.** `useLatestRelease` asks the GitHub API
for the latest release so cutting a new one does not leave the page a version
behind. There is a fallback constant for when the call fails — it needs bumping
only if the API is unreachable for a long stretch, since the download button
points at `/releases/latest` either way.

## The look

No webfont is downloaded. Apple's SF Pro is not licensed for general web use, but
`-apple-system` *is* SF Pro on the Macs this app runs on, so the system stack
gives the real thing where it matters. Icons are `@mdi/js` SVG paths rather than
the icon font, which would have been 3.6 MB of glyphs and 600 kB of CSS for the
handful the page uses.
