#=
renderer.jl — Rendering layer
Responsible for converting the AST Node tree + eval module into the final HTML string.
=#

"""
    render_nodes(nodes, mod) -> String

Recursively renders the AST node sequence into HTML strings.
`mod` is a Julia Module that performs interpolation and conditional expressions.
"""
function render_nodes(nodes::Vector{Node}, mod::Module)
    io = IOBuffer()

    for node in nodes
        if node isa TextNode
            write(io, node.content)

        elseif node isa CommentNode
            write(io, node.content)

        elseif node isa InterpNode
            val = try
                Core.eval(mod, node.expr)
            catch e
                error("SakuraEngine [Renderer] : Interpolation expression evaluation failed `$(node.expr)` - $e")
            end
            write(io, string(val))

        elseif node isa IfNode
            for (cond, children) in node.branches
                should_render = if cond === nothing
                    true # sk-else - unconditional
                else
                    try
                        Core.eval(mod, cond)
                    catch e
                        error("SakuraEngine [Renderer] : Conditional expression evaluation failed `$(cond)` - $e")
                    end
                end
                if should_render
                    write(io, render_nodes(children, mod))
                    break # Only the first matching branch is rendered
                end
            end

        elseif node isa ElementNode
            write(io, "<", node.tag)
            for (k, v) in node.attrs
                if startswith(k, "sk-bind:")
                    attr_name = SubString(k, 9)
                    val = try
                        Core.eval(mod, Meta.parse(v))
                    catch e
                        error("SakuraEngine [Renderer] : sk-bind expression evaluation failed `$v` - $e")
                    end
                    
                    if val isa Bool
                        if val
                            write(io, " $attr_name")
                        end
                    elseif val !== nothing
                        write(io, " $attr_name=\"$val\"")
                    end
                else
                    write(io, " $k=\"$v\"")
                end
            end
            write(io, ">")
            write(io, render_nodes(node.children, mod))
            write(io, "</", node.tag, ">")

        elseif node isa ForNode
            iterable = try
                Core.eval(mod, node.iterable)
            catch e
                error("SakuraEngine [Renderer] : for iteration object evaluation failed `$(node.iterable)` - $e")
            end
            for val in iterable
                Core.eval(mod, :($(node.var) = $val))
                write(io, render_nodes(node.children, mod))
            end
        end
    end

    return String(take!(io))
end

"""
    render_template(template, mod) -> String

Parse the template string, apply directive transformations, and generate HTML.
"""
function render_template(template::AbstractString, mod::Module)
    nodes = parse_elements(template)
    nodes = transform_directives(nodes)
    return render_nodes(nodes, mod)
end
