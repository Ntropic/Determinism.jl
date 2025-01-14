using Test
using Determinism
using Base.Threads
using Random

@testset "Determinism.jl Tests" begin
    @testset "Reproducibility Test 1" begin
        result1 = @determinism rng 42 begin
            rand(rng, 10, 10)
        end

        result2 = @determinism rng2 42 begin
            rand(rng2, 10, 10)
        end
        @test result1 == result2  # Ensure results are identical
    end

    @testset "Reproducibility Test 2" begin        
        result1 = @determinism rng 42 begin
            x1 = zeros(10, 10)
            for i in 1:10
                for j in 1:10
                    x1[i, j] = rand()
                end
            end
            x1
        end

        result2 = @determinism rng2 42 begin
            x2 = zeros(10, 10)
            for i in 1:10
                for j in 1:10
                    x2[i, j] = rand()
                end
            end
            x2
        end
        @test result1 == result2  # Ensure results are identical
    end

    @testset "Reproducibility Test 3" begin        
        result1 = @determinism rng 42 begin
            x1 = zeros(10, 10)
            for i in 1:10
                for j in 1:10
                    x1[i, j] = rand()
                end
            end
            x1
        end

        result2 = @determinism rng 42 begin
            x2 = zeros(10, 10)
            for i in 1:10
                for j in 1:10
                    x2[i, j] = rand()
                end
            end
            x2
        end
        @test result1 != result2  # Ensure results are identical
    end

    @testset "Reference Code Test 1" begin
        function determinism_function()
            @determinism rnger1 42 begin
                x1_ = rand(rnger1, 10, 10)
                Threads.@threads for i in 1:4
                    x1_[:, i] .+= rand(10)
                end
                return x1_
            end
        end

        function manual_function()
            rng = MersenneTwister(42)
            x2_ = rand(rng, 10, 10)
            Threads.@threads for i in 1:4
                rng_local = MersenneTwister(hash((i,))+42)
                x2_[:, i] .+= rand(rng_local, 10)
            end
            return x2_
        end

        result_determinism = determinism_function()
        result_manual = manual_function()
        @test result_determinism == result_manual  # Compare results
    end

    @testset "Equivalence Test: Nested loops with threading" begin
        function nested_determinism_function()
            @determinism begin
                x = zeros(4, 4)
                Threads.@threads for i in 1:4
                    Threads.@threads for j in 1:4
                        x[i, j] = randexp()
                    end
                end
                return x
            end
        end

        function nested_manual_function()
            x = zeros(4, 4)
            for i in 1:4
                Threads.@threads for i in 1:4
                    Threads.@threads for j in 1:4
                        rng_local = MersenneTwister(hash((i,j,)))
                        x[i, j] = randexp(rng_local)
                    end
                end
            end
            return x
        end

        result_determinism = nested_determinism_function()
        result_manual = nested_manual_function()
        @test result_determinism == result_manual  # Compare results
    end

end
# Generate lcov.info after tests
Coverage.Codecov.submit(process_folder())