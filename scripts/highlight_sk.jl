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
        :expression          => "\033[38;2;255;117;239m", # {{ variable }}
        :expression_computed => "\033[38;2;255;150;201m", # {{ a + b }}
        :html_tag            => "\033[38;2;255;156;207m", # brackets & others
        :html_tag_name       => "\033[38;2;255;178;41m", # <div>
        :html_attr_class     => "\033[38;2;153;142;124m", # class=
        :html_attr_value     => "\033[38;2;224;190;232m", # "value"
        :delimiter           => "\033[38;2;200;167;252m", # {{ }}
        :title               => "\033[1;37m", # Bold White
    )
    reset = "\033[0m"

    sk_tag_pattern = join(keys(sk_tags), "|")
    sk_attr_pattern = join(keys(sk_attrs), "|")

    highlighted = content

    # 1. Handle Sakura-specific Tags
    highlighted = replace(highlighted,
        Regex("(</?)($(sk_tag_pattern))((?:\\s[^>]*)??>)", "i") => 
        s -> begin
            m = match(Regex("(</?)($(sk_tag_pattern))((?:\\s[^>]*)??>)", "i"), s)
            tag_color = get(sk_tags, lowercase(m[2]), theme[:html_tag])
            tag_color * s * reset
        end)

    # 2. Handle Expressions {{ ... }}
    highlighted = replace(highlighted,
        r"\{\{.*?\}\}"s => 
        s -> begin
            inner = s[3:end-2]
            has_op = occursin(r"[+\-*/%&|=!><]", inner)
            content_color = has_op ? theme[:expression_computed] : theme[:expression]
            theme[:delimiter] * "{{" * reset * content_color * inner * reset * theme[:delimiter] * "}}" * reset
        end)

    # 3. Handle Standard HTML Tags & Attributes
    highlighted = replace(highlighted,
        r"(<(?!/?sk-)/?[a-zA-Z][a-zA-Z0-9-]*)([^>]*)(>)"s => 
        m_str -> begin
            m = match(r"(<(?!/?sk-)/?[a-zA-Z][a-zA-Z0-9-]*)([^>]*)(>)"s, m_str)
            tag_part = m[1]
            attr_part = m[2]
            tail_part = m[3]

            # a. Sakura attributes
            processed_attrs = replace(attr_part, 
                Regex("($(sk_attr_pattern))(\\s*=\\s*\"[^\"]*\")?", "i") => 
                a -> begin
                    am = match(Regex("($(sk_attr_pattern))", "i"), a)
                    color = get(sk_attrs, lowercase(am[1]), theme[:html_tag])
                    color * a * reset
                end)

            # b. CSS Class
            processed_attrs = replace(processed_attrs, 
                r"(class\s*=\s*[\"'])([^\"]*)([\"'])"i => 
                c -> begin
                    cm = match(r"(class\s*=\s*[\"'])([^\"]*)([\"'])"i, c)
                    theme[:html_attr_class] * cm[1] * reset * theme[:html_attr_value] * cm[2] * reset * theme[:html_attr_class] * cm[3] * reset
                end)

            theme[:html_tag_name] * tag_part * reset * processed_attrs * theme[:html_tag_name] * tail_part * reset
        end)

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