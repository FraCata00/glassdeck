import fullWidth from '#images/touchbar-full-width.png'
import compact from '#images/touchbar-compact.png'
import detail from '#images/touchbar-detail.png'
import mini from '#images/touchbar-mini.png'

/// Everything the page says about the app, in one place, so the copy can be
/// revised without going through the components.

export const repo = 'https://github.com/FraCata00/glassdeck'
export const latestRelease = `${repo}/releases/latest`
export const sponsors = 'https://github.com/sponsors/FraCata00'

/// The four Touch Bar sizes, largest first.
export const touchBarStates = [
  {
    id: 'full',
    name: 'Full width',
    image: fullWidth,
    alt: 'GlassDeck across the full width of the Touch Bar, showing every metric',
    body: 'Every metric, fan RPM and the battery, edge to edge.',
  },
  {
    id: 'compact',
    name: 'Compact',
    image: compact,
    alt: 'GlassDeck beside the system Control Strip, showing four live graphs and the battery',
    body: 'Four graphs and the battery, with the system Control Strip left where it is.',
  },
  {
    id: 'detail',
    name: 'One metric',
    image: detail,
    alt: 'The CPU panel expanded across the Touch Bar with its detailed readings',
    body: 'Tap any panel for the numbers behind it and its recent history.',
  },
  {
    id: 'mini',
    name: 'Mini',
    image: mini,
    alt: 'GlassDeck as a small meter parked beside the Control Strip',
    body: 'Just the meters. Shrinking stops here, so a tap never makes GlassDeck vanish.',
  },
]

/// What the app reads, in the order it declares them.
export const metrics = [
  { name: 'CPU', body: 'Total, user and system, per-core bars by cluster, load average.' },
  { name: 'GPU', body: 'Utilisation and allocated video memory.' },
  { name: 'Memory', body: 'Used and swap, the way Activity Monitor counts them, with memory pressure.' },
  { name: 'Disk', body: 'Read and write throughput, and the boot volume’s capacity.' },
  { name: 'Network', body: 'Up and down across every active interface.' },
  { name: 'Fans', body: 'Live RPM and rated range, read from the SMC. Never written.' },
  { name: 'Temperature', body: 'CPU, GPU, battery and enclosure sensors.' },
  { name: 'Power', body: 'What the machine draws, against the adapter’s rating.' },
  { name: 'Battery', body: 'Charge, state, and time to full or empty.' },
  { name: 'Bluetooth', body: 'The charge of paired devices, earbuds split left, right and case.' },
  { name: 'Clock', body: 'Extra time zones, one of them in the menu bar if you like.' },
  { name: 'Processes', body: 'The busiest ones, sampled only while a window is open.' },
]

/// The claims the app is built on.
export const principles = [
  { title: 'No network access', body: 'Nothing about your machine leaves it.' },
  { title: 'No root, no daemon', body: 'Every reading comes from a public kernel interface.' },
  { title: 'Light at rest', body: 'Under 1% of one core at the default cadence.' },
  { title: 'No Dock icon', body: 'It lives in the menu bar and on the Touch Bar.' },
]
