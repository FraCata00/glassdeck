<script setup>
import { metrics, modules } from '@/data/content'
</script>

<template>
  <!-- The one near-white section, the way an Apple page breaks a run of black.
       Deliberately typographic: no cards, no borders, no icons — whitespace and
       the column rhythm do the separating. -->
  <section id="metrics" class="deck-section metrics v-theme--deckLight">
    <div class="deck-measure metrics__head">
      <h2 class="deck-headline metrics__title" v-reveal>Nine readings, none of them guessed.</h2>
      <p class="deck-lead deck-dim-dark metrics__lead" v-reveal>
        Every metric comes from a public kernel interface. Nothing shells out to
        <span class="deck-mono">ps</span>, <span class="deck-mono">powermetrics</span> or
        <span class="deck-mono">ioreg</span>, and nothing needs privileges.
      </p>
    </div>

    <div class="deck-measure">
      <v-row class="metrics__grid">
        <v-col
          v-for="(metric, index) in metrics"
          :key="metric.name"
          cols="12"
          sm="6"
          md="4"
        >
          <div class="metric" v-reveal>
            <h3 class="deck-title metric__name">{{ metric.name }}</h3>
            <p class="deck-body deck-dim-dark">{{ metric.body }}</p>
          </div>
        </v-col>
      </v-row>

      <div class="metrics__modules" v-reveal>
        <p class="deck-caption metrics__label">And two cards that are not gauges</p>
        <v-row class="metrics__grid">
          <v-col v-for="module in modules" :key="module.name" cols="12" sm="6">
            <div class="metric">
              <h3 class="deck-title metric__name">{{ module.name }}</h3>
              <p class="deck-body deck-dim-dark">{{ module.body }}</p>
            </div>
          </v-col>
        </v-row>
      </div>

      <p class="deck-body deck-dim-dark metrics__note" v-reveal>
        Plus the busiest processes, sampled only while a window is open. In English and Italian,
        following the system language.
      </p>
    </div>
  </section>
</template>

<style scoped>
.metrics {
  background: #fbfbfd;
  color: var(--deck-ink-dark);
}

.metrics__head {
  text-align: center;
  margin-bottom: clamp(3.5rem, 7vw, 5.5rem);
}

.metrics__title {
  color: var(--deck-ink-dark);
  margin-bottom: 20px;
}

.metrics__lead {
  max-width: 640px;
  margin-inline: auto;
}

.metrics__grid {
  row-gap: clamp(1.5rem, 4vw, 3rem);
}

.metric__name {
  color: var(--deck-ink-dark);
  margin-bottom: 10px;
}

.metrics__modules {
  margin-top: clamp(3.5rem, 6vw, 4.5rem);
  padding-top: clamp(2.5rem, 5vw, 3.5rem);
  /* The only rule on the page: it is doing the work three paragraphs of
     explanation would otherwise have to do. */
  border-top: 1px solid rgba(0, 0, 0, 0.08);
}

.metrics__label {
  margin-bottom: clamp(1.5rem, 3vw, 2rem);
  text-transform: uppercase;
  letter-spacing: 0.06em;
  font-weight: 600;
  color: var(--deck-ink-dark-dim);
}

.metrics__note {
  max-width: 660px;
  margin: clamp(3.5rem, 6vw, 4.5rem) auto 0;
  text-align: center;
}
</style>
