<script setup>
import CodeLine from './CodeLine.vue'
import { useLatestRelease } from '@/composables/useLatestRelease'
import { latestRelease, repo } from '@/data/content'

const { version } = useLatestRelease()

const requirements = [
  'macOS 15 or later — Liquid Glass surfaces need macOS 26; older systems get the material fallback',
  'Apple silicon or Intel',
  'A Touch Bar for the Touch Bar features; everything else works without one',
]
</script>

<template>
  <section id="install" class="deck-section install v-theme--deckLight">
    <div class="deck-measure">
      <div class="install__head">
        <h2 class="deck-headline install__title" v-reveal>Get GlassDeck.</h2>
        <p class="deck-lead deck-dim-dark install__lead" v-reveal="80">
          Version {{ version }}. Free, MIT-licensed, and about five megabytes.
        </p>
      </div>

      <v-row align="stretch" class="install__row">
        <v-col cols="12" md="6">
          <!-- The one boxed thing left on the page, because a terminal wants to
               look like a terminal. -->
          <div class="install__terminal" v-reveal>
            <p class="deck-title install__cardtitle">Homebrew</p>
            <p class="deck-body deck-dim install__cardlead">
              The recommended route: it clears the quarantine flag for you and upgrades along
              with everything else.
            </p>

            <CodeLine command="brew tap fracata00/tap" />
            <CodeLine command="brew trust fracata00/tap" comment="Homebrew asks this of every third-party tap" />
            <CodeLine command="brew install --cask glassdeck" />

            <p class="deck-caption install__after">
              Already have it? <span class="deck-mono">brew upgrade --cask glassdeck</span>, then quit
              and reopen GlassDeck — a running app keeps executing the binary it started with.
            </p>
          </div>
        </v-col>

        <v-col cols="12" md="6">
          <div class="install__direct" v-reveal="90">
            <p class="deck-title install__cardtitle install__cardtitle--dark">Direct download</p>
            <p class="deck-body deck-dim-dark install__cardlead">
              Move <span class="deck-mono">GlassDeck.app</span> to Applications, then right-click it
              and choose <strong>Open</strong> once — the build is signed ad hoc rather than
              notarised, which needs a paid developer account.
            </p>

            <v-btn
              :href="latestRelease"
              target="_blank"
              rel="noopener"
              color="primary"
              variant="flat"
              size="large"
            >
              Download {{ version }}
            </v-btn>

            <p class="deck-caption deck-dim-dark install__after">
              The SHA-256 is published beside the archive, so you can check what you got:
              <span class="deck-mono">shasum -a 256 GlassDeck.zip</span>
            </p>

            <p class="deck-caption install__reqtitle">Requirements</p>
            <p
              v-for="item in requirements"
              :key="item"
              class="deck-caption deck-dim-dark install__req"
            >
              {{ item }}
            </p>
          </div>
        </v-col>
      </v-row>

      <p class="deck-body install__source" v-reveal>
        Building it yourself is three lines —
        <span class="deck-mono">git clone</span>,
        <span class="deck-mono">Scripts/bundle.sh --universal</span>,
        <span class="deck-mono">open</span>.
        <a :href="repo" target="_blank" rel="noopener" class="install__link">The README has them.</a>
      </p>
    </div>
  </section>
</template>

<style scoped>
.install {
  background: #fbfbfd;
  color: var(--deck-ink-dark);
}

.install__head {
  text-align: center;
  margin-bottom: clamp(3rem, 6vw, 4rem);
}

.install__title {
  color: var(--deck-ink-dark);
  margin-bottom: 18px;
}

.install__lead {
  max-width: 540px;
  margin-inline: auto;
}

.install__row {
  row-gap: 3rem;
}

.install__terminal {
  height: 100%;
  padding: 32px 28px 34px;
  border-radius: 22px;
  background: #0b0b0d;
  color: var(--deck-ink);
}

.install__direct {
  height: 100%;
  padding-block: 32px;
}

.install__cardtitle {
  color: var(--deck-ink);
  margin-bottom: 12px;
}

.install__cardtitle--dark {
  color: var(--deck-ink-dark);
}

.install__cardlead {
  margin-bottom: 24px;
}

.install__after {
  margin-top: 22px;
  color: #6e6e73;
}

.install__reqtitle {
  margin-top: 34px;
  margin-bottom: 10px;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  font-weight: 600;
  color: var(--deck-ink-dark);
}

.install__req {
  margin-bottom: 6px;
}

.install__source {
  margin-top: clamp(3.5rem, 6vw, 4.5rem);
  text-align: center;
  color: var(--deck-ink-dark-dim);
}

.install__link {
  color: var(--deck-blue);
  text-decoration: none;
}

.install__link:hover {
  text-decoration: underline;
}
</style>
