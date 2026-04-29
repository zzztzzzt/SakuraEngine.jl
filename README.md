# SakuraEngine.jl

![GitHub last commit](https://img.shields.io/github/last-commit/zzztzzzt/SakuraEngine.jl.svg)
![GitHub repo size](https://img.shields.io/github/repo-size/zzztzzzt/SakuraEngine.jl.svg)

<br>

<img src="https://github.com/SakuraAxis/SakuraEngine.jl/blob/main/logo/logo.webp" alt="sakura-engine-logo" style="height: 280px; width: auto;" />

### SakuraEngine - Julia SSR Template Engine with Vue Hydration.

IMPORTANT : This project is still in the development and testing stages, licensing terms may be updated in the future. Please don't do any commercial usage currently.

## Project Dependencies Guide

[![Julia](https://img.shields.io/badge/Julia-9558B2?style=for-the-badge&logo=julia&logoColor=white)](https://github.com/JuliaLang/julia)
[![Vue3](https://img.shields.io/badge/vue3-4FC08D?style=for-the-badge&logo=vuedotjs&logoColor=white)](https://github.com/vuejs/core)
[![Tailwind CSS](https://img.shields.io/badge/tailwind_css-06B6D4?style=for-the-badge&logo=tailwindcss&logoColor=white)](https://github.com/tailwindlabs/tailwindcss)
[![vite](https://img.shields.io/badge/vite-646CFF?style=for-the-badge&logo=vite&logoColor=white)](https://github.com/vitejs/vite)

## How To Use

### Follow below example file, or directly test it :

```shell
julia --project=. scripts/render_hydration_example.jl
```

```julia
using SakuraEngine

root_dir = joinpath(@__DIR__, "..")
input_path = joinpath(root_dir, "template_example", "hydration_example.sk")
vue_project_dir = joinpath(root_dir, "sakura-vue")
output_ts_dir = joinpath(vue_project_dir, "src", "sakura")

println(">>> Sakura-SFC Pipeline Start")

init_frontend(vue_project_dir)

# 1. Export Vue assets ( logic and templates )
export_assets(input_path, output_ts_dir)
println(">>> Vue assets exported to: $output_ts_dir")

# 2. Using Node.js for SSR rendering
println(">>> Executing Node.js SSR...")
vue_html = cd(vue_project_dir) do
    read(`npx.cmd tsx scripts/render-vue-panel.ts`, String)
end


# 3. Render the final HTML with hydration data
final_html = render_file(input_path; vue_ssr=vue_html)

# 4. Output preview
output_index = joinpath(vue_project_dir, "index.html")
write(output_index, final_html)
println(">>> Success! Hydrated HTML saved to : $output_index")

println("||||||  Run Below To Test  ||||||")
println("cd sakura-vue")
println("npm run dev")
```

## Template ( SK SSR mix Vue3 Hydration )

```html
#= Julia script =#
<sk-script>
title = "Sakura mix Vue SFC"
user_name = "Sakura"
show_server_hello = true
disable_increment = false
initial_count = 5
server_tags = ["ssr", "hydration", "sfc"]
todos = [
    Dict("id" => 1, "label" => "Setup Sakura-SFC ", "done" => true),
    Dict("id" => 2, "label" => "Enjoy Single File Dev ", "done" => false),
]
pending_count = count(todo -> !todo["done"], todos)
</sk-script>

#= TypeScript / Vue Logic =#
<script type="sk-ts">
interface Todo {
  id: number;
  text: string;
  done: boolean;
}

interface ServerTag {
  id: string;
  name: string;
}

const title = ref<string>({{|| title ||}})
const user = ref<string>({{|| user_name ||}})
const count = ref<number>({{|| initial_count ||}})
const todos = ref<Todo[]>({{|| todos ||}})
const serverTags = ref<ServerTag[]>({{|| server_tags ||}})

const ready = ref<boolean>(false)

const pending = computed((): number => {
  return todos.value.filter((t: Todo) => !t.done).length
})

onMounted(() => {
  ready.value = true
})

return { title, user, count, todos, serverTags, ready, pending }
</script>

<script type="module" src="/src/entry-client.ts"></script>

#= Template Area ( SSR + Vue Hydration ) =#
<sk-template>
<section id="vue-panel">
  <h1>{{ title }}</h1>
  <p>Server : {{|| user_name ||}} / Client : {{ user }}</p>
  <p
    sk-if="show_server_hello"
  >
    Hello from SakuraEngine server side
  </p>
  
  <p v-if="ready">Client Pending : {{ pending }}</p>
  <p v-else>Server Pending : {{|| pending_count ||}}</p>

  <button @click="count++">
    Count: {{ count }}
  </button>

  <h3>Tags ( Hybrid List )</h3>
  <ul>
    #= sk-for for SEO, v-for for Reactivity =#
    <li
      sk-for="tag in server_tags"
      v-for="tag in serverTags"
      :key="tag"
    >
      tag = {{ tag }}
    </li>
  </ul>

  <h3>Todos</h3>
  <ul>
    <li
      sk-for="todo in todos"
      v-for="todo in todos"
      :key="todo.id"
    >
      <span
        :style="{ textDecoration: todo.done ? 'line-through' : 'none' }"
      >
        {{ todo.label }}
      </span>
      <button
        @click="todo.done = !todo.done"
      >Toggle</button>
    </li>
  </ul>

  <p>Status : All zones are now hydrated and reactive via Sakura-SFC.</p>
</section>
</sk-template>
```

## Project Detail / Debug
### Current Mixed Template Rules

SakuraEngine uses a two-phase template pipeline for Vue 3 style hydration :

1. Server phase :
   `sk-if`, `sk-else-if`, `sk-else`, `sk-for`, `sk-bind:*`, and `{{|| expr ||}}`
   are executed by SakuraEngine on the server first.
2. Client phase :
   Vue directives and Vue interpolation such as `v-if`, `v-else-if`, `v-else`,
   `v-for`, `v-model`, `@click`, `:prop`, and `{{ expr }}` are preserved in the
   rendered HTML for Vue 3 to process on the client.

Top-level sibling blocks are also allowed :

- `<sk-script>` provides Julia server context
- `<script type="application/json">` and `<script type="module">` may live at
  the same level as `<sk-template>`
- top-level sibling scripts are preserved in output
- `{{|| expr ||}}` inside those sibling scripts is rendered by SakuraEngine
- Vue syntax inside sibling scripts is left untouched

### Directive Ownership

- `{{|| expr ||}}` is server interpolation only.
- `{{ expr }}` is Vue interpolation only.
- `sk-*` directives own the server structural pass.
- `v-*` directives own the client reactive pass.

### Execution Order

- `sk-for` runs before `sk-if`, matching the current transformer priority.
- After SakuraEngine expands or removes nodes, the remaining template is passed
  forward with Vue syntax intact.
- This means Vue only sees the post-`sk-*` DOM shape.

### Mixing Strategy

Allowed and recommended :

- `sk-for` wrapping markup that still contains `v-if`, `v-model`, `@click`, or `{{ }}`
- `sk-if` gating a Vue-owned section
- `{{|| expr ||}}` and `{{ expr }}` in the same file, as long as each side owns
  its own data source

Use caution :

- Putting `sk-for` and `v-for` on the same element
- Putting `sk-if` and `v-if` on the same element

When both appear on the same element, SakuraEngine now keeps the Vue directive
but executes the `sk-*` directive first and emits a warning during the server
transform pass.

## Project Dependencies Details

Vue3 License : [https://github.com/vuejs/core/blob/main/LICENSE](https://github.com/vuejs/core/blob/main/LICENSE)
<br>

Tailwind CSS License : [https://github.com/tailwindlabs/tailwindcss/blob/main/LICENSE](https://github.com/tailwindlabs/tailwindcss/blob/main/LICENSE)
<br>

Vite License : [https://github.com/vitejs/vite/blob/main/LICENSE](https://github.com/vitejs/vite/blob/main/LICENSE)
