<script setup>
/// A Touch Bar screenshot presented as the hardware it belongs to.
///
/// The captures are 2008 × 60 — an extreme aspect ratio that looks like a
/// stray banner if it is dropped straight onto a page. Framing it in the
/// aluminium-and-black strip it came from is what makes it read as a product
/// shot rather than as a wide image.
defineProps({
  src: { type: String, required: true },
  alt: { type: String, required: true },
  glow: { type: Boolean, default: false },
})
</script>

<template>
  <figure class="strip" :class="{ 'strip--glow': glow }">
    <div class="strip__scroller">
      <div class="strip__bezel">
        <img :src="src" :alt="alt" class="strip__image" loading="lazy" decoding="async" />
      </div>
    </div>
  </figure>
</template>

<style scoped>
.strip {
  margin: 0;
  position: relative;
}

/* The coloured haze behind the bar, which is the app's own accent gradient. */
.strip--glow::before {
  content: '';
  position: absolute;
  inset: -60% -6% -90%;
  background: radial-gradient(
    58% 130% at 50% 50%,
    rgba(95, 216, 255, 0.26) 0%,
    rgba(167, 139, 255, 0.16) 42%,
    transparent 72%
  );
  filter: blur(26px);
  z-index: 0;
  pointer-events: none;
}

.strip__bezel {
  position: relative;
  z-index: 1;
  padding: 7px;
  border-radius: 13px;
  background: linear-gradient(180deg, #2a2a2e 0%, #17171a 100%);
  box-shadow:
    0 0 0 1px rgba(255, 255, 255, 0.08),
    0 18px 48px rgba(0, 0, 0, 0.55);
  overflow: hidden;
}

.strip__image {
  display: block;
  width: 100%;
  height: auto;
  border-radius: 6px;
  background: #000;
}

.strip__scroller {
  position: relative;
  z-index: 1;
}

@media (max-width: 700px) {
  .strip__scroller {
    overflow-x: auto;
    -webkit-overflow-scrolling: touch;
    scrollbar-width: none;
    /* Bleed to the screen edges so the bar reads as something you swipe. */
    margin-inline: -22px;
    padding-inline: 22px;
  }

  .strip__scroller::-webkit-scrollbar {
    display: none;
  }

  .strip__bezel {
    padding: 5px;
    border-radius: 10px;
    /* Below this the 60 px-tall capture is unreadable. */
    min-width: 680px;
  }
}
</style>
