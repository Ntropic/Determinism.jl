# Determinism.jl

[![CI](https://github.com/ntropic/Determinism.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/ntropic/Determinism.jl/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/ntropic/Determinism.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/ntropic/Determinism.jl)

**Determinism.jl** is a Julia package for ensuring reproducibility in parallel computations with pseudorandom number generators (RNGs). IT provides the macro `@determinism` to ensure that the same sequence of random numbers is generated independently of the thread or process execution order.

## Features
- Create aThread/Process specific seed for reproducible random number generation.
- Ensures `rand`, `randi`, `randn`, `randexp`, `randperm` and `randstring` in parallel for loops are executed with deterministic RNG logic.
- Detects function calls with `rng` argument (or custom rng variable).
- Recognizes parallel `for` loops created via the `@threads`, `@distributed`, `@parallel` and `@floop` macros.
- Inititalizes a `rng` object (via `MersenneTwister`) if none is has been initialized before the macro


## Installation
You can install `Determinism.jl` via Julia's package manager:

```julia
using Pkg
Pkg.add("Determinism")
```

## Usage
A simple example in which a parallel for loop, would normally not yield reproducible results.
```julia
using Determinism
using Base.Threads 
@determinism function parallel_function()
    x = rand(10,10)
    y = fun(rng)
    for i =1:10
        Threads.@threads for j in 1:10
            a = sum(rand(j:10))
            b = other_fun(rng)
        end
    end
end
```
Which roughly transforms the `parallel_function` into
```julia
function parallel_function()
    if !(Base.@isdefined(rng))
        rng = MersenneTwister(0)
    end
    x = rand(rng, 10, 10)
    y = fun(rng)
    for i = 1:10
        Threads.@threads for j = 1:10
            var"##rng#233" = MersenneTwister(hash((i, j)))
            a = sum(rand(var"##rng#233", j:10))
            b = other_fun(rng)
        end
    end
end
```
This ensures `rng` is initialized in the outer loop, and that every thread has a unique seed, that depends on the indexes of the nested loop that it is executing. This way, each thread will generate its own sequence of random numbers independently of the other threads.

The macro also allows optional arguments to specify the name of the RNG variable (by default `rng`) and a seed value that is added to the hashed seeds. The RNG variable is used to detect function calls with internal random number generation. In the above example `fun(rng)` and `other_fun()`.

Specify the variable names via `@determinism rng_name **code**`, the has via `@determinism seed_value **code**` or both via `@determinism rng_name seed_value **code**`. 

## Author
Michael Schilling