<script setup>
import { mdiGithub, mdiMenu } from '@mdi/js'
import { ref } from 'vue'
import { repo } from '@/data/content'
import icon from '#images/icon.png'

/// The translucent bar that stays with you down the page. It is deliberately
/// short and quiet: on Apple's pages the navigation is the least prominent
/// thing on screen until you need it.
const links = [
  { label: 'Touch Bar', href: '#touchbar' },
  { label: 'Metrics', href: '#metrics' },
  { label: 'How it works', href: '#how' },
  { label: 'Install', href: '#install' },
]

const drawer = ref(false)
</script>

<template>
  <v-app-bar
    flat
    height="52"
    class="nav"
  >
    <div class="nav__inner deck-measure-wide">
      <a href="#top" class="nav__brand" aria-label="GlassDeck, back to top">
        <v-img :src="icon" width="22" height="22" alt="" class="nav__icon" />
        <span class="nav__name">GlassDeck</span>
      </a>

      <nav class="nav__links" aria-label="Sections">
        <a v-for="link in links" :key="link.href" :href="link.href" class="nav__link">
          {{ link.label }}
        </a>
      </nav>

      <div class="nav__actions">
        <v-btn
          :href="repo"
          target="_blank"
          rel="noopener"
          variant="text"
          size="small"
          class="nav__github"
          :prepend-icon="mdiGithub"
        >
          GitHub
        </v-btn>

        <v-btn
          href="#install"
          color="primary"
          size="small"
          variant="flat"
          class="nav__cta"
        >
          Download
        </v-btn>

        <v-btn
          :icon="mdiMenu"
          variant="text"
          size="small"
          class="nav__burger"
          aria-label="Open the section menu"
          @click="drawer = true"
        />
      </div>
    </div>
  </v-app-bar>

  <v-navigation-drawer v-model="drawer" location="right" temporary width="260" class="nav__drawer">
    <v-list nav density="comfortable">
      <v-list-item
        v-for="link in links"
        :key="link.href"
        :href="link.href"
        :title="link.label"
        @click="drawer = false"
      />
      <v-divider class="my-2" />
      <v-list-item
        :href="repo"
        target="_blank"
        rel="noopener"
        :prepend-icon="mdiGithub"
        title="GitHub"
      />
    </v-list>
  </v-navigation-drawer>
</template>

<style scoped>
.nav {
  background: rgba(0, 0, 0, 0.72) !important;
  backdrop-filter: saturate(180%) blur(20px);
  -webkit-backdrop-filter: saturate(180%) blur(20px);
  border-bottom: 1px solid rgba(255, 255, 255, 0.08);
}

.nav :deep(.v-toolbar__content) {
  padding-inline: 0;
}

.nav__inner {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 24px;
}

.nav__brand {
  display: flex;
  align-items: center;
  gap: 9px;
  text-decoration: none;
  color: var(--deck-ink);
  flex: none;
}

.nav__icon {
  border-radius: 6px;
  flex: none;
}

.nav__name {
  font-size: 0.9375rem;
  font-weight: 600;
  letter-spacing: -0.01em;
}

.nav__links {
  display: flex;
  align-items: center;
  gap: 30px;
  margin-inline: auto;
}

.nav__link {
  color: var(--deck-ink);
  opacity: 0.8;
  text-decoration: none;
  font-size: 0.8125rem;
  letter-spacing: -0.005em;
  transition: opacity 0.2s ease;
}

.nav__link:hover {
  opacity: 1;
}

.nav__actions {
  display: flex;
  align-items: center;
  gap: 8px;
  flex: none;
}

.nav__github {
  color: var(--deck-ink);
  opacity: 0.8;
  font-size: 0.8125rem;
}

.nav__github:hover { opacity: 1; }

.nav__burger { display: none; color: var(--deck-ink); }

@media (max-width: 860px) {
  .nav__links,
  .nav__github { display: none; }
  .nav__burger { display: inline-flex; }
  .nav__inner { gap: 12px; }
  .nav__actions { margin-left: auto; }
}

@media (max-width: 340px) {
  .nav__cta { display: none; }
}
</style>
