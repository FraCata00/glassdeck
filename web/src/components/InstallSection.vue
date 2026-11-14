<script setup>
import CodeLine from './CodeLine.vue'
import { useLatestRelease } from '@/composables/useLatestRelease'
import { latestRelease } from '@/data/content'

const { version } = useLatestRelease()
</script>

<template>
  <section id="install" class="deck-section install v-theme--deckLight">
    <div class="deck-measure">
      <div class="install__head">
        <h2 class="deck-headline install__title" v-reveal>Get GlassDeck.</h2>
        <p class="deck-lead deck-dim-dark install__lead" v-reveal>
          Version {{ version }}. Free and MIT-licensed. macOS 15 or later, Apple silicon or Intel.
        </p>
      </div>

      <v-row align="stretch" class="install__row">
        <v-col cols="12" md="6">
          <!-- A terminal wants to look like a terminal. -->
          <div class="install__terminal" v-reveal>
            <p class="deck-title install__cardtitle">Homebrew</p>
            <CodeLine command="brew tap fracata00/tap" />
            <CodeLine command="brew trust fracata00/tap" />
            <CodeLine command="brew install --cask glassdeck" />
          </div>
        </v-col>

        <v-col cols="12" md="6">
          <div class="install__direct" v-reveal>
            <p class="deck-title install__cardtitle install__cardtitle--dark">Download</p>
            <p class="deck-body deck-dim-dark install__cardlead">
              Move <span class="deck-mono">GlassDeck.app</span> to Applications and right-click →
              <strong>Open</strong> the first time: it is signed ad hoc, not notarised.
            </p>
            <v-btn :href="latestRelease" target="_blank" rel="noopener" color="primary" variant="flat" size="large">
              Download {{ version }}
            </v-btn>
          </div>
        </v-col>
      </v-row>
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
  margin-bottom: 20px;
}

.install__cardtitle--dark {
  color: var(--deck-ink-dark);
  margin-bottom: 12px;
}

.install__cardlead {
  margin-bottom: 24px;
}
</style>
