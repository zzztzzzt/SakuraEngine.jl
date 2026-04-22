#=
ast.jl - AST Node Type Definitions
All parsed template nodes are represented by these structs
=#

abstract type Node end

# Pure text node ( without interpolation )
struct TextNode <: Node
    content::String
end

# {{ expr }} Interpolation node
struct InterpNode <: Node
    expr::Union{Expr, Symbol, Number}
end

# sk-if / sk-else-if / sk-else Conditional chain node
# branches : Vector of ( condition_expr => children ) pairs
# condition_expr is an Expr / Symbol for sk-if / sk-else-if
# condition_expr is `nothing` for the unconditional sk-else branch
struct IfNode <: Node
    branches::Vector{Pair{Any, Vector{Node}}}
end

# General HTML element node
struct ElementNode <: Node
    tag::String
    attrs::Dict{String,String}
    children::Vector{Node}
end

# sk-for / v-for Loop node
struct ForNode <: Node
    var::Union{Symbol, Expr}
    iterable::Any
    children::Vector{Node}
end
