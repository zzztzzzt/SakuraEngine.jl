#= 
transformer.jl — Directive transformation layer
Responsible for converting directive attributes ( sk-* / v-* ) on ElementNode
into corresponding AST control nodes ( ForNode / IfNode ).
=#

# Supported directives — priority order kept consistent with Vue 3

const FOR_DIRECTIVES = ("sk-for", "v-for")
const IF_DIRECTIVES = ("sk-if", "v-if")
const ELSEIF_DIRECTIVES = ("sk-else-if", "v-else-if")
const ELSE_DIRECTIVES = ("sk-else", "v-else")

"""
    _parse_for_expr(expr) -> (var, iterable)

Parse for expressions in the format `item in items` or `(idx, item) in items`.
"""
function _parse_for_expr(expr::AbstractString)
    parts = split(expr, " in ", limit=2)
    length(parts) != 2 &&
        error("SakuraEngine [Transformer] : Invalid for expression `$expr`, format should be `item in iterable`")

    var_str = strip(parts[1])
    iterable_str = strip(parts[2])

    var = try
        Meta.parse(var_str)
    catch e
        error("SakuraEngine [Transformer] : for expression var parsing failed `$var_str` - $e")
    end

    iterable = try
        Meta.parse(iterable_str)
    catch e
        error("SakuraEngine [Transformer] : for expression iterable parsing failed `$iterable_str` - $e")
    end

    return var, iterable
end

"""
    _parse_if_expr(expr) -> Expr

Parse the conditional expression string and return it as a Julia Expr.
"""
function _parse_if_expr(expr::AbstractString)
    try
        Meta.parse(strip(expr))
    catch e
        error("SakuraEngine [Transformer] : if expression parsing failed `$expr` - $e")
    end
end

"""
    _find_directive(attrs, keys) -> (key, value) | nothing

Find the first matching directive in the attribute dictionary according to priority.
"""
function _find_directive(attrs::Dict{String,String}, keys)
    for k in keys
        haskey(attrs, k) && return (k, attrs[k])
    end
    return nothing
end

"""
    transform_directives(nodes) -> Vector{Node}

Recursively convert directive attributes on ElementNode into control nodes.

Processing priority : for > if > else-if / else
  - sk-for wraps the entire host element
  - sk-if starts a conditional chain; contiguous sk-else-if/sk-elsesiblings
    ( separated only by whitespace text ) are collected into the same IfNode
"""
function transform_directives(nodes::Vector{Node})
    new_nodes = Node[]
    i = 1

    while i <= length(nodes)
        node = nodes[i]

        # Non-element nodes pass through unchanged
        if !(node isa ElementNode)
            push!(new_nodes, node)
            i += 1
            continue
        end

        # Recursively transform children first
        node = ElementNode(
            node.tag,
            node.attrs,
            transform_directives(node.children)
        )

        # sk-for / v-for ( highest priority, wraps the whole element )
        for_directive = _find_directive(node.attrs, FOR_DIRECTIVES)
        if for_directive !== nothing
            dir_key, dir_val = for_directive
            var, iterable    = _parse_for_expr(dir_val)

            clean_attrs = copy(node.attrs)
            delete!(clean_attrs, dir_key)
            clean_node = ElementNode(node.tag, clean_attrs, node.children)

            push!(new_nodes, ForNode(var, iterable, Node[clean_node]))
            i += 1
            continue
        end

        # sk-if / v-if  — collect the full if / else-if / else chain
        if_directive = _find_directive(node.attrs, IF_DIRECTIVES)
        if if_directive !== nothing
            dir_key, dir_val = if_directive
            cond_expr = _parse_if_expr(dir_val)

            clean_attrs = copy(node.attrs)
            delete!(clean_attrs, dir_key)
            clean_node = ElementNode(node.tag, clean_attrs, node.children)

            branches = Pair{Any, Vector{Node}}[cond_expr => Node[clean_node]]
            i += 1

            # Look ahead: consume contiguous sk-else-if / sk-else siblings
            while i <= length(nodes)
                sib = nodes[i]

                # Skip pure-whitespace text that lives between the tags
                if sib isa TextNode && isempty(strip(sib.content))
                    i += 1
                    continue
                end

                # Stop if next node is not an element
                sib isa ElementNode || break

                elseif_dir = _find_directive(sib.attrs, ELSEIF_DIRECTIVES)
                else_dir = _find_directive(sib.attrs, ELSE_DIRECTIVES)

                if elseif_dir !== nothing
                    ek, ev = elseif_dir
                    cond2 = _parse_if_expr(ev)
                    attrs2 = copy(sib.attrs);  delete!(attrs2, ek)
                    child2 = ElementNode(sib.tag, attrs2, transform_directives(sib.children))
                    push!(branches, cond2 => Node[child2])
                    i += 1

                elseif else_dir !== nothing
                    ek, _ = else_dir
                    attrs2 = copy(sib.attrs);  delete!(attrs2, ek)
                    child2 = ElementNode(sib.tag, attrs2, transform_directives(sib.children))
                    push!(branches, nothing => Node[child2])   # nothing = unconditional
                    i += 1
                    break # sk-else is always the last branch

                else
                    break # next sibling is unrelated - stop
                end
            end

            push!(new_nodes, IfNode(branches))
            continue
        end

        # Stray sk-else-if / sk-else without a preceding sk-if
        # ( should not happen in valid templates; silently drop the directive )
        if _find_directive(node.attrs, ELSEIF_DIRECTIVES) !== nothing ||
           _find_directive(node.attrs, ELSE_DIRECTIVES)   !== nothing
            @warn "SakuraEngine [Transformer] : sk-else-if / sk-else found without a preceding sk-if — ignored"
            push!(new_nodes, node)
            i += 1
            continue
        end

        push!(new_nodes, node)
        i += 1
    end

    return new_nodes
end
