function parse_mpc(filename)
    content = read(filename, String)
    
    # Remove whole-line comments starting with %
    lines = split(content, "\n")
    clean_lines = filter(line -> !startswith(strip(line), "%"), lines)
    content_clean = join(clean_lines, "\n")
    
    mpc_dict = Dict{String,Any}()
    
    # Regex (with DOTALL mode) to capture sections with matrices.
    # The (?s) tells the regex to treat newlines as normal characters.
    pattern = r"(?s)mpc\.(\w+)\s*=\s*\[(.*?)\];"
    for m in eachmatch(pattern, content_clean)
        field = m.captures[1]
        block = m.captures[2]
        
        # Split rows on semicolon and remove empty results
        rows = filter(x -> !isempty(strip(x)), split(block, ';'))
        matrix = []
        for row in rows
            # Split row into tokens (space/tab separated) and filter empty strings
            tokens = filter(x -> !isempty(x), split(strip(row)))
            if !isempty(tokens)
                push!(matrix, parse.(Float64, tokens))
            end
        end
        mpc_dict[field] = matrix
    end
    return mpc_dict
end