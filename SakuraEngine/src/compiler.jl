# Manually Validated by mmmssstttt-SakuraAxis 2026-05-29

#=
compiler.jl - File loading layer
It is responsible for reading .sk files, splitting <sk-script> / <sk-template> blocks,
executing scripts, and returning the final HTML.
=#

"""
    extract_blocks(content) -> (script::String, template::String)

Extract the contents of `<sk-script>` and `<sk-template>` from the .sk file string.
If either block is missing, return an empty string without throwing an error.
"""
function extract_blocks(content::String)
    script_match = match(r"<sk-script\b[^>]*>(.*?)</sk-script>"s, content)
    template_match = match(r"<sk-template\b[^>]*>(.*?)</sk-template>"s, content)

    script = script_match !== nothing ? script_match.captures[1] : ""
    template = template_match !== nothing ? template_match.captures[1] : ""

    if isempty(template)
        @warn "SakuraEngine [Compiler] : The <sk-template> block was not found; an empty string will be returned"
    end

    template = replace(template, r"#=(.*?)=#"s => s"<!--\1-->")

    return script, template
end

const SCRIPT_CACHE = Dict{UInt64, Module}()

"""
    eval_script(script) -> Module

"""
function eval_script(script::AbstractString)
    script_hash = hash(script)
    if haskey(SCRIPT_CACHE, script_hash)
        return SCRIPT_CACHE[script_hash]
    end
    
    mod_name = Symbol("SkScript_", string(script_hash, base=16))
    mod = Module(mod_name)

    try
        Core.eval(mod, :(using Base))
        ast = Base.Meta.parseall(script)
        Core.eval(mod, ast)

        SCRIPT_CACHE[script_hash] = mod
    catch e
        error("SakuraEngine [Compiler] : <sk-script> execution failed - $e")
    end

    return mod
end

"""
    render_server_fragment(fragment, mod) -> String

Render non-template top-level fragments with server interpolation only.
This is used for sibling `<script>` blocks or other top-level HTML that should
keep Vue syntax untouched while still allowing `{{|| expr ||}}`.
"""
function render_server_fragment(fragment::AbstractString, mod::Module)
    cleaned = replace(String(fragment), r"#=(.*?)=#"s => "")
    nodes = parse_interpolations(cleaned)
    return render_nodes(nodes, mod)
end

"""
    render_file(path; vue_ssr::String="") -> String

Complete rendering process entry : read .sk file, execute `<sk-script>`, render
`<sk-template>`, preserve top-level sibling content, and normalize whitespace.
If `vue_ssr` is provided, it will replace the content of the element with 
id `sk-hydration-area`.
"""
function render_file(path::String; vue_ssr::String="")
    isfile(path) || error("SakuraEngine [Compiler] : File not found `$path`")

    content = read(path, String)
    script, template = extract_blocks(content)
    mod = eval_script(script)
    rendered_template = render_template(template, mod)

    # If Vue SSR content is provided, perform injection
    if !isempty(vue_ssr)
        m = match(r"<section\b[^>]*id=\"sk-hydration-area\"[^>]*>", rendered_template)
        if m !== nothing
            start_pos = m.offset + sizeof(m.match) 
            
            depth = 1
            curr_pos = start_pos
            while depth > 0 && curr_pos <= sizeof(rendered_template)
                next_open = findnext("<section", rendered_template, curr_pos)
                next_close = findnext("</section>", rendered_template, curr_pos)
                
                if next_close === nothing
                    break
                end
                
                if next_open !== nothing && first(next_open) < first(next_close)
                    depth += 1
                    curr_pos = last(next_open) + 1
                else
                    depth -= 1
                    if depth == 0
                        rendered_template = rendered_template[1:start_pos-1] * vue_ssr * rendered_template[first(next_close):end]
                        break
                    end
                    curr_pos = last(next_close) + 1
                end
            end
        else
            @warn "SakuraEngine [Compiler] : `vue_ssr` provided but `id=\"sk-hydration-area\"` not found in template"
        end
    end

    has_vue_logic = occursin(r"<script\s+type=[\"']sk-ts[\"'][^>]*>"i, content)
    block_re = r"<sk-script\b[^>]*>.*?</sk-script>|<sk-template\b[^>]*>.*?</sk-template>|<script\s+type=[\"']sk-ts[\"'][^>]*>.*?</script>"si
    io = IOBuffer()
    pos = 1

    for m in eachmatch(block_re, content)
        if m.offset > pos
            write(io, render_server_fragment(content[pos:m.offset-1], mod))
        end

        if startswith(m.match, "<sk-template>")
            write(io, rendered_template)
        end

        pos = m.offset + length(m.match)
    end

    if pos <= lastindex(content)
        write(io, render_server_fragment(content[pos:end], mod))
    end

    html = String(take!(io))

    if has_vue_logic
        client_entry = get_config(:client_entry, "/src/entry-client.ts")
        script_tag = "\n<script type=\"module\" src=\"$client_entry\"></script>\n"

        body_close_idx = findlast("</body>", html)
        if body_close_idx !== nothing
            html = html[1:first(body_close_idx)-1] * script_tag * html[first(body_close_idx):end]
        else
            html *= script_tag
        end
    end

    html = replace(html, r"\n{3,}" => "\n\n")
    html = replace(html, r"\n\s*\n" => "\n")

    return strip(html)
end
