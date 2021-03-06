#
# Correctness Tests
#

require("test.jl")

using DataFrames

my_tests = ["test/dataarray.jl",
            "test/data.jl",
            "test/index.jl",
            "test/dataframe.jl",
            "test/operators.jl",
            "test/io.jl",
            # "test/formula.jl",
            "test/datastream.jl",
            "test/datamatrix.jl",
            "test/constructors.jl",
            "test/abstractarray.jl",
            "test/booleans.jl",
            "test/indexing.jl",
            "test/indexedvector.jl",
            "test/iteration.jl",
            "test/colfuncs.jl",
            "test/duplicates.jl",
            "test/padding.jl",
            "test/tabulation.jl"]

println("Running tests:")

for my_test in my_tests
    println(" * $(my_test)")
    include(my_test)
end
