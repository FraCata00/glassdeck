<script setup>
import SiteNav from './components/SiteNav.vue'
import HeroSection from './components/HeroSection.vue'
import TouchBarSection from './components/TouchBarSection.vue'
import MetricsSection from './components/MetricsSection.vue'
import PrinciplesSection from './components/PrinciplesSection.vue'
import HowSection from './components/HowSection.vue'
import InstallSection from './components/InstallSection.vue'
import SiteFooter from './components/SiteFooter.vue'
</script>

<template>
  <v-app theme="deck">
    <SiteNav />

    <v-main>
      <HeroSection />
      <TouchBarSection />
      <MetricsSection />
      <PrinciplesSection />
      <HowSection />
      <InstallSection />
      <SiteFooter />
    </v-main>
  </v-app>
</template>

<style>
/* Vuetify paints the app background; the page is black behind every section. */
.v-application {
  background: #000 !important;
}
</style>
