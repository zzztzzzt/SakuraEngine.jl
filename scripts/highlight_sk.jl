function highlight_sk(filename::String)
    if !isfile(filename)
        error("File not found: $filename")
    end

    content = read(filename, String)

    # Color Configuration ( ANSI TrueColor )
    sk_tags = Dict(
        "sk-script"   => "\033[38;2;149;88;178m",
        "sk-template" => "\033[38;2;149;88;178m",
    )
    sk_attrs = Dict(
        "sk-if"      => "\033[38;2;255;242;184m",
        "sk-else-if" => "\033[38;2;255;242;184m",
        "sk-else"    => "\033[38;2;255;242;184m",
        "sk-on"      => "\033[38;2;255;242;184m",
        "sk-for"     => "\033[38;2;255;242;184m",
        "sk-bind"    => "\033[38;2;255;242;184m",
        "sk-model"   => "\033[38;2;255;242;184m",
        "sk-show"    => "\033[38;2;255;242;184m",
    )
    theme = Dict(
        :expression          => "\033[38;2;255;117;239m",
        :expression_computed => "\033[38;2;255;150;201m",
        :html_tag            => "\033[38;2;255;156;207m",
        :html_tag_name       => "\033[38;2;255;178;41m",
        :html_attr_class     => "\033[38;2;153;142;124m",
        :html_attr_value     => "\033[38;2;224;190;232m",
        :delimiter           => "\033[38;2;200;167;252m",
        :sk_script_body      => "\033[38;2;180;180;180m",
        :title               => "\033[1;37m",
        :comment             => "\033[38;2;135;206;235m",
    )
    reset = "\033[0m"

    sk_tag_pattern  = join(keys(sk_tags),  "|")
    sk_attr_pattern = join(keys(sk_attrs), "|")

    # helpers

    # Highlight {{ expr }} inside an already-extracted string
    function highlight_expressions(s::AbstractString)
        replace(String(s), r"\{\{.*?\}\}"s => sub -> begin
            sub = String(sub)
            inner = sub[3:end-2]
            has_op = occursin(r"[+\-*/%&|=!><]", inner)
            color = has_op ? theme[:expression_computed] : theme[:expression]
            theme[:delimiter] * "{{" * reset * color * inner * reset * theme[:delimiter] * "}}" * reset
        end)
    end

    # Highlight sk-* and class= attributes inside an attr string
    function highlight_attrs(attr_part::AbstractString)
        # a. sk-* attributes ( name + optional ="value" )
        processed = replace(String(attr_part),
            Regex("($(sk_attr_pattern))(\\s*=\\s*\"[^\"]*\")?", "i") => a -> begin
                a = String(a)
                am = match(Regex("($(sk_attr_pattern))", "i"), a)
                am === nothing && return a
                color = get(sk_attrs, lowercase(String(am[1])), theme[:html_tag])
                color * a * reset
            end)

        # b. class= attribute
        processed = replace(processed,
            r"(class\s*=\s*[\"'])([^\"']*)([\"'])"i => c -> begin
                c = String(c)
                cm = match(r"(class\s*=\s*[\"'])([^\"']*)([\"'])"i, c)
                cm === nothing && return c
                theme[:html_attr_class] * String(cm[1]) * reset *
                theme[:html_attr_value] * String(cm[2]) * reset *
                theme[:html_attr_class] * String(cm[3]) * reset
            end)

        processed
    end

    # Split content into segments : sk-script blocks vs everything else

    #=
    Strategy : tokenise the file into a list of ( kind, text ) pairs, then
    process each kind independently so sk-script bodies are never touched
    by HTML/expression regexes
    =#

    segments = Tuple{Symbol,String}[]

    # Regex that captures a full <sk-script>...</sk-script> block ( multiline )
    sk_script_re = r"(<sk-script(?:\s(?:\"[^\"]*\"|'[^']*'|[^>])*)?>)(.*?)(</sk-script>)"si

    pos = 1
    for m in eachmatch(sk_script_re, content)
        # text before this block
        if m.offset > pos
            push!(segments, (:html, content[pos : m.offset - 1]))
        end
        push!(segments, (:sk_open, m[1])) # <sk-script>
        push!(segments, (:sk_body, m[2])) # raw script content
        push!(segments, (:sk_close, m[3])) # </sk-script>
        pos = m.offset + length(m.match)
    end
    # remainder
    if pos <= lastindex(content)
        push!(segments, (:html, content[pos:end]))
    end

    # Process each segment

    function process_html(s::AbstractString)
        # 1. Sakura container tags : <sk-template> </sk-template> etc
        s = replace(String(s),
            Regex("(</?)($(sk_tag_pattern))((?:\"[^\"]*\"|'[^']*'|[^>])*>)", "si") => sub -> begin
                sub = String(sub)
                mm = match(Regex("(</?)($(sk_tag_pattern))((?:\"[^\"]*\"|'[^']*'|[^>])*>)", "si"), sub)
                mm === nothing && return sub
                tag_color = get(sk_tags, lowercase(String(mm[2])), theme[:html_tag])
                tag_color * sub * reset
            end)

        # 2. Expressions {{ ... }}
        s = highlight_expressions(s)

        # 3. Standard HTML tags — quote-aware attr matching
        #=
        Attr part: (?:"[^"]*"|'[^']*'|[^>])*
        This alternation consumes quoted strings whole (so > inside quotes
        is never mistaken for the closing >), and falls back to any
        non-> character otherwise. The first unquoted > ends the tag
        =#
        s = replace(s,
            r"(<(?!/?sk-)/?[a-zA-Z][a-zA-Z0-9-]*)((?:\"[^\"]*\"|'[^']*'|[^>])*)(>)"s => sub -> begin
                sub = String(sub)
                mm = match(r"(<(?!/?sk-)/?[a-zA-Z][a-zA-Z0-9-]*)((?:\"[^\"]*\"|'[^']*'|[^>])*)(>)"s, sub)
                mm === nothing && return sub
                tag_part  = String(mm[1])
                attr_part = highlight_attrs(String(mm[2]))
                tail_part = String(mm[3])
                theme[:html_tag_name] * tag_part * reset *
                attr_part *
                theme[:html_tag_name] * tail_part * reset
            end)

        # 4. Comments #= ... =# and <!-- ... -->
        s = replace(s, r"(#=.*?=#|<!--.*?-->)"s => sub -> begin
            clean_sub = replace(String(sub), r"\033\[[0-9;]*m" => "")
            theme[:comment] * clean_sub * reset
        end)

        s
    end

    function process_sk_open(s::AbstractString)
        # The opening <sk-script> tag itself
        tag_color = get(sk_tags, "sk-script", theme[:html_tag])
        tag_color * s * reset
    end

    function process_sk_body(s::AbstractString)
        # Raw Julia/script body — just dim it, no HTML processing
        theme[:sk_script_body] * s * reset
    end

    function process_sk_close(s::AbstractString)
        tag_color = get(sk_tags, "sk-script", theme[:html_tag])
        tag_color * s * reset
    end

    highlighted = join(
        map(segments) do (kind, text)
            if     kind === :html     ; process_html(text)
            elseif kind === :sk_open  ; process_sk_open(text)
            elseif kind === :sk_body  ; process_sk_body(text)
            elseif kind === :sk_close ; process_sk_close(text)
            else                      ; text
            end
        end
    )

    # Output
    println(theme[:title] * "|||||| SK Template Highlight: $filename ||||||" * reset * "\n")
    print(highlighted)
    println("\n\n" * theme[:title] * "|||||| End of File ||||||" * reset)
end

# CLI Entry Point
if !isempty(ARGS)
    highlight_sk(ARGS[1])
else
    println("Usage : julia --project=. --color=yes scripts/highlight_sk.jl template_example/example.sk")
end