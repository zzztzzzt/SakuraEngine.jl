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
