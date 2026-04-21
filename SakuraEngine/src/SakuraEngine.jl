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
    template = process_sk_for(template, mod)
    template = process_sk_if(template, mod)

    result = template
    for m in reverse(collect(eachmatch(r"\{\{(.*?)\}\}"s, template)))
        clean_expr = strip(m.captures[1])
        ex = Meta.parse(clean_expr)
        val = Core.eval(mod, ex)
        result = result[1:m.offset-1] * string(val) * result[m.offset+length(m.match):end]
    end

    return result
end

function render_file(path::String)
    content = read(path, String)
    script, template = extract_blocks(content)
    mod = eval_script(script)
    html = render_template(template, mod)

    # Clean up extra blank lines left after removing sk-if
    html = replace(html, r"\n{3,}" => "\n\n")
    # Replace multiple consecutive line breaks with a single line break
    html = replace(html, r"\n\s*\n" => "\n")
    return strip(html)
end

function process_sk_if(template::AbstractString, mod::Module)
    pattern = r"<(\w+)([^>]*)\s+sk-if=\"(.*?)\"([^>]*)>(.*?)</\1>"s

    prev = ""
    curr = String(template)

    while prev != curr
        prev = curr
        matches = collect(eachmatch(pattern, curr))
        # Replace from back to front to avoid displacement issues
        for m in reverse(matches)
            tag = m.captures[1]
            before_attrs = m.captures[2]
            condition_str = m.captures[3]
            after_attrs = m.captures[4]
            inner = m.captures[5]

            cond_expr = Meta.parse(condition_str)
            result_val = Core.eval(mod, cond_expr)

            if result_val
                combined_attrs = strip(string(before_attrs, " ", after_attrs))
                attr_str = isempty(combined_attrs) ? "" : " " * combined_attrs
                replacement = "<$tag$attr_str>$(strip(inner))</$tag>"
            else
                replacement = ""
            end

            curr = curr[1:m.offset-1] * replacement * curr[m.offset+length(m.match):end]
        end
    end

    return curr
end

function process_sk_for(template::AbstractString, mod::Module)
    pattern = r"<(\w+)([^>]*)\s+sk-for=\"(.*?) in (.*?)\"([^>]*)>(.*?)</\1>"s
    curr = String(template)

    while true
        m = match(pattern, curr)
        isnothing(m) && break

        tag = m.captures[1]
        before_attrs = m.captures[2]
        var_name = Symbol(strip(m.captures[3]))
        iterable_str = strip(m.captures[4])
        after_attrs = m.captures[5]
        inner = m.captures[6]

        iterable = Core.eval(mod, Meta.parse(iterable_str))
        result_html = ""

        for val in iterable
            Core.eval(mod, :($var_name = $val))

            processed_inner = process_sk_if(inner, mod)

            # process {{ }}
            processed_inner = replace(processed_inner, r"\{\{(.*?)\}\}"s => function(matched_str)
                expr_str = strip(match(r"\{\{(.*?)\}\}"s, matched_str).captures[1])
                ex = Meta.parse(expr_str)
                return string(Core.eval(mod, ex))
            end)

            combined_attrs = strip(string(before_attrs, " ", after_attrs))
            attr_str = isempty(combined_attrs) ? "" : " " * combined_attrs
            result_html *= "<$tag$attr_str>$(strip(processed_inner))</$tag>"
        end

        curr = curr[1:m.offset-1] * result_html * curr[m.offset+length(m.match):end]
    end

    return curr
end

end # module SakuraEngine
