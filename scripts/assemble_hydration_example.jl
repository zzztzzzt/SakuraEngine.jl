using SakuraEngine

# Usage : julia --project=. scripts/assemble_hydration_example.jl

workspace_dir = joinpath(@__DIR__, "..", "sakura-vue", ".sakura")
base_html_path = joinpath(workspace_dir, "hydration_example.base.html")
panel_html_path = joinpath(workspace_dir, "vue-panel.ssr.html")
output_path = joinpath(@__DIR__, "..", "sakura-vue", "index.html")

isfile(base_html_path) || error("Base HTML not found: $base_html_path")
isfile(panel_html_path) || error("Vue panel HTML not found: $panel_html_path")

html = read(base_html_path, String)
panel_html = strip(read(panel_html_path, String))

panel_match = match(r"""(<section\b[^>]*id="vue-panel"[^>]*>)(.*?)(</section>)"""s, html)
panel_match === nothing && error("Could not find #vue-panel in base HTML.")

open_tag = String(panel_match.captures[1])
close_tag = String(panel_match.captures[3])

html = replace(html, panel_match.match => open_tag * panel_html * close_tag)
write(output_path, html)

println("Assembled :")
println("base   => " * base_html_path)
println("panel  => " * panel_html_path)
println("output => " * output_path)
println("")
println("Next :")
println("1. cd sakura-vue")
println("2. npm run dev")
