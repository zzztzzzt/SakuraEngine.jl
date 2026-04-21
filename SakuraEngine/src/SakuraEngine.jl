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
    include_string(mod, script)
    return mod
end

function inject_if_nodes(nodes::Vector{Node})
    new_nodes = Node[]

    for node in nodes
        if node isa ElementNode
            node = ElementNode(
                node.tag,
                node.attrs,
                inject_if_nodes(node.children)
            )

            if haskey(node.attrs, "sk-if")
                cond_expr = Meta.parse(node.attrs["sk-if"])

                new_attrs = copy(node.attrs)
                delete!(new_attrs, "sk-if")

                clean_node = ElementNode(
                    node.tag,
                    new_attrs,
                    node.children
                )

                push!(new_nodes, IfNode(cond_expr, [clean_node]))
            else
                push!(new_nodes, node)
            end

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

    html = replace(html, r"\n{3,}" => "\n\n")
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

        if start_idx > last_idx
            text = template[last_idx:start_idx-1]
            push!(nodes, TextNode(text))
        end

        expr_str = strip(m.captures[1])
        ex = Meta.parse(expr_str)
        push!(nodes, InterpNode(ex))

        last_idx = end_idx + 1
    end

    if last_idx <= lastindex(template)
        push!(nodes, TextNode(template[last_idx:end]))
    end

    return nodes
end

function parse_open_tag(template::AbstractString, from::Int)
    i = from
    len = lastindex(template)

    # Must start with <
    i > len && return nothing
    template[i] != '<' && return nothing
    i = nextind(template, i)

    # Skip whitespace
    while i <= len && isspace(template[i])
        i = nextind(template, i)
    end

    # Read tag name
    tag_start = i
    while i <= len && !isspace(template[i]) && template[i] != '>' && template[i] != '/'
        i = nextind(template, i)
    end
    tag = template[tag_start:prevind(template, i)]
    isempty(tag) && return nothing

    # Read attributes until closing >  — skip over quoted strings so > inside values is safe
    attr_start = i
    while i <= len
        c = template[i]
        if c == '>'
            attrs_str = template[attr_start:prevind(template, i)]
            return (tag, attrs_str, i)
        elseif c == '"' || c == '\''
            quote_char = c
            i = nextind(template, i)
            while i <= len && template[i] != quote_char
                i = nextind(template, i)
            end
            i <= len && (i = nextind(template, i)) # skip closing quote
        else
            i = nextind(template, i)
        end
    end

    return nothing # unclosed tag
end

# Find the matching closing </tag> starting from `from`, handling nesting
function find_closing_tag(template::AbstractString, tag::String, from::Int)
    open_pat  = Regex("<\\s*$(tag)[\\s>]")
    close_pat = Regex("</\\s*$(tag)\\s*>")

    depth = 1
    i = from

    while i <= lastindex(template)
        close_m = match(close_pat, template, i)
        open_m  = match(open_pat,  template, i)

        # whichever comes first
        close_pos = close_m === nothing ? typemax(Int) : close_m.offset
        open_pos  = open_m  === nothing ? typemax(Int) : open_m.offset

        if close_pos == typemax(Int)
            return nothing # no closing tag found
        end

        if open_pos < close_pos
            depth += 1
            i = open_pos + length(open_m.match)
        else
            depth -= 1
            if depth == 0
                return (close_m.offset, close_m.offset + length(close_m.match) - 1)
            end
            i = close_pos + length(close_m.match)
        end
    end

    return nothing
end

function parse_attrs(attr_str::AbstractString)
    attrs = Dict{String,String}()
    # Match key="value" or key='value', where value can contain anything including >
    for m in eachmatch(r"""(\S+?)\s*=\s*["'](.*?)["']"""s, attr_str)
        attrs[m.captures[1]] = m.captures[2]
    end
    return attrs
end

function parse_elements(template::AbstractString)
    nodes = Node[]
    i = 1
    len = lastindex(template)

    while i <= len
        # Look for next <tag
        lt = findnext('<', template, i)
        if lt === nothing
            # rest is plain text / interpolation
            append!(nodes, parse_interpolations(template[i:end]))
            break
        end

        # Text before the tag
        if lt > i
            append!(nodes, parse_interpolations(template[i:prevind(template, lt)]))
        end

        result = parse_open_tag(template, lt)
        if result === nothing
            # not a valid tag, treat < as text
            append!(nodes, parse_interpolations(template[lt:lt]))
            i = nextind(template, lt)
            continue
        end

        tag, attrs_str, gt_pos = result

        # Skip self-closing tags and non-element things ( sk-*, etc. )
        # Also skip closing tags that somehow appear here
        if startswith(tag, "/") || startswith(tag, "!")
            i = nextind(template, gt_pos)
            continue
        end

        # Find matching closing tag — start searching AFTER the >
        after_open = nextind(template, gt_pos)
        close_result = find_closing_tag(template, tag, after_open)

        if close_result === nothing
            # Treat as void/self-closing element with no children
            attrs = parse_attrs(attrs_str)
            push!(nodes, ElementNode(tag, attrs, Node[]))
            i = after_open
            continue
        end

        close_start, close_end = close_result
        inner = template[after_open:prevind(template, close_start)]

        attrs = parse_attrs(attrs_str)
        children = parse_elements(inner)

        push!(nodes, ElementNode(tag, attrs, children))
        i = nextind(template, close_end)
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

        if start_idx > last_idx
            text = template[last_idx:start_idx-1]
            append!(nodes, parse_interpolations(text))
        end

        cond_expr = Meta.parse(strip(m.captures[3]))
        inner = m.captures[5]
        child_nodes = parse_interpolations(inner)
        push!(nodes, IfNode(cond_expr, child_nodes))

        last_idx = end_idx + 1
    end

    if last_idx <= lastindex(template)
        append!(nodes, parse_interpolations(template[last_idx:end]))
    end

    return nodes
end

function process_sk_if(template::AbstractString, mod::Module)
    pattern = r"<(\w+)((?:[^>\"]*|\"[^\"]*\")*?)\s+sk-if=\"([^\"]*?)\"((?:[^>\"]*|\"[^\"]*\")*)>(.*?)</\1>"s

    prev = ""
    curr = String(template)

    while prev != curr
        prev = curr
        matches = collect(eachmatch(pattern, curr))
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
    pattern = r"<(\w+)((?:[^>\"]*|\"[^\"]*\")*?)\s+sk-for=\"([^\"]*?) in ([^\"]*?)\"((?:[^>\"]*|\"[^\"]*\")*)>(.*?)</\1>"s
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