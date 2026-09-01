<script setup>
import { principles } from '@/data/content'
</script>

<template>
  <section class="deck-section principles">
    <div class="deck-measure principles__head">
      <h2 class="deck-headline principles__title" v-reveal>
        It watches your Mac.<br />
        Nothing watches you.
      </h2>
    </div>

    <div class="deck-measure">
      <v-row>
        <v-col v-for="(item, index) in principles" :key="item.title" cols="12" sm="6" md="3">
          <div class="principle" v-reveal>
            <h3 class="deck-body principle__name">{{ item.title }}</h3>
            <p class="deck-body deck-dim">{{ item.body }}</p>
          </div>
        </v-col>
      </v-row>
    </div>
  </section>
</template>

<style scoped>
.principles {
  background: #000;
}

.principles__head {
  text-align: center;
  margin-bottom: clamp(3rem, 6vw, 4.5rem);
}

.principles__title {
  color: var(--deck-ink);
}

.principle {
  height: 100%;
  padding-right: 16px;
}

.principle__name {
  color: var(--deck-ink);
  font-weight: 600;
  margin-bottom: 8px;
}
</style>
