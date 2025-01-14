module Determinism

export @determinism  # Export your macro

using Random
using SHA
const rand_funs = [:rand, :randi, :randn, :randexp, :randperm, :randstring]

function extract_variable_names(loop_var)
    if isa(loop_var, Expr)
        if loop_var.head == :tuple
            # If it's a tuple, extract each variable
            return [extract_variable_names(arg) for arg in loop_var.args]
        elseif loop_var.head == :(=)
            # If it's an assignment, extract the variable name
            return extract_variable_names(loop_var.args[1])
        end
    elseif isa(loop_var, Symbol)
        # If it's a single variable, return it
        return loop_var
    end
    return nothing
end
function separate_for_block(for_expr::Expr)
    # Check if it's a 'for' loop
    if for_expr.head == :for
        # The first two arguments are the loop variable and range
        args = for_expr.args[1]
        # The third argument is the body (or block of code)
        body = for_expr.args[2]  # It should exist as long as the loop has a body
        if length(for_expr.args) != 2
            throw(ArgumentError("Block has wrong number of arguments"))
        end
        varargs = extract_variable_names(args.args[1])
        return varargs, args, body
    else
        throw(ArgumentError("Expression is not a for loop"))
    end
end

function is_for_block(expr)
    # check first if is a Expr 
    if isa(expr, Expr) 
        return expr.head == :for
    else
        false 
    end
end
function contains_for_block(expr)
    if !isa(expr, Expr) 
        return false 
    end

    # First, check if the current expression is a for-loop
    if is_for_block(expr)
        return true
    end

    # Recursively check in all subexpressions
    for arg in expr.args
        if arg isa Expr
            if contains_for_block(arg)  # Check in the sub-expression
                return true
            end
        end
    end
    return false
end

function extract_macro_symbol(expr)
    if isa(expr.args[1], Expr) && expr.args[1].head == :(.)
        # Extract the last argument of the dotted expression
        node = expr.args[1].args[end]
        return isa(node, QuoteNode) ? node.value : node
    elseif isa(expr.args[1], Symbol)
        # Direct symbol case (e.g., @floop)
        return expr.args[1]
    else
        throw(ArgumentError("Unexpected macro expression structure"))
    end
end

function fix_rng(expr, new_rng_var::Symbol=:rng, old_rng_var::Symbol=:rng, symbols::Vector{Symbol}=Symbol[], hash_int::Int=0, in_parallel_macro::Bool=false)
    # Base case: if it's not an expression, replace old_rng_var with new_rng_var if necessary
    if !isa(expr, Expr)
        return expr == old_rng_var ? new_rng_var : expr
    end 

    # Handle macro calls (e.g., @threads, @sync)
    if expr.head == :macrocall
        macro_name = extract_macro_symbol(expr)
        parallel_macros = [Symbol("@threads"), Symbol("@distributed"), Symbol("@parallel"), Symbol("@floop")]
        if macro_name in parallel_macros
            # Recursively process the macro body, indicating it's inside a parallel macro
            expr.args[end] = fix_rng(expr.args[end], new_rng_var, old_rng_var, symbols, hash_int, true)
        else
            # Process the macro body without marking it as parallel
            expr.args[end] = fix_rng(expr.args[end], new_rng_var, old_rng_var, symbols, hash_int)
        end
        return expr
    end

    # Handle `for` loops
    if is_for_block(expr)
        curr_symbols = copy(symbols)
        loop_var, other_args, body = separate_for_block(expr)

        # Track loop variables
        if loop_var isa Vector
            append!(curr_symbols, loop_var)
        elseif loop_var isa Symbol
            push!(curr_symbols, loop_var)
        end

        # If inside a parallel macro, generate a new RNG per iteration
        if in_parallel_macro
            rng_symbol = gensym(:rng)
            if length(curr_symbols) > 0
                if hash_int > 0
                    rng_expr = :( $rng_symbol = MersenneTwister(hash($(Expr(:tuple, curr_symbols...)))+$hash_int) ) 
                else
                    rng_expr = :( $rng_symbol = MersenneTwister(hash($(Expr(:tuple, curr_symbols...)))) ) 
                end
            else
                rng_expr = :( $rng_symbol = MersenneTwister(hash($hash_int)) )
            end
            new_body = fix_rng(body, rng_symbol, old_rng_var, curr_symbols, hash_int)
            return Expr(:for, other_args, Expr(:block, rng_expr, new_body.args...))
        else
            # Non-parallel `for` loops: process the body as-is
            return Expr(:for, other_args, fix_rng(body, new_rng_var, old_rng_var, curr_symbols, hash_int))
        end
    end

    # Handle `while` loops
    if expr.head == :while
        return Expr(:while, map(x -> fix_rng(x, new_rng_var, old_rng_var, symbols, hash_int), expr.args)...)
    end

    # Handle function calls
    if expr.head == :call
        processed_args = map(arg -> fix_rng(arg, new_rng_var, old_rng_var, symbols, hash_int), expr.args)
        if processed_args[1] in rand_funs
            updated_args = map(x -> x == old_rng_var ? new_rng_var : x, processed_args)
            if new_rng_var in updated_args[2:end]
                return Expr(:call, updated_args...)
            else
                return Expr(:call, processed_args[1], new_rng_var, updated_args[2:end]...)
            end
        else
            return Expr(:call, processed_args...)
        end
    end

    # Recursively process all arguments for other expression types
    return Expr(expr.head, map(x -> fix_rng(x, new_rng_var, old_rng_var, symbols, hash_int), expr.args)...)
end

function add_twister_if_undefined(rng_var::Symbol, hash_int::Int=0)
    # Generate the conditional `if` expression
    return :(if !(Base.@isdefined $(rng_var))
                $rng_var = MersenneTwister($hash_int)
            end)
end
function fix_rng_with_twister(expr::Expr, rng_var::Symbol, hash_int::Int)
    # Add the Twister initialization if the RNG variable is not defined
    rng_check_expr = add_twister_if_undefined(rng_var, hash_int)

    # Process the input expression using `fix_rng`
    fixed_expr = fix_rng(expr, rng_var, rng_var, Symbol[], hash_int, false)
    # Combine the Twister initialization and the transformed expression
    return esc(Expr(:block, rng_check_expr, fixed_expr))
end

macro determinism(expr::Expr)
    rng_var::Symbol = :rng
    hash_int::Int = 0
    new_expr = fix_rng_with_twister(expr, rng_var, hash_int)
    return new_expr
end

macro determinism(rng_var::Symbol, expr::Expr)
    hash_int::Int = 0
    return fix_rng_with_twister(expr, rng_var, hash_int)
end

macro determinism(hash_int::Int, expr::Expr)
    rng_var::Symbol = :rng
    return fix_rng_with_twister(expr, rng_var, hash_int)
end

macro determinism(rng_var::Symbol, hash_int::Int, expr::Expr)
    return fix_rng_with_twister(expr, rng_var, hash_int)
end
end
