<!-- 段三：七个角色，每张卡点击进角色页（§一「七个角色 = 首页 7 卡 + 角色页」）。 -->
<script setup lang="ts">
import { withBase } from 'vitepress'
import type { HomeData } from './types'

defineProps<{ home: HomeData }>()
</script>

<template>
  <section id="roles" class="section" aria-labelledby="roles-title">
    <div class="wrap">
      <p class="kicker">{{ home.rolesKicker }}</p>
      <h2 id="roles-title">{{ home.rolesTitle }}</h2>
      <p class="lead">{{ home.rolesLead }}</p>
      <ul class="cards cards-roles">
        <li v-for="role in home.roles" :key="role.id" class="card role">
          <a class="role-link" :href="withBase(`/roles/${role.id}`)">
            <span class="role-kicker">
              <span>{{ role.name }}</span>
              <code class="role-id">{{ role.id }}</code>
            </span>
            <span class="role-duty" :title="role.duty">{{ role.duty }}</span>
          </a>
        </li>
      </ul>
    </div>
  </section>
</template>
