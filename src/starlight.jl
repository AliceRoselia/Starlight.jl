module starlight

using Colors

export fitn
export F, VectorF, Point4, Vector4
export BlankCanvas
export pixel, pixel!
export x, x!, y, y!, z, z!, height, width
export pixels, flat

function fitn(vec = [], n::Int = 3)
    """
        fit Vector4 to n elements, i.e. truncate or pad.
        defaults to n = 3 because that's my use case.
    """
    if length(vec) == 0
        return [0.0, 0.0, 0.0]
    else
        return vcat(vec[1:min(n, length(vec))], repeat([AbstractFloat(0)], max(0, n - length(vec))))
    end
end

# Point4 and Vector4 are just length-4 arrays with particular valuesin the last index

function Point4(coords = [])
    return vcat(fitn(coords), [AbstractFloat(1)])
end

function Vector4(coords = [])
    return vcat(fitn(coords), [AbstractFloat(0)])
end

F = T where T<:AbstractFloat
VectorF = Vector{T} where T<:AbstractFloat

function GetIndexOrWarn(vec::VectorF, i::Int, sym::Symbol)
    if length(vec) >= i
        return vec[i]
    else
        @warn "vector must have length at least $(String(i)) to interpret index $(String(i)) as its $(String(sym)) component"
        return nothing
    end
end

x(vec::VectorF) = GetIndexOrWarn(vec, 1, :x)
y(vec::VectorF) = GetIndexOrWarn(vec, 2, :y)
z(vec::VectorF) = GetIndexOrWarn(vec, 3, :z)
w(vec::VectorF) = GetIndexOrWarn(vec, 4, :w)

function SetIndexOrWarn!(vec::VectorF, i::Int, sym::Symbol, val::T where T<:AbstractFloat)
    if length(vec) >= i
        vec[i] = val
    else
        @warn "vector must have length at least $(String(i)) to interpret index $(String(i)) as its $(String(sym)) component"
        return nothing
    end
end

x!(vec::VectorF, val::F) = SetIndexOrWarn!(vec, 1, :x, val)
y!(vec::VectorF, val::F) = SetIndexOrWarn!(vec, 2, :y, val)
z!(vec::VectorF, val::F) = SetIndexOrWarn!(vec, 3, :z, val)
w!(vec::VectorF, val::F) = SetIndexOrWarn!(vec, 4, :w, val)

# height is number of rows, which in julia is the first dimension.
# width is number of columns, which in julia is the second dimension.
BlankCanvas(w::Int, h::Int) = fill(colorant"black", (h, w))
height(mat) = size(mat)[1]
width(mat) = size(mat)[2]
pixel(mat, x::Int, y::Int) = mat[x,y]
pixel!(mat, x::Int, y::Int, c::Colorant) = mat[x,y] = c
pixels(mat) = flat(mat)
flat(mat) = reshape(mat, (prod(size(mat)), 1))

end
