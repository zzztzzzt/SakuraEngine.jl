module SakuraEngine

export render_file, render_template

function extract_blocks(content::String)
    script_match = match(r"<sk-script>(.*?)</sk-script>"s, content)
    template_match = match(r"<sk-template>(.*?)</sk-template>"s, content)

    script = script_match !== nothing ? script_match.captures[1] : ""
    template = template_match !== nothing ? template_match.captures[1] : ""

    return script, template
end

function eval_script(script::AbstractString)
    mod = Module()
    
    # Use include_string to execute the entire string within the namespace of this module
    include_string(mod, script)

    return mod
end

function render_template(template::AbstractString, mod::Module)
    return replace(template, r"\{\{(.*?)\}\}"s => function(m)
        # Process Substring and remove {{ }}
        clean_expr = strip(m[3:end-2])
        
        # Parse the string into an expression
        ex = Meta.parse(clean_expr)
        
        # Execute within the specified mod module, and explicitly use Core.eval
        val = Core.eval(mod, ex)
        
        return string(val)
    end)
end

function render_file(path::String)
    content = read(path, String)

    script, template = extract_blocks(content)
    mod = eval_script(script)

    html = render_template(template, mod)

    return html
end

end # module SakuraEngine
