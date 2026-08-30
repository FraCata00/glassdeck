<script setup>
import { repo } from '@/data/content'
import icon from '#images/icon.png'

const links = [
  { label: 'Source', href: repo },
  { label: 'Releases', href: `${repo}/releases` },
  { label: 'Changelog', href: `${repo}/blob/main/CHANGELOG.md` },
  { label: 'Issues', href: `${repo}/issues` },
  { label: 'License', href: `${repo}/blob/main/LICENSE` },
]
</script>

<template>
  <footer class="footer">
    <div class="deck-measure-wide footer__inner">
      <div class="footer__brand">
        <v-img :src="icon" width="28" height="28" alt="" class="footer__icon" />
        <div>
          <p class="deck-body footer__name">GlassDeck</p>
          <p class="deck-caption deck-dim">A menu bar system monitor for macOS.</p>
        </div>
      </div>

      <nav class="footer__links" aria-label="Project links">
        <a v-for="link in links" :key="link.label" :href="link.href" target="_blank" rel="noopener">
          {{ link.label }}
        </a>
      </nav>
    </div>

    <v-divider class="footer__rule" />

    <div class="deck-measure-wide footer__legal">
      <p class="deck-caption deck-dim">
        MIT licensed. Not affiliated with Apple Inc. Apple, Mac, macOS, MacBook Pro and Touch Bar
        are trademarks of Apple Inc.
      </p>
      <p class="deck-caption deck-dim">© {{ new Date().getFullYear() }} Francesco Cataldo</p>
    </div>
  </footer>
</template>

<style scoped>
.footer {
  background: #000;
  padding-block: 56px 44px;
}

.footer__inner {
  display: flex;
  flex-wrap: wrap;
  gap: 28px;
  align-items: center;
  justify-content: space-between;
}

.footer__brand {
  display: flex;
  align-items: center;
  gap: 13px;
}

.footer__icon {
  border-radius: 7px;
  flex: none;
}

.footer__name {
  color: var(--deck-ink);
  font-weight: 600;
  margin-bottom: 2px;
}

.footer__links {
  display: flex;
  flex-wrap: wrap;
  gap: 26px;
}

.footer__links a {
  color: var(--deck-ink-dim);
  text-decoration: none;
  font-size: 0.8125rem;
  transition: color 0.2s ease;
}

.footer__links a:hover {
  color: var(--deck-ink);
}

.footer__rule {
  margin-block: 34px;
  border-color: rgba(255, 255, 255, 0.09) !important;
}

.footer__legal {
  display: flex;
  flex-wrap: wrap;
  gap: 10px 28px;
  justify-content: space-between;
}
</style>
