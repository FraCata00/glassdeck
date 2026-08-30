<script setup>
import { sources, repo } from '@/data/content'
import { mdiChevronRight } from '@mdi/js'

/// Two things worth saying plainly, which used to be behind accordions. An
/// accordion asks the reader to decide whether to open it; three sentences do
/// not need that ceremony.
const notes = [
  {
    title: 'The Control Strip needs private interfaces.',
    body: 'Apple never shipped a public way to put an item there, so GlassDeck takes the same route every Touch Bar utility takes — two DFRFoundation entry points and two private NSTouchBar selectors, all resolved at runtime. On a Mac without a Touch Bar, or a macOS that drops them, they degrade to no-ops.',
  },
  {
    title: 'The fans are read, never written.',
    body: 'Fan control means overriding the thermal management of a machine whose sensors you only partly understand, and the failure mode is hardware. It is out of scope by design, not by omission.',
  },
]
</script>

<template>
  <section id="how" class="deck-section how">
    <div class="deck-measure">
      <div class="how__head">
        <h2 class="deck-headline how__title" v-reveal>Where the numbers come from.</h2>
        <p class="deck-lead deck-dim how__lead" v-reveal="80">
          No shelling out, no polling another tool's output, no helper daemon, no root.
          Each metric is one call into an interface macOS already publishes.
        </p>
      </div>

      <v-table class="sources" v-reveal>
        <tbody>
          <tr v-for="[metric, source] in sources" :key="metric">
            <th scope="row" class="sources__metric">{{ metric }}</th>
            <td class="deck-mono sources__call">{{ source }}</td>
          </tr>
        </tbody>
      </v-table>

      <v-row class="how__notes">
        <v-col v-for="(note, index) in notes" :key="note.title" cols="12" md="6">
          <div v-reveal="index * 90">
            <h3 class="deck-body how__notetitle">{{ note.title }}</h3>
            <p class="deck-body deck-dim">{{ note.body }}</p>
          </div>
        </v-col>
      </v-row>

      <p class="deck-body how__source" v-reveal>
        <a :href="repo" target="_blank" rel="noopener" class="how__link">
          Read the source
          <v-icon size="small" :icon="mdiChevronRight" />
        </a>
      </p>
    </div>
  </section>
</template>

<style scoped>
.how {
  background: #000;
}

.how__head {
  text-align: center;
  margin-bottom: clamp(3.5rem, 7vw, 5rem);
}

.how__title {
  color: var(--deck-ink);
  margin-bottom: 20px;
}

.how__lead {
  max-width: 620px;
  margin-inline: auto;
}

.sources {
  background: transparent;
}

.sources :deep(td),
.sources :deep(th) {
  border-bottom-color: rgba(255, 255, 255, 0.07) !important;
  /* Vuetify sets `padding: 0 16px` on cells, which wins over a bare
     padding-block and collapses the rows to about twenty pixels. */
  padding-top: 16px !important;
  padding-bottom: 16px !important;
  vertical-align: top;
  height: auto !important;
}

.sources__metric {
  color: var(--deck-ink) !important;
  font-weight: 600;
  font-size: 0.9375rem !important;
  text-align: left;
  white-space: nowrap;
  width: 1%;
  padding-right: 32px !important;
}

.sources__call {
  color: var(--deck-ink-dim) !important;
  font-size: 0.8125rem !important;
  line-height: 1.5;
}

.how__notes {
  margin-top: clamp(3.5rem, 6vw, 5rem);
  row-gap: 2rem;
}

.how__notetitle {
  color: var(--deck-ink);
  font-weight: 600;
  margin-bottom: 8px;
}

.how__source {
  margin-top: clamp(3rem, 5vw, 4rem);
  text-align: center;
}

.how__link {
  color: #2997ff;
  text-decoration: none;
}

.how__link:hover {
  text-decoration: underline;
}
</style>
