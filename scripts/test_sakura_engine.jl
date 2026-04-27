using SakuraEngine

# Usage : julia --project=. scripts/test_sakura_engine.jl

html = SakuraEngine.render_file("template_example/example.sk")

println(html)
