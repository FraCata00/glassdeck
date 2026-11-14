<script setup>
import { metrics } from '@/data/content'
</script>

<template>
  <!-- The one near-white section, the way an Apple page breaks a run of black.
       Deliberately typographic: no cards, no borders, no icons. -->
  <section id="metrics" class="deck-section metrics v-theme--deckLight">
    <div class="deck-measure metrics__head">
      <h2 class="deck-headline metrics__title" v-reveal>Everything, straight from the kernel.</h2>
      <p class="deck-lead deck-dim-dark metrics__lead" v-reveal>
        Nothing shells out to another tool, and nothing needs privileges.
      </p>
    </div>

    <div class="deck-measure">
      <v-row class="metrics__grid">
        <v-col v-for="metric in metrics" :key="metric.name" cols="12" sm="6" md="4">
          <div v-reveal>
            <h3 class="deck-title metric__name">{{ metric.name }}</h3>
            <p class="deck-body deck-dim-dark">{{ metric.body }}</p>
          </div>
        </v-col>
      </v-row>
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
  margin-bottom: clamp(3rem, 6vw, 4.5rem);
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
  row-gap: clamp(1rem, 3vw, 2rem);
}

.metric__name {
  color: var(--deck-ink-dark);
  margin-bottom: 6px;
}
</style>
