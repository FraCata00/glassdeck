import 'vuetify/styles'
import { createVuetify } from 'vuetify'
import { aliases, mdi } from 'vuetify/iconsets/mdi-svg'

/// Two themes, because the page alternates between black and near-white
/// sections the way an Apple product page does, and Vuetify components need to
/// know which ground they are sitting on. Sections opt in with `v-theme-*`.
const shared = {
  primary: '#0071e3',   // the blue Apple uses for actions
  accent: '#5fd8ff',    // the cyan of the GlassDeck arc
  violet: '#a78bff',    // the violet it fades into
}

export default createVuetify({
  // SVG paths rather than the icon webfont: the font is 3.6 MB of glyphs and
  // 600 kB of CSS for the dozen icons this page uses, and only the paths that
  // are imported survive the bundle.
  icons: { defaultSet: 'mdi', aliases, sets: { mdi } },
  theme: {
    defaultTheme: 'deck',
    themes: {
      deck: {
        dark: true,
        colors: {
          ...shared,
          background: '#000000',
          surface: '#111113',
          'on-background': '#f5f5f7',
          'on-surface': '#f5f5f7',
        },
      },
      deckLight: {
        dark: false,
        colors: {
          ...shared,
          background: '#fbfbfd',
          surface: '#ffffff',
          'on-background': '#1d1d1f',
          'on-surface': '#1d1d1f',
        },
      },
    },
  },
  defaults: {
    VBtn: {
      rounded: 'pill',
      elevation: 0,
      class: 'text-none',
    },
    VCard: {
      elevation: 0,
      rounded: 'xl',
    },
  },
})
