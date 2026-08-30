<script setup>
import { ref } from 'vue'
import { mdiCheck, mdiContentCopy } from '@mdi/js'

/// A shell command with a copy button. The commands on this page exist to be
/// pasted, so the button is the point of the component rather than decoration.
const props = defineProps({
  command: { type: String, required: true },
  comment: { type: String, default: '' },
})

const copied = ref(false)
const failed = ref(false)

async function copy() {
  try {
    await navigator.clipboard.writeText(props.command)
    copied.value = true
    failed.value = false
    setTimeout(() => (copied.value = false), 1600)
  } catch {
    // Clipboard access can be refused (an insecure origin, a permission
    // policy). Say so instead of pretending it worked — the text is on screen
    // and can be selected by hand.
    failed.value = true
    setTimeout(() => (failed.value = false), 2600)
  }
}
</script>

<template>
  <div class="code-block">
    <div class="code-line">
      <code class="code-line__text deck-mono">
        <span class="code-line__prompt">$</span>
        {{ command }}
      </code>

      <v-btn
        :icon="copied ? mdiCheck : mdiContentCopy"
        variant="text"
        size="small"
        density="comfortable"
        class="code-line__copy"
        :aria-label="copied ? 'Copied' : `Copy: ${command}`"
        @click="copy"
      />

      <v-tooltip
        v-if="failed"
        activator="parent"
        text="Copy it by hand — the clipboard is not available here"
      />
    </div>

    <!-- Outside the command's own no-wrap scroll region, where it was cut off. -->
    <p v-if="comment" class="deck-caption code-line__comment">{{ comment }}</p>
  </div>
</template>

<style scoped>
.code-block + .code-block {
  margin-top: 12px;
}

.code-line {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 13px 8px 13px 18px;
  border-radius: 12px;
  background: rgba(255, 255, 255, 0.05);
}

.code-line__text {
  flex: 1;
  min-width: 0;
  font-size: 0.9375rem;
  line-height: 1.5;
  color: var(--deck-ink);
  overflow-x: auto;
  white-space: nowrap;
  scrollbar-width: thin;
}

.code-line__prompt {
  color: #6e6e73;
  user-select: none;
  margin-right: 6px;
}

.code-line__copy {
  color: var(--deck-ink-dim);
  flex: none;
}

.code-line__copy:hover {
  color: var(--deck-ink);
}

.code-line__comment {
  color: #6e6e73;
  margin: 8px 0 0 18px;
}
</style>
