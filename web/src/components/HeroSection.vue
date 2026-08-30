<script setup>
import { mdiChevronRight } from '@mdi/js'
import TouchBarStrip from './TouchBarStrip.vue'
import { useLatestRelease } from '@/composables/useLatestRelease'
import { touchBarStates, latestRelease, repo } from '@/data/content'
import icon from '#images/icon.png'

const { version } = useLatestRelease()
const hero = touchBarStates[0]
</script>

<template>
  <section id="top" class="hero">
    <div class="hero__glow" aria-hidden="true" />

    <div class="deck-measure hero__copy">
      <v-img :src="icon" width="104" height="104" alt="" class="hero__icon" v-reveal />

      <h1 class="deck-display hero__title" v-reveal="60">
        Your Mac's vitals,<br />
        <span class="deck-gradient-text">in Liquid Glass.</span>
      </h1>

      <p class="deck-lead deck-dim hero__lead" v-reveal="140">
        A menu bar system monitor that reads your machine straight from the kernel — and,
        on a MacBook Pro that has one, puts it on the Touch Bar where you can actually
        glance at it.
      </p>

      <div class="hero__actions" v-reveal="220">
        <v-btn :href="latestRelease" target="_blank" rel="noopener" color="primary" size="large" variant="flat">
          Download for macOS
        </v-btn>
        <v-btn :href="repo" target="_blank" rel="noopener" size="large" variant="text" class="hero__link">
          View on GitHub
          <v-icon end size="small" :icon="mdiChevronRight" />
        </v-btn>
      </div>

      <p class="deck-caption deck-dim hero__meta" v-reveal="260">
        Version {{ version }} · macOS 15 or later · Apple silicon and Intel · Free and open source
      </p>
    </div>

    <div class="deck-measure-wide hero__shot" v-reveal="120">
      <TouchBarStrip :src="hero.image" :alt="hero.alt" glow />
    </div>
  </section>
</template>

<style scoped>
.hero {
  position: relative;
  padding-top: clamp(5.5rem, 12vw, 9rem);
  padding-bottom: clamp(4rem, 9vw, 7rem);
  overflow: hidden;
  text-align: center;
}

/* A single soft light behind the headline, the way a dark Apple hero is lit. */
.hero__glow {
  position: absolute;
  top: -22%;
  left: 50%;
  width: min(1100px, 130vw);
  aspect-ratio: 1.6;
  transform: translateX(-50%);
  background: radial-gradient(
    50% 50% at 50% 50%,
    rgba(64, 122, 255, 0.2) 0%,
    rgba(95, 216, 255, 0.1) 38%,
    transparent 70%
  );
  pointer-events: none;
}

.hero__copy {
  position: relative;
  z-index: 1;
}

.hero__icon {
  margin-inline: auto;
  margin-bottom: 30px;
  border-radius: 23%;
  filter: drop-shadow(0 16px 34px rgba(0, 0, 0, 0.55));
  flex: none;
}

.hero__title {
  color: var(--deck-ink);
  margin-bottom: 22px;
}

.hero__lead {
  max-width: 640px;
  margin-inline: auto;
  margin-bottom: 34px;
}

.hero__actions {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  justify-content: center;
  align-items: center;
}

.hero__link {
  color: #2997ff; /* Apple's link blue on dark grounds */
}

.hero__meta {
  margin-top: 22px;
}

.hero__shot {
  position: relative;
  z-index: 1;
  margin-top: clamp(3.5rem, 7vw, 6rem);
}
</style>
