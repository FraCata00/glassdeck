<script setup>
import { ref } from 'vue'
import TouchBarStrip from './TouchBarStrip.vue'
import { touchBarStates } from '@/data/content'

/// The Touch Bar is the reason this app exists rather than being one more
/// menu bar monitor, so it gets the first section and the most room.
const current = ref(touchBarStates[0].id)
</script>

<template>
  <section id="touchbar" class="deck-section touchbar">
    <div class="deck-measure touchbar__head">
      <h2 class="deck-headline touchbar__title" v-reveal>
        The strip Apple gave up on,<br class="d-none d-sm-block" />
        finally worth looking at.
      </h2>
      <p class="deck-lead deck-dim touchbar__lead" v-reveal>
        Four sizes, and a rule: shrinking never makes GlassDeck disappear.
      </p>
    </div>

    <div class="deck-measure-wide" v-reveal>
      <v-tabs
        v-model="current"
        color="accent"
        density="comfortable"
        class="touchbar__tabs"
        align-tabs="center"
        show-arrows
      >
        <v-tab v-for="state in touchBarStates" :key="state.id" :value="state.id" class="touchbar__tab">
          {{ state.name }}
        </v-tab>
      </v-tabs>

      <v-window v-model="current" class="touchbar__window">
        <v-window-item v-for="state in touchBarStates" :key="state.id" :value="state.id">
          <TouchBarStrip :src="state.image" :alt="state.alt" />

          <div class="touchbar__caption">
            <h3 class="deck-title">{{ state.title }}</h3>
            <p class="deck-body deck-dim">{{ state.body }}</p>
            <p class="deck-caption touchbar__reach">{{ state.reach }}</p>
          </div>
        </v-window-item>
      </v-window>
    </div>
  </section>
</template>

<style scoped>
.touchbar__head {
  text-align: center;
  margin-bottom: clamp(3rem, 6vw, 4.5rem);
}

.touchbar__title {
  color: var(--deck-ink);
  margin-bottom: 20px;
}

.touchbar__lead {
  max-width: 620px;
  margin-inline: auto;
}

.touchbar__tabs {
  margin-bottom: clamp(2.5rem, 5vw, 3.5rem);
}

.touchbar__tab {
  letter-spacing: -0.01em;
  font-size: 0.9375rem;
}

.touchbar__window {
  overflow: visible;
}

.touchbar__caption {
  max-width: 600px;
  margin: clamp(2.5rem, 5vw, 3.5rem) auto 0;
  text-align: center;
}

.touchbar__caption h3 {
  color: var(--deck-ink);
  margin-bottom: 12px;
}

/* How you reach this size, kept quiet: it matters once, when you first try it. */
.touchbar__reach {
  margin-top: 18px;
  color: #6e6e73;
}
</style>
