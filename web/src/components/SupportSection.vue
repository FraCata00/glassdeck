<script setup>
import { mdiHeartOutline } from '@mdi/js'
import { sponsors } from '@/data/content'
</script>

<template>
  <!-- Deliberately the shortest band on the page. Asking for money is allowed to
       be visible; it is not allowed to be the loudest thing here, and the blue
       button stays reserved for the download. -->
  <section class="support">
    <div class="deck-measure support__inner">
      <p class="deck-body support__copy" v-reveal>
        GlassDeck is free, and stays free. If it has earned its place in your menu bar, you can
        sponsor the work on GitHub.
      </p>

      <v-btn
        :href="sponsors"
        target="_blank"
        rel="noopener"
        variant="outlined"
        size="large"
        class="support__button"
        :prepend-icon="mdiHeartOutline"
        v-reveal
      >
        Sponsor on GitHub
      </v-btn>
    </div>
  </section>
</template>

<style scoped>
.support {
  background: #000;
  padding-block: clamp(3.5rem, 7vw, 5rem);
  border-top: 1px solid rgba(255, 255, 255, 0.07);
}

.support__inner {
  display: flex;
  flex-wrap: wrap;
  gap: 20px 32px;
  align-items: center;
  justify-content: center;
  text-align: center;
}

.support__copy {
  color: var(--deck-ink-dim);
  max-width: 460px;
}

.support__button {
  color: var(--deck-ink);
  border-color: rgba(255, 255, 255, 0.24);
}

.support__button:hover {
  border-color: rgba(255, 255, 255, 0.45);
}
</style>
