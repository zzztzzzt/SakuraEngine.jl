module SakuraEngine

export render_file, render_template

abstract type Node end

struct TextNode <: Node
    content::String
end

struct InterpNode <: Node
    expr::Union{Expr, Symbol, Number}
end

struct IfNode <: Node
    cond::Expr
    children::Vector{Node}
end

struct ElementNode <: Node
    tag::String
    attrs::Dict{String,String}
    children::Vector{Node}
end

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

function inject_if_nodes(nodes::Vector{Node})
    new_nodes = Node[]

    for node in nodes
        if node isa ElementNode
            # find sk-if（ use attrs string hack first）
            push!(new_nodes, node)
        else
            push!(new_nodes, node)
        end
    end

    return new_nodes
end

function render_nodes(nodes::Vector{Node}, mod::Module)
    io = IOBuffer()

    for node in nodes
        if node isa TextNode
            write(io, node.content)

        elseif node isa InterpNode
            val = Core.eval(mod, node.expr)
            write(io, string(val))

        elseif node isa IfNode
            cond_val = Core.eval(mod, node.cond)
            if cond_val
                write(io, render_nodes(node.children, mod))
            end
        elseif node isa ElementNode
            write(io, "<", node.tag)
        
            # attrs（ currently null ）
            for (k, v) in node.attrs
                write(io, " $k=\"$v\"")
            end
        
            write(io, ">")
        
            write(io, render_nodes(node.children, mod))
        
            write(io, "</", node.tag, ">")
        end
    end

    return String(take!(io))
end

function render_template(template::AbstractString, mod::Module)
    template = process_sk_for(template, mod)

    nodes = parse_elements(template)

    nodes = inject_if_nodes(nodes)

    return render_nodes(nodes, mod)
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

function parse_interpolations(template::AbstractString)
    nodes = Node[]
    pattern = r"\{\{(.*?)\}\}"s

    last_idx = 1

    for m in eachmatch(pattern, template)
        start_idx = m.offset
        end_idx = m.offset + length(m.match) - 1

        # The preceding plain text
        if start_idx > last_idx
            text = template[last_idx:start_idx-1]
            push!(nodes, TextNode(text))
        end

        # {{ expression }}
        expr_str = strip(m.captures[1])
        ex = Meta.parse(expr_str)
        push!(nodes, InterpNode(ex))

        last_idx = end_idx + 1
    end

    # The remaining text
    if last_idx <= lastindex(template)
        push!(nodes, TextNode(template[last_idx:end]))
    end

    return nodes
end

function parse_sk_if_nodes(template::String)
    pattern = r"<(\w+)([^>]*)\s+sk-if=\"(.*?)\"([^>]*)>(.*?)</\1>"s

    nodes = Node[]
    last_idx = 1

    for m in eachmatch(pattern, template)
        start_idx = m.offset
        end_idx = m.offset + length(m.match) - 1

        # The preceding ordinary content
        if start_idx > last_idx
            text = template[last_idx:start_idx-1]
            append!(nodes, parse_interpolations(text))
        end

        # sk-if block
        cond_expr = Meta.parse(strip(m.captures[3]))
        inner = m.captures[5]

        # inner also needs to be parsed into nodes
        child_nodes = parse_interpolations(inner)

        push!(nodes, IfNode(cond_expr, child_nodes))

        last_idx = end_idx + 1
    end

    # The remaining part
    if last_idx <= lastindex(template)
        append!(nodes, parse_interpolations(template[last_idx:end]))
    end

    return nodes
end

function parse_elements(template::String)
    pattern = r"<(\w+)([^>]*)>(.*?)</\1>"s

    nodes = Node[]
    last_idx = 1

    for m in eachmatch(pattern, template)
        start_idx = m.offset
        end_idx = m.offset + length(m.match) - 1

        # The preceding text
        if start_idx > last_idx
            append!(nodes, parse_interpolations(template[last_idx:start_idx-1]))
        end

        tag = m.captures[1]
        attr_str = strip(m.captures[2])
        inner = m.captures[3]

        attrs = Dict{String,String}()

        children = parse_interpolations(inner)

        push!(nodes, ElementNode(tag, attrs, children))

        last_idx = end_idx + 1
    end

    # The remaining part
    if last_idx <= lastindex(template)
        append!(nodes, parse_interpolations(template[last_idx:end]))
    end

    return nodes
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
