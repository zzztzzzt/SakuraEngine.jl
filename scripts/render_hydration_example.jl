using SakuraEngine

# Usage : julia --project=. scripts/render_hydration_example.jl

input_path = joinpath(@__DIR__, "..", "template_example", "hydration_example.sk")
workspace_dir = joinpath(@__DIR__, "..", "sakura-vue", ".sakura")
base_html_path = joinpath(workspace_dir, "hydration_example.base.html")
state_path = joinpath(workspace_dir, "vue-panel-state.json")
preview_output_path = joinpath(@__DIR__, "..", "sakura-vue", "index.html")

mkpath(workspace_dir)

html = SakuraEngine.render_file(input_path)

state_match = match(r"""<script\s+type="application/json"\s+id="sk-hydration-state">(.*?)</script>"""s, html)
state_match === nothing && error("Could not find #sk-hydration-state in rendered HTML.")

state_json = strip(String(state_match.captures[1]))

write(base_html_path, html)
write(state_path, state_json)
write(preview_output_path, html)

println("Rendered base files :")
println("input  => " * input_path)
println("base   => " * base_html_path)
println("state  => " * state_path)
println("preview=> " * preview_output_path)
println("")
println("Next :")
println("1. cd sakura-vue")
println("2. npx tsx scripts/render-vue-panel.ts --state .sakura/vue-panel-state.json --out .sakura/vue-panel.ssr.html")
println("3. cd ..")
println("4. julia --project=. scripts/assemble_hydration_example.jl")
