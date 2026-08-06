module DGGSexplorer

using DGGS
using Oxygen
using OteraEngine
using HTTP
using DimensionalData
import DimensionalData as DD
using JSON3
using ColorSchemes
using FileIO
using ColorTypes
using ImageCore
using Makie
using Extents
using GeometryBasics

DGGSMakie = Base.get_extension(DGGS, :DGGSMakie)

include("plot.jl")
include("webserver.jl")

export serve, Collection
end
