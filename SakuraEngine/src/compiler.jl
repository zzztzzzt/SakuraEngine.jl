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
    script_match = match(r"<sk-script>(.*?)</sk-script>"s, content)
    template_match = match(r"<sk-template>(.*?)</sk-template>"s, content)

    script = script_match !== nothing ? script_match.captures[1] : ""
    template = template_match !== nothing ? template_match.captures[1] : ""

    if isempty(template)
        @warn "SakuraEngine [Compiler] : The <sk-template> block was not found; an empty string will be returned"
    end

    template = replace(template, r"#=(.*?)=#"s => s"<!--\1-->")

    return script, template
end

"""
    eval_script(script) -> Module

Execute the Julia code of `<sk-script>` in a separate module,
and post back the module for use by the rendering layer.
"""
function eval_script(script::AbstractString)
    mod = Module()
    try
        include_string(mod, script)
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
        pattern = r"(<section\b[^>]*id=\"sk-hydration-area\"[^>]*>)(.*?)(</section>)"s
        m = match(pattern, rendered_template)
        if m !== nothing
            open_tag = m.captures[1]
            close_tag = m.captures[3]
            # Replace the entire match with open_tag + vue_ssr + close_tag
            # Note : We assume vue_ssr is the inner content or we handle it accordingly.
            # Actually, Vue SSR renderToString often returns the root element too.
            # If vue_ssr already contains the root tag, we might need to be careful.
            # But according to assemble_hydration_example.jl, it replaces the inner part.
            
            # Let's follow the logic in assemble_hydration_example.jl:
            rendered_template = replace(rendered_template, m.match => open_tag * vue_ssr * close_tag)
        else
            @warn "SakuraEngine [Compiler] : `vue_ssr` provided but `id=\"sk-hydration-area\"` not found in template"
        end
    end

    has_vue_logic = occursin(r"<script type=\"sk-ts\">"s, content)
    block_re = r"<sk-script>.*?</sk-script>|<sk-template>.*?</sk-template>|<script type=\"sk-ts\">.*?</script>"s
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
        html *= "\n<script type=\"module\" src=\"$client_entry\"></script>"
    end

    html = replace(html, r"\n{3,}" => "\n\n")
    html = replace(html, r"\n\s*\n" => "\n")

    return strip(html)
end
