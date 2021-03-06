##############################################################################
##
## PooledDataArray type definition
##
## An AbstractDataArray with efficient storage when values are repeated. A
## PDA wraps an array of UInt8's, which are used to index into a compressed
## pool of values. NA's are 0's in the UInt8 array.
##
## TODO: Make sure we don't overflow from refs being Uint8
## TODO: Allow ordering of factor levels
## TODO: Add metadata for dummy conversion
##
##############################################################################

type PooledDataArray{T, N} <: AbstractDataArray{T, N}
    refs::Array{POOLED_DATA_VEC_REF_TYPE, N}
    pool::Vector{T}

    function PooledDataArray(rs::Array{POOLED_DATA_VEC_REF_TYPE, N},
                             p::Vector{T})
        # refs mustn't overflow pool
        if max(rs) > prod(size(p))
            error("Reference array points beyond the end of the pool")
        end
        new(rs, p)
    end
end
typealias PooledDataVector{T} PooledDataArray{T, 1}
typealias PooledDataMatrix{T} PooledDataArray{T, 2}

##############################################################################
##
## PooledDataArray constructors
##
##############################################################################

# Echo inner constructor as an outer constructor
function PooledDataArray{T, N}(refs::Array{POOLED_DATA_VEC_REF_TYPE, N},
                               pool::Vector{T})
    PooledDataArray{T, N}(refs, pool)
end


# A no-op constructor
PooledDataArray(d::PooledDataArray) = d

# How do you construct a PooledDataArray from an Array?
# From the same sigs as a DataArray!
#
# Algorithm:
# * Start with:
#   * A null pool
#   * A pre-allocated refs
#   * A hash from T to Int
# * Iterate over d
#   * If value of d in pool already, set the refs accordingly
#   * If value is new, add it to the pool, then set refs
function PooledDataArray{T, N}(d::Array{T, N}, m::AbstractArray{Bool, N})
    newrefs = Array(POOLED_DATA_VEC_REF_TYPE, size(d))
    #newpool = Array(T, 0)
    poolref = Dict{T, POOLED_DATA_VEC_REF_TYPE}(0) # Why isn't this a set?
    maxref = 0

    # Loop through once to fill the poolref dict
    for i = 1:length(d)
        if !m[i]
            poolref[d[i]] = 0
        end
    end

    # Fill positions in poolref
    newpool = sort(keys(poolref))
    i = 1
    for p in newpool
        poolref[p] = i
        i += 1
    end

    # Fill in newrefs
    for i = 1:length(d)
        if m[i]
            newrefs[i] = 0
        else
            newrefs[i] = poolref[d[i]]
        end
    end

    return PooledDataArray(newrefs, newpool)
end

# Allow a pool to be provided by the user
function PooledDataArray{T, N}(d::Array{T, N},
                               pool::Vector{T},
                               m::AbstractArray{Bool, N})
    if length(pool) > typemax(POOLED_DATA_VEC_REF_TYPE)
        error("Cannot construct a PooledDataVector with such a large pool")
    end

    newrefs = Array(POOLED_DATA_VEC_REF_TYPE, size(d))
    poolref = Dict{T, POOLED_DATA_VEC_REF_TYPE}(0)
    maxref = 0

    # loop through once to fill the poolref dict
    for i = 1:length(pool)
        poolref[pool[i]] = 0
    end

    # fill positions in poolref
    newpool = sort(keys(poolref))
    i = 1
    for p in newpool
        poolref[p] = i
        i += 1
    end

    # fill in newrefs
    for i = 1:length(d)
        if m[i]
            newrefs[i] = 0
        else
            if has(poolref, d[i])
              newrefs[i] = poolref[d[i]]
            else
              error("Vector contains elements not in provided pool")
            end
        end
    end

    return PooledDataArray(newrefs, newpool)
end

# Convert a BitArray to an Array{Bool} w/ specified missingness
function PooledDataArray{N}(d::BitArray{N}, m::AbstractArray{Bool, N})
    PooledDataArray(convert(Array{Bool}, d), m)
end

# Convert a DataArray to a PooledDataArray
PooledDataArray{T}(da::DataArray{T}) = PooledDataArray(da.data, da.na)

# Convert a Array{T} to a PooledDataArray
PooledDataArray{T}(a::Array{T}) = PooledDataArray(a, falses(size(a)))

# Convert a BitVector to a Vector{Bool} w/o specified missingness
function PooledDataArray(a::BitArray)
    PooledDataArray(convert(Array{Bool}, a), falses(size(a)))
end

# Explicitly convert Ranges into a PooledDataVector
PooledDataArray(r::Ranges) = PooledDataArray([r], falses(length(r)))

# Construct an all-NA PooledDataVector of a specific type
PooledDataArray(t::Type, dims::Int...) = PooledDataArray(Array(t, dims...), trues(dims...))

# Specify just a vector and a pool
function PooledDataArray{T}(d::Array{T}, pool::Vector{T})
    PooledDataArray(d, pool, falses(size(d)))
end

# Initialized constructors with 0's, 1's
for (f, basef) in ((:pdatazeros, :zeros), (:pdataones, :ones))
    @eval begin
        ($f)(dims::Int...) = PooledDataArray(($basef)(dims...), falses(dims...))
        ($f)(t::Type, dims::Int...) = PooledDataArray(($basef)(t, dims...), falses(dims...))
    end
end

# Initialized constructors with false's or true's
for (f, basef) in ((:pdatafalses, :falses), (:pdatatrues, :trues))
    @eval begin
        ($f)(dims::Int...) = PooledDataArray(($basef)(dims...), falses(dims...))
    end
end

# Super hacked-out constructor: PooledDataVector[1, 2, 2, NA]
function ref(::Type{PooledDataVector}, vals...)
    # For now, just create a DataVector and then convert it
    # TODO: Rewrite for speed
    PooledDataArray(DataVector[vals...])
end

##############################################################################
##
## Basic size properties of all Data* objects
##
##############################################################################

size(pda::PooledDataArray) = size(pda.refs)
length(pda::PooledDataArray) = length(pda.refs)
endof(pda::PooledDataArray) = endof(pda.refs)

##############################################################################
##
## Copying Data* objects
##
##############################################################################

copy(pda::PooledDataArray) = PooledDataArray(copy(pda.refs),
                                             copy(pda.pool))
# TODO: Implement copy_to()

##############################################################################
##
## Predicates, including the new isna()
##
##############################################################################

function isnan(pda::PooledDataArray)
    PooledDataArray(copy(pda.refs), isnan(pda.pool))
end

function isfinite(pda::PooledDataArray)
    PooledDataArray(copy(pda.refs), isfinite(pda.pool))
end

isna(pda::PooledDataArray) = pda.refs .== 0

##############################################################################
##
## PooledDataArray utilities
##
## TODO: Add methods with these names for DataArray's
##       Decide whether levels() or unique() is primitive. Make the other
##       an alias.
##
##############################################################################

# Convert a PooledDataVector{T} to a DataVector{T}
function values{T}(pda::PooledDataArray{T})
    res = DataArray(T, size(pda)...)
    for i in 1:length(pda)
        r = pda.refs[i]
        if r == 0
            res[i] = NA
        else
            res[i] = pda.pool[r]
        end
    end
    return res
end
DataArray(pda::PooledDataArray) = values(pda)
values(da::DataArray) = copy(da)
values(a::Array) = copy(a)

function unique{T}(x::PooledDataArray{T})
    if any(x.refs .== 0)
        n = length(x.pool)
        d = Array(T, n + 1)
        for i in 1:n
            d[i] = x.pool[i]
        end
        m = falses(n + 1)
        m[n + 1] = true
        return DataArray(d, m)
    else
        return DataArray(copy(x.pool), falses(length(x.pool)))
    end
end
levels{T}(pdv::PooledDataArray{T}) = unique(pdv)

function unique{T}(adv::AbstractDataVector{T})
  values = Dict{Union(T, NAtype), Bool}()
  for i in 1:length(adv)
    values[adv[i]] = true
  end
  unique_values = keys(values)
  res = DataArray(T, length(unique_values))
  for i in 1:length(unique_values)
    res[i] = unique_values[i]
  end
  return res
end
levels{T}(adv::AbstractDataVector{T}) = unique(adv)

get_indices{T}(x::PooledDataArray{T}) = x.refs

function index_to_level{T}(x::PooledDataArray{T})
    d = Dict{POOLED_DATA_VEC_REF_TYPE, T}()
    for i in POOLED_DATA_VEC_REF_CONVERTER(1:length(x.pool))
        d[i] = x.pool[i]
    end
    return d
end

function level_to_index{T}(x::PooledDataArray{T})
    d = Dict{T, POOLED_DATA_VEC_REF_TYPE}()
    for i in POOLED_DATA_VEC_REF_CONVERTER(1:length(x.pool))
        d[x.pool[i]] = i
    end
    d
end

##############################################################################
##
## similar()
##
##############################################################################

similar(pda::PooledDataArray) = pda

function similar(pda::PooledDataArray, dims::Int...)
    PooledDataArray(fill(uint16(0), dims...), pda.pool)
end

function similar(pda::PooledDataArray, dims::Dims)
    PooledDataArray(fill(uint16(0), dims), pda.pool)
end

##############################################################################
##
## find()
##
##############################################################################

find(pdv::PooledDataVector{Bool}) = find(values(pdv))

##############################################################################
##
## ref()
##
##############################################################################

# pda[SingleItemIndex]
function ref(pda::PooledDataArray, i::Real)
    if pda.refs[i] == 0
        return NA
    else
        return pda.pool[pda.refs[i]]
    end
end

# pda[MultiItemIndex]
function ref(pda::PooledDataArray, inds::AbstractDataVector{Bool})
    inds = find(replaceNA(inds, false))
    return PooledDataArray(pda.refs[inds], copy(pda.pool))
end
function ref(pda::PooledDataArray, inds::AbstractDataVector)
    inds = removeNA(inds)
    return PooledDataArray(pda.refs[inds], copy(pda.pool))
end
function ref(pda::PooledDataArray, inds::Union(Vector, BitVector, Ranges))
    return PooledDataArray(pda.refs[inds], copy(pda.pool))
end

# pdm[SingleItemIndex, SingleItemIndex)
function ref(pda::PooledDataArray, i::Real, j::Real)
    if pda.refs[i, j] == 0
        return NA
    else
        return pda.pool[pda.refs[i, j]]
    end
end

# pda[SingleItemIndex, MultiItemIndex]
function ref(pda::PooledDataArray, i::Real, col_inds::AbstractDataVector{Bool})
    ref(pda, i, find(replaceNA(col_inds, false)))
end
function ref(pda::PooledDataArray, i::Real, col_inds::AbstractDataVector)
    ref(pda, i, removeNA(col_inds))
end
# TODO: Make inds::AbstractVector
function ref(pda::PooledDataArray,
             i::Real,
             col_inds::Union(Vector, BitVector, Ranges))
    error("not yet implemented")
    PooledDataArray(pda.refs[i, col_inds], pda.pool[i, col_inds])
end

# pda[MultiItemIndex, SingleItemIndex]
function ref(pda::PooledDataArray, row_inds::AbstractDataVector{Bool}, j::Real)
    ref(pda, find(replaceNA(row_inds, false)), j)
end
function ref(pda::PooledDataArray, row_inds::AbstractVector, j::Real)
    ref(pda, removeNA(row_inds), j)
end
# TODO: Make inds::AbstractVector
function ref(pda::PooledDataArray,
             row_inds::Union(Vector, BitVector, Ranges),
             j::Real)
    error("not yet implemented")
    PooledDataArray(pda.refs[row_inds, j], pda.pool[row_inds, j])
end

# pda[MultiItemIndex, MultiItemIndex]
function ref(pda::PooledDataArray,
             row_inds::AbstractDataVector{Bool},
             col_inds::AbstractDataVector{Bool})
    ref(pda, find(replaceNA(row_inds, false)), find(replaceNA(col_inds, false)))
end
function ref(pda::PooledDataArray,
             row_inds::AbstractDataVector{Bool},
             col_inds::AbstractDataVector)
    ref(pda, find(replaceNA(row_inds, false)), removeNA(col_inds))
end
# TODO: Make inds::AbstractVector
function ref(pda::PooledDataArray,
             row_inds::AbstractDataVector{Bool},
             col_inds::Union(Vector, BitVector, Ranges))
    ref(pda, find(replaceNA(row_inds, false)), col_inds)
end
function ref(pda::PooledDataArray,
             row_inds::AbstractDataVector,
             col_inds::AbstractDataVector{Bool})
    ref(pda, removeNA(row_inds), find(replaceNA(col_inds, false)))
end
function ref(pda::PooledDataArray,
             row_inds::AbstractDataVector,
             col_inds::AbstractDataVector)
    ref(pda, removeNA(row_inds), removeNA(col_inds))
end
# TODO: Make inds::AbstractVector
function ref(pda::PooledDataArray,
             row_inds::AbstractDataVector,
             col_inds::Union(Vector, BitVector, Ranges))
    ref(pda, removeNA(row_inds), col_inds)
end
# TODO: Make inds::AbstractVector
function ref(pda::PooledDataArray,
             row_inds::Union(Vector, BitVector, Ranges),
             col_inds::AbstractDataVector{Bool})
    ref(pda, row_inds, find(replaceNA(col_inds, false)))
end
# TODO: Make inds::AbstractVector
function ref(pda::PooledDataArray,
             row_inds::Union(Vector, BitVector, Ranges),
             col_inds::AbstractDataVector)
    ref(pda, row_inds, removeNA(col_inds))
end
# TODO: Make inds::AbstractVector
function ref(pda::PooledDataArray,
             row_inds::Union(Vector, BitVector, Ranges),
             col_inds::Union(Vector, BitVector, Ranges))
    error("not yet implemented")
    PooledDataArray(pda.refs[row_inds, col_inds], pda.pool[row_inds, col_inds])
end

##############################################################################
##
## assign() definitions
##
##############################################################################

# x[SingleIndex] = NA
# TODO: Delete values from pool that no longer exist?
function assign(x::PooledDataArray, val::NAtype, ind::Real)
    x.refs[ind] = 0
    return NA
end

# x[SingleIndex] = Single Item
# TODO: Delete values from pool that no longer exist?
function assign(x::PooledDataArray, val::Any, ind::Real)
    val = convert(eltype(x), val)
    pool_idx = findfirst(x.pool, val)
    if pool_idx > 0
        x.refs[ind] = pool_idx
    else
        push!(x.pool, val)
        x.refs[ind] = length(x.pool)
    end
    return val
end

# x[MultiIndex] = NA
# TODO: Find a way to delete the next four methods
function assign(x::PooledDataArray{NAtype},
                val::NAtype,
                inds::AbstractVector{Bool})
    error("Don't use PooledDataVector{NAtype}'s")
end
function assign(x::PooledDataArray{NAtype},
                val::NAtype,
                inds::AbstractVector)
    error("Don't use PooledDataVector{NAtype}'s")
end
function assign(x::PooledDataArray, val::NAtype, inds::AbstractVector{Bool})
    inds = find(inds)
    x.refs[inds] = 0
    return NA
end
function assign(x::PooledDataArray, val::NAtype, inds::AbstractVector)
    x.refs[inds] = 0
    return NA
end

# pda[MultiIndex] = Multiple Values
function assign(pda::PooledDataArray,
                vals::AbstractVector,
                inds::AbstractVector{Bool})
    assign(pda, vals, find(inds))
end
function assign(pda::PooledDataArray,
                vals::AbstractVector,
                inds::AbstractVector)
    for (val, ind) in zip(vals, inds)
        pda[ind] = val
    end
    return vals
end

# pda[SingleItemIndex, SingleItemIndex] = NA
function assign(pda::PooledDataMatrix, val::NAtype, i::Real, j::Real)
    pda.refs[i, j] = POOLED_DATA_VEC_REF_CONVERTER(0)
    return NA
end
# pda[SingleItemIndex, SingleItemIndex] = Single Item
function assign{T}(pda::PooledDataMatrix{T}, val::Any, i::Real, j::Real)
    val = convert(T, val)
    pool_idx = findfirst(x.pool, val)
    if pool_idx > 0
        pda.refs[i, j] = pool_idx
    else
        push!(pda.pool, val)
        pda.refs[i, j] = length(pda.pool)
    end
    return val
end

##############################################################################
##
## show() and similar methods
##
##############################################################################

function string(x::PooledDataVector)
    tmp = join(x, ", ")
    return "[$tmp]"
end

# Need assign()'s to make this work
function show(io::IO, pda::PooledDataArray)
    invoke(show, (Any, AbstractArray), io, pda)
    print(io, "\nlevels: ")
    print(io, levels(pda))
end

##############################################################################
##
## Replacement operations
##
##############################################################################

function replace!(x::PooledDataArray{NAtype}, fromval::NAtype, toval::NAtype)
    NA # no-op to deal with warning
end
function replace!(x::PooledDataArray, fromval::NAtype, toval::NAtype)
    NA # no-op to deal with warning
end
function replace!{S, T}(x::PooledDataArray{S}, fromval::T, toval::NAtype)
    fromidx = findfirst(x.pool, fromval)
    if fromidx == 0
        error("can't replace a value not in the pool in a PooledDataVector!")
    end

    x.refs[x.refs .== fromidx] = 0

    return NA
end
function replace!{S, T}(x::PooledDataArray{S}, fromval::NAtype, toval::T)
    toidx = findfirst(x.pool, toval)
    # if toval is in the pool, just do the assignment
    if toidx != 0
        x.refs[x.refs .== 0] = toidx
    else
        # otherwise, toval is new, add it to the pool
        push!(x.pool, toval)
        x.refs[x.refs .== 0] = length(x.pool)
    end

    return toval
end
function replace!{R, S, T}(x::PooledDataArray{R}, fromval::S, toval::T)
    # throw error if fromval isn't in the pool
    fromidx = findfirst(x.pool, fromval)
    if fromidx == 0
        error("can't replace a value not in the pool in a PooledDataArray!")
    end

    # if toval is in the pool too, use that and remove fromval from the pool
    toidx = findfirst(x.pool, toval)
    if toidx != 0
        x.refs[x.refs .== fromidx] = toidx
        #x.pool[fromidx] = None    TODO: what to do here??
    else
        # otherwise, toval is new, swap it in
        x.pool[fromidx] = toval
    end

    return toval
end

##############################################################################
##
## Sorting can use the pool to speed things up
##
##############################################################################

order(pda::PooledDataArray) = groupsort_indexer(pda)[1]
sort(pda::PooledDataArray) = pd[order(pda)]

##############################################################################
##
## PooledDataVecs: EXPLANATION SHOULD GO HERE
##
##############################################################################

function PooledDataVecs{S, T}(v1::AbstractDataVector{S},
                              v2::AbstractDataVector{T})

    ## Return two PooledDataVecs that share the same pool.

    refs1 = Array(POOLED_DATA_VEC_REF_TYPE, length(v1))
    refs2 = Array(POOLED_DATA_VEC_REF_TYPE, length(v2))
    poolref = Dict{T, POOLED_DATA_VEC_REF_TYPE}(length(v1))
    maxref = 0

    # loop through once to fill the poolref dict
    for i = 1:length(v1)
        poolref[v1[i]] = 0
    end
    for i = 1:length(v2)
        poolref[v2[i]] = 0
    end

    # fill positions in poolref
    pool = sort(keys(poolref))
    i = 1
    for p in pool
        poolref[p] = i
        i += 1
    end

    # fill in newrefs
    for i = 1:length(v1)
        refs1[i] = poolref[v1[i]]
    end
    for i = 1:length(v2)
        refs2[i] = poolref[v2[i]]
    end

    return (PooledDataArray(refs1, pool),
            PooledDataArray(refs2, pool))
end
