using SakuraEngine

root_dir = joinpath(@__DIR__, "..")
input_path = joinpath(root_dir, "template_example", "hydration_example.sk")
vue_project_dir = joinpath(root_dir, "sakura-vue")
output_ts_dir = joinpath(vue_project_dir, "src", "sakura")

# 1. Write the TypeScript required for the front-end
export_assets(input_path, output_ts_dir)

# 2. Call Node.js to execute the rendering script and capture its output string
vue_html = cd(vue_project_dir) do
    # Use `read` to capture standard output ( stdout )
    read(`npx.cmd tsx scripts/render-vue-panel.ts`, String)
end

# 3. Insert Vue SSR HTML into the Sakura template
final_html = render_file(input_path; vue_ssr=vue_html)

# 4. Output preview
output_index = joinpath(vue_project_dir, "index.html")
write(output_index, final_html)
println("Success! Hydrated HTML saved to : $output_index")