/// `v-reveal` — fades an element up as it scrolls into view.
///
/// One movement, no stagger: elements that arrive together settle together.
/// Cascading them a tenth of a second apart drew attention to the animation
/// rather than to what was animating.
///
/// One observer for the whole page rather than one per element, and each
/// element is unobserved once it has appeared: the animation plays on the way
/// down and does not replay on the way back up, which is how Apple's pages
/// behave. Honours `prefers-reduced-motion` by never hiding anything.
const reduced =
  typeof window !== 'undefined' &&
  window.matchMedia('(prefers-reduced-motion: reduce)').matches

let observer = null

function watcher() {
  if (observer) return observer
  observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue
        entry.target.classList.add('is-visible')
        observer.unobserve(entry.target)
      }
    },
    // Fire a little before the element is fully on screen, so the movement is
    // finishing as the reader arrives at it rather than starting then.
    { rootMargin: '0px 0px -12% 0px', threshold: 0.08 },
  )
  return observer
}

export default {
  mounted(el) {
    if (reduced || typeof IntersectionObserver === 'undefined') {
      el.classList.add('deck-reveal', 'is-visible')
      return
    }
    el.classList.add('deck-reveal')
    watcher().observe(el)
  },
  unmounted(el) {
    observer?.unobserve(el)
  },
}
