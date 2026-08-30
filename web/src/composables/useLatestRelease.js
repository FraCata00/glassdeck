import { ref, onMounted } from 'vue'
import { repo } from '@/data/content'

/// The version shown on the page comes from GitHub rather than from a constant
/// here, so cutting a release does not leave the site quietly a version behind.
/// If the call fails — offline, rate-limited, blocked — the page keeps the
/// fallback and simply says nothing about the version.
const FALLBACK = '1.5.0'

export function useLatestRelease() {
  const version = ref(FALLBACK)
  const confirmed = ref(false)

  onMounted(async () => {
    try {
      const response = await fetch('https://api.github.com/repos/FraCata00/glassdeck/releases/latest', {
        headers: { Accept: 'application/vnd.github+json' },
      })
      if (!response.ok) return
      const { tag_name: tag } = await response.json()
      if (typeof tag !== 'string') return
      version.value = tag.replace(/^v/, '')
      confirmed.value = true
    } catch {
      // Keep the fallback; the download button points at /releases/latest
      // either way, so nothing on the page is broken by this.
    }
  })

  return { version, confirmed, repo }
}
