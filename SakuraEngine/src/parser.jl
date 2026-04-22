#=
parser.jl - Template parsing layer
Responsible for parsing the original HTML string into an AST Node tree.
=#

"""
    parse_interpolations(template) -> Vector{Node}

Parse text segments containing `{{ expr }}` interpolations into a sequence of TextNode / InterpNode.
"""
function parse_interpolations(template::AbstractString)
    nodes = Node[]
    pattern = r"\{\{(.*?)\}\}"s
    last_idx = 1

    for m in eachmatch(pattern, template)
        start_idx = m.offset
        end_idx = m.offset + length(m.match) - 1

        if start_idx > last_idx
            push!(nodes, TextNode(template[last_idx:start_idx-1]))
        end

        expr_str = strip(m.captures[1])
        ex = try
            Meta.parse(expr_str)
        catch e
            error("SakuraEngine [Parser] : Interpolation expression parsing failed `{{ $expr_str }}` - $e")
        end
        push!(nodes, InterpNode(ex))

        last_idx = end_idx + 1
    end

    if last_idx <= lastindex(template)
        push!(nodes, TextNode(template[last_idx:end]))
    end

    return nodes
end

"""
    parse_open_tag(template, from) -> (tag, attrs_str, gt_pos) | nothing

Starting from the `from` position, attempt to parse an opening tag and return ( tag name, attribute string, position of `>` ).
If it is not a valid opening tag, return `nothing`.
"""
function parse_open_tag(template::AbstractString, from::Int)
    i = from
    len = lastindex(template)

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

    # Read attributes until `>`
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
            i <= len && (i = nextind(template, i)) # Skip closing quote
        else
            i = nextind(template, i)
        end
    end

    return nothing # Unclosed tag
end

"""
    find_closing_tag(template, tag, from) -> (close_start, close_end) | nothing

Find the corresponding closing tag `</tag>` starting from the `from` position, correctly handling nested same-named tags.
"""
function find_closing_tag(template::AbstractString, tag::AbstractString, from::Int)
    open_pat = Regex("<\\s*$(tag)[\\s>]")
    close_pat = Regex("</\\s*$(tag)\\s*>")

    depth = 1
    i = from

    while i <= lastindex(template)
        close_m = match(close_pat, template, i)
        open_m = match(open_pat, template, i)

        close_pos = close_m === nothing ? typemax(Int) : close_m.offset
        open_pos = open_m === nothing ? typemax(Int) : open_m.offset

        close_pos == typemax(Int) && return nothing # No closing tag found

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

"""
    parse_attrs(attr_str) -> Dict{String,String}

Parse the attribute string into a key => value dictionary, supporting single and double quotes.
"""
function parse_attrs(attr_str::AbstractString)
    attrs = Dict{String,String}()

    # Pass 1 - value attributes : key="value" or key='value'
    for m in eachmatch(r"""([\w\-:@\.]+)\s*=\s*["'](.*?)["']"""s, attr_str)
        attrs[m.captures[1]] = m.captures[2]
    end

    # Pass 2 - boolean attributes ( no `=` ) :
    # Remove all value-attr spans, then scan remaining words
    cleaned = replace(attr_str, r"""[\w\-:@\.]+\s*=\s*["'].*?["']"""s => " ")
    for m in eachmatch(r"""([\w\-:@\.]+)""", cleaned)
        key = m.captures[1]
        haskey(attrs, key) || (attrs[key] = "")
    end

    return attrs
end

"""
    parse_elements(template) -> Vector{Node}

The main parsing function: recursively parse the template string into a complete AST Node tree.
"""
function parse_elements(template::AbstractString)
    nodes = Node[]
    i = 1
    len = lastindex(template)

    while i <= len
        lt = findnext('<', template, i)

        if lt === nothing
            append!(nodes, parse_interpolations(template[i:end]))
            break
        end

        # Text before the tag
        if lt > i
            append!(nodes, parse_interpolations(template[i:prevind(template, lt)]))
        end

        if startswith(SubString(template, lt), "<!--")
            close_idx = findnext("-->", template, lt)
            if close_idx === nothing
                push!(nodes, CommentNode(template[lt:end]))
                break
            else
                push!(nodes, CommentNode(template[lt:last(close_idx)]))
                i = nextind(template, last(close_idx))
                continue
            end
        end

        result = parse_open_tag(template, lt)
        if result === nothing
            # Not a valid tag, treat `<` as plain text
            append!(nodes, parse_interpolations(template[lt:lt]))
            i = nextind(template, lt)
            continue
        end

        tag, attrs_str, gt_pos = result

        # Skip closing tags, DOCTYPE, comments, etc.
        if startswith(tag, "/") || startswith(tag, "!")
            i = nextind(template, gt_pos)
            continue
        end

        after_open = nextind(template, gt_pos)
        close_result = find_closing_tag(template, tag, after_open)

        if close_result === nothing
            # Void / self-closing element
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
