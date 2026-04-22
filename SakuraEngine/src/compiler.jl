#=
compiler.jl — File loading layer
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

    # Convert #= ... =# to <!-- ... --> in template
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
    render_file(path) -> String

Complete rendering process entry : read .sk file → split blocks → execute script →
parse template → apply instructions → render HTML → normalize whitespace.
"""
function render_file(path::String)
    isfile(path) || error("SakuraEngine [Compiler] : File not found `$path`")

    content = read(path, String)
    script, template = extract_blocks(content)
    mod = eval_script(script)
    html = render_template(template, mod)

    # Normalize extra blank lines
    html = replace(html, r"\n{3,}" => "\n\n")
    html = replace(html, r"\n\s*\n" => "\n")

    return strip(html)
end
