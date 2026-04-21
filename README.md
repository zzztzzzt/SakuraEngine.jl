# SakuraEngine.jl

![GitHub last commit](https://img.shields.io/github/last-commit/zzztzzzt/SakuraEngine.jl.svg)
![GitHub repo size](https://img.shields.io/github/repo-size/zzztzzzt/SakuraEngine.jl.svg)

<br>

<img src="https://github.com/zzztzzzt/SakuraEngine.jl/blob/main/logo/logo.png" alt="sakura-engine-logo" style="height: 280px; width: auto;" />

### SakuraEngine - Julia SSR Template Engine with Vue Hydration.

IMPORTANT : This project is still in the development and testing stages, licensing terms may be updated in the future. Please don't do any commercial usage currently.

## Project Dependencies Guide

[![Julia](https://img.shields.io/badge/Julia-9558B2?style=for-the-badge&logo=julia&logoColor=white)](https://github.com/JuliaLang/julia)
[![Vue3](https://img.shields.io/badge/vue3-4FC08D?style=for-the-badge&logo=vuedotjs&logoColor=white)](https://github.com/vuejs/core)
[![Tailwind CSS](https://img.shields.io/badge/tailwind_css-06B6D4?style=for-the-badge&logo=tailwindcss&logoColor=white)](https://github.com/tailwindlabs/tailwindcss)
[![vite](https://img.shields.io/badge/vite-646CFF?style=for-the-badge&logo=vite&logoColor=white)](https://github.com/vitejs/vite)

## WIP Project SakuraEngine

### SK Template Example

```html
#= Julia Script =#
<sk-script>
x = 10
name = "Sakura"
score = 72

items = [1, 2, 3]
</sk-script>

<sk-template>
<div>
  <p>Hello {{ name }}</p>
  <p>{{ x + 5 }}</p>
</div>

#= sk-if / sk-else-if / sk-else chain =#
<div>
  <p sk-if="score >= 90">Grade A - Excellent!</p>
  <p sk-else-if="score >= 75">Grade B - Good.</p>
  <p sk-else-if="score >= 60">Grade C - Pass.</p>
  <p sk-else>Grade F - Failed.</p>
</div>

#= sk-for + nested sk-if / sk-else =#
<ul>
  <li sk-for="item in items">
    <span sk-if="item > 2">{{ item }} - big</span>
    <span sk-else-if="item == 2">{{ item }} - medium</span>
    <span sk-else>{{ item }} - small</span>
  </li>
</ul>
</sk-template>
```

## Project Dependencies Details

Vue3 License : [https://github.com/vuejs/core/blob/main/LICENSE](https://github.com/vuejs/core/blob/main/LICENSE)
<br>

Tailwind CSS License : [https://github.com/tailwindlabs/tailwindcss/blob/main/LICENSE](https://github.com/tailwindlabs/tailwindcss/blob/main/LICENSE)
<br>

Vite License : [https://github.com/vitejs/vite/blob/main/LICENSE](https://github.com/vitejs/vite/blob/main/LICENSE)