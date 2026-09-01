import fullWidth from '#images/touchbar-full-width.png'
import compact from '#images/touchbar-compact.png'
import detail from '#images/touchbar-detail.png'
import mini from '#images/touchbar-mini.png'

/// Everything the page says about the app, in one place, so the copy can be
/// revised without going through the components.

export const repo = 'https://github.com/FraCata00/glassdeck'
export const latestRelease = `${repo}/releases/latest`
export const sponsors = 'https://github.com/sponsors/FraCata00'

/// The four Touch Bar states, in the order the ⌄ button steps through them.
export const touchBarStates = [
  {
    id: 'full',
    reach: '⤢ from compact',
    name: 'Full width',
    image: fullWidth,
    alt: 'GlassDeck across the full width of the Touch Bar, showing every metric',
    title: 'Every metric, edge to edge.',
    body: 'CPU, GPU, memory, disk, network, temperature, power, fan RPM and battery, each in its own panel. The panels are sized from the room the bar actually has, so turning a metric off widens the ones that remain instead of leaving a gap.',
  },
  {
    id: 'compact',
    reach: '⌄ from full width, or ⤢ from mini',
    name: 'Compact',
    image: compact,
    alt: 'GlassDeck beside the system Control Strip, showing four live graphs and the battery',
    title: 'Beside the Control Strip.',
    body: 'Four live graphs and the battery, with the system controls exactly where you left them. Put it on the left, in the centre, or right next to the Control Strip.',
  },
  {
    id: 'detail',
    reach: 'Tap any panel or the battery chip',
    name: 'One metric',
    image: detail,
    alt: 'The CPU panel expanded across the Touch Bar with its detailed readings',
    title: 'Tap a panel, get the whole story.',
    body: 'Any panel opens across the bar with the numbers behind its headline and its recent history — the user/system split for CPU, read and write for the disk, each fan and its rated range.',
  },
  {
    id: 'mini',
    reach: '⌄ from compact — and ✕ hands the bar back',
    name: 'Mini',
    image: mini,
    alt: 'GlassDeck as a small meter parked beside the Control Strip',
    title: 'Down to a meter.',
    body: 'The ⌄ button steps down one size at a time and stops here, so a single tap can never make GlassDeck vanish. Release the bar and the meter in the Control Strip brings it straight back.',
  },
]

/// The metrics, in the order the app declares them.
export const metrics = [
  {
    name: 'CPU',
    body: 'Total load, the user and system split, per-core bars grouped into Apple silicon’s performance and efficiency clusters, and load average.',
  },
  {
    name: 'GPU',
    body: 'Device, renderer and tiler utilisation with allocated video memory, read from the IOKit accelerator registry.',
  },
  {
    name: 'Memory',
    body: 'Used counted as app memory plus wired plus compressed — the same arithmetic Activity Monitor does — with swap alongside it.',
  },
  {
    name: 'Disk',
    body: 'Live read and write throughput on the graph, with the boot volume’s capacity kept in the caption.',
  },
  {
    name: 'Network',
    body: 'Up and down throughput across every active interface, scaled against the fastest rate your machine has actually reached.',
  },
  {
    name: 'Fans',
    body: 'Live RPM and each fan’s rated range, read from the SMC. Read-only: fan control is out of scope by design.',
  },
  {
    name: 'Temperature',
    body: 'CPU, GPU, battery and enclosure sensors, discovered by enumerating the SMC rather than guessing key names per model.',
  },
  {
    name: 'Power',
    body: 'What the machine is drawing right now, scaled against the rating of the adapter that is plugged in.',
  },
  {
    name: 'Battery',
    body: 'Charge, charging state, and the time left to full or empty.',
  },
]

/// The two cards that are not gauges. Kept apart from the metrics above
/// because the app keeps them apart: neither is a single fraction of a whole.
export const modules = [
  {
    name: 'Bluetooth',
    body: 'The charge of every paired device that reports one — earbuds split into left, right and case. A device that is not connected keeps publishing the level it was last seen at, so those rows are dimmed and marked rather than passed off as live.',
  },
  {
    name: 'Clock',
    body: 'As many time zones as you like, each with its own label and the offset from here, and one of them in the menu bar. Offsets are read at the instant, so a summer-time mismatch is never an hour out.',
  },
]

/// The four claims the app is really built on.
export const principles = [
  {
    title: 'No network access',
    body: 'GlassDeck never opens a socket. Nothing about your machine leaves it.',
  },
  {
    title: 'No root, no daemon',
    body: 'Every reading comes from a public kernel interface. Nothing is installed beside the app.',
  },
  {
    title: 'Light at rest',
    body: 'Under 1% of one core at the default cadence, measured over alternating runs rather than guessed at.',
  },
  {
    title: 'No Dock icon',
    body: 'It lives in the menu bar and on the Touch Bar. It is never a window you have to close.',
  },
]

/// Where each number actually comes from. The point of the section is that
/// nothing here shells out to another tool.
export const sources = [
  ['CPU', 'host_processor_info(PROCESSOR_CPU_LOAD_INFO), hw.perflevel*.logicalcpu, getloadavg'],
  ['GPU', 'IOAccelerator → PerformanceStatistics'],
  ['Memory', 'host_statistics64(HOST_VM_INFO64), vm.swapusage'],
  ['Disk', 'URLResourceValues + IOBlockStorageDriver → Statistics'],
  ['Network', 'getifaddrs → if_data counters'],
  ['Fans', 'AppleSMC user client (FNum, F<n>Ac/Mn/Mx), read-only'],
  ['Temperature', 'AppleSMC, keys discovered on the first sample'],
  ['Power', 'AppleSMC (PSTR and friends), adapter rating as full scale'],
  ['Battery', 'IOPSCopyPowerSourcesInfo'],
  ['Processes', 'libproc (proc_listpids, proc_pidinfo)'],
  ['Bluetooth', 'IOBluetoothDevice.pairedDevices(), asked only once the module is on'],
  ['Clock', 'Date and TimeZone — no interface at all'],
]
