module SakuraEngine

#=
SakuraEngine.jl — Module Entry Point

Loading Order :
ast.jl         — AST Node Type Definitions
parser.jl      — Template Parsing Layer
transformer.jl — Directive Transformation Layer (sk-* / v-*)
renderer.jl    — HTML Rendering Layer
compiler.jl    — File Loading Layer
=#

const SAKURA_CONFIG = Dict{Symbol, Any}(
    :client_entry => "/src/entry-client.ts"
)

function set_config(key::Symbol, value::Any)
    SAKURA_CONFIG[key] = value
end

function get_config(key::Symbol, default=nothing)
    return get(SAKURA_CONFIG, key, default)
end

include("ast.jl")
include("parser.jl")
include("transformer.jl")
include("renderer.jl")
include("compiler.jl")
include("pipeline.jl")

export render_file, render_template, set_config, export_assets

end # module SakuraEngine